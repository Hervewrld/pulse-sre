# One task definition + ECS service per Pulse service (api/scheduler/checker) -
# instantiated three times from environments/{dev,prod}/main.tf with different
# ports, secrets and ALB/service-discovery wiring, sharing this one definition
# so the three don't drift apart in how they're deployed.

locals {
  # A container-level health check is what lets ECS (and the deployment
  # circuit breaker below) tell "started but broken" apart from "actually
  # serving traffic" - without one, a task that starts but never actually
  # works still counts as RUNNING and a bad deploy never gets caught or
  # rolled back. api/checker get an HTTP check (the command reuses
  # docker-compose's own python-urllib check for api - docker-compose.yml
  # has none for checker to reuse, but both expose /health, see
  # src/checker/main.py); scheduler has no HTTP server to check, so it's
  # expected to pass health_check_command instead (a heartbeat-file freshness
  # check - see src/scheduler/main.py) rather than get no check at all.
  container_health_check = (
    var.container_port != null ? {
      command = [
        "CMD-SHELL",
        "python -c \"import urllib.request; urllib.request.urlopen('http://localhost:${var.container_port}${var.health_check_path}')\" || exit 1",
      ]
      } : var.health_check_command != null ? {
      command = var.health_check_command
    } : null
  )

  container_definition = merge(
    {
      name      = var.name
      image     = var.image
      essential = true
      portMappings = var.container_port == null ? [] : [
        {
          containerPort = var.container_port
          protocol      = "tcp"
        }
      ]
      environment = var.environment
      # AWS's container definition schema wants "valueFrom" (camelCase); the
      # var's value_from (matching Terraform's snake_case convention) would
      # otherwise pass through jsonencode as the literal wrong key and make
      # RegisterTaskDefinition reject the whole task definition.
      secrets = [for s in var.secrets : { name = s.name, valueFrom = s.value_from }]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = var.log_group_name
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = var.name
        }
      }
    },
    local.container_health_check == null ? {} : {
      healthCheck = merge(local.container_health_check, {
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 10
      })
    }
  )
}

resource "aws_ecs_task_definition" "this" {
  family                   = "${var.project_name}-${var.name}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = tostring(var.cpu)
  memory                   = tostring(var.memory)
  execution_role_arn       = var.execution_role_arn
  task_role_arn            = var.task_role_arn

  container_definitions = jsonencode([local.container_definition])
}

# Only created when this service needs to be reachable from other ECS services
# by name (e.g. checker, called by both api and scheduler) - a service with no
# callers besides the ALB (api) or no callers at all (scheduler) skips this.
resource "aws_service_discovery_service" "this" {
  count = var.service_discovery_namespace_id == null ? 0 : 1

  name = var.name

  dns_config {
    namespace_id = var.service_discovery_namespace_id

    dns_records {
      ttl  = 10
      type = "A"
    }

    routing_policy = "MULTIVALUE"
  }

  # No health_check_custom_config: nothing in the app calls Cloud Map's
  # UpdateInstanceCustomHealthStatus, so a custom health check here would sit
  # permanently "healthy" and never actually reflect task health - it'd be a
  # decoration, not a signal. Instances still come and go correctly because
  # aws_ecs_service (service_registries below) registers/deregisters this
  # Cloud Map entry itself as tasks start and stop.
}

resource "aws_ecs_service" "this" {
  name            = "${var.project_name}-${var.name}"
  cluster         = var.cluster_id
  task_definition = aws_ecs_task_definition.this.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = [var.security_group_id]
    assign_public_ip = false
  }

  # ECS's own defaults (100%/200%) let a rolling deploy briefly run
  # ceil(desired_count * 2.0) tasks - fine for a stateless service like api,
  # but wrong for anything (scheduler) that must never run more than one
  # instance at a time. Callers that need that guarantee pass 0/100 instead.
  deployment_minimum_healthy_percent = var.deployment_minimum_healthy_percent
  deployment_maximum_percent         = var.deployment_maximum_percent

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  # Makes `terraform apply` block until the new tasks are stable, and (per the
  # AWS provider's own handling of deployment_circuit_breaker) fail if a
  # circuit breaker rollback happened along the way - ECS has already done the
  # actual rollback by the time terraform reports it either way.
  # .github/workflows/deploy.yml treats that apply failure as its first
  # "automatic rollback on failure" signal, but doesn't only trust it: right
  # after apply, that workflow separately calls DescribeServices/
  # DescribeTaskDefinition and fails the job if the PRIMARY deployment's image
  # isn't this build's tag - so even if this waiter ever reported "stable"
  # without noticing a rollback (the old task definition satisfying the same
  # stability check the new one would have), the pipeline still catches it.
  wait_for_steady_state = true

  timeouts {
    update = "10m"
  }

  dynamic "load_balancer" {
    for_each = var.target_group_arn == null ? [] : [1]
    content {
      target_group_arn = var.target_group_arn
      container_name   = var.name
      container_port   = var.container_port
    }
  }

  health_check_grace_period_seconds = var.target_group_arn == null ? null : var.health_check_grace_period_seconds

  dynamic "service_registries" {
    for_each = var.service_discovery_namespace_id == null ? [] : [1]
    content {
      registry_arn = aws_service_discovery_service.this[0].arn
    }
  }
}
