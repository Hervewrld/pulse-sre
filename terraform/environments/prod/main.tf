locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 2)
}

module "vpc" {
  source = "../../modules/vpc"

  name = var.name
  azs  = local.azs
  # Prod: one NAT gateway per AZ, so a NAT/AZ failure only takes out that
  # AZ's egress, not the whole environment's.
  single_nat_gateway = false
}

module "ecr" {
  source = "../../modules/ecr"

  name             = var.name
  repository_names = var.services
}

module "alb" {
  source = "../../modules/alb"

  name              = var.name
  vpc_id            = module.vpc.vpc_id
  public_subnet_ids = module.vpc.public_subnet_ids
  target_port       = var.api_container_port
  grafana_port      = var.grafana_container_port
}

module "security_groups" {
  source = "../../modules/security_groups"

  name                   = var.name
  vpc_id                 = module.vpc.vpc_id
  alb_security_group_id  = module.alb.alb_security_group_id
  api_container_port     = var.api_container_port
  checker_container_port = var.checker_container_port
  grafana_container_port = var.grafana_container_port
}

module "ecs_cluster" {
  source = "../../modules/ecs_cluster"

  name   = var.name
  vpc_id = module.vpc.vpc_id
}

module "rds" {
  source = "../../modules/rds"

  name               = var.name
  private_subnet_ids = module.vpc.private_subnet_ids
  security_group_id  = module.security_groups.db_security_group_id

  instance_class        = "db.t4g.small"
  allocated_storage_gb  = 50
  multi_az              = true
  backup_retention_days = 14
  deletion_protection   = true
}

module "secrets" {
  source = "../../modules/secrets"

  name = var.name
  secrets = {
    slack_webhook_url = "Slack incoming webhook URL the checker service posts down/recovered alerts to (Phase 2)."
  }
}

module "iam" {
  source = "../../modules/iam"

  name                = var.name
  services            = var.services
  ecr_repository_arns = module.ecr.repository_arns

  secret_arns = {
    api       = [module.rds.master_user_secret_arn]
    scheduler = [module.rds.master_user_secret_arn]
    checker   = [module.rds.master_user_secret_arn, module.secrets.secret_arns["slack_webhook_url"]]
    grafana   = [module.rds.master_user_secret_arn]
  }
}

locals {
  checker_dns_name = "checker.${var.name}.local"

  db_environment = [
    { name = "DB_HOST", value = module.rds.address },
    { name = "DB_PORT", value = tostring(module.rds.port) },
    { name = "DB_NAME", value = module.rds.database_name },
  ]
  db_secrets = [
    { name = "DB_USER", value_from = "${module.rds.master_user_secret_arn}:username::" },
    { name = "DB_PASSWORD", value_from = "${module.rds.master_user_secret_arn}:password::" },
  ]
}

module "ecs_service_api" {
  source = "../../modules/ecs_service"

  # module.iam.execution_role_arns resolves as soon as the IAM roles exist,
  # not once aws_iam_role_policy.execution (in that module) is attached to
  # them - without this, a task can start before it's actually allowed to
  # pull its image or read its secrets, failing with ResourceInitializationError.
  depends_on = [module.iam]

  name         = "api"
  project_name = var.name
  region       = var.region
  cluster_id   = module.ecs_cluster.cluster_id

  image          = "${module.ecr.repository_urls["api"]}:${var.image_tag}"
  container_port = var.api_container_port
  enable_xray    = true
  # Two tasks across two AZs, sized above the Fargate minimum - dev runs the
  # single-task/minimum-size default from modules/ecs_service instead.
  cpu           = 512
  memory        = 1024
  desired_count = 2

  execution_role_arn = module.iam.execution_role_arns["api"]
  task_role_arn      = module.iam.task_role_arns["api"]
  log_group_name     = module.iam.log_group_names["api"]

  # No CHECKER_URL here: src/api never calls checker (only src/scheduler does,
  # see local.checker_dns_name below), and the checker security group only
  # allows inbound from scheduler's SG anyway - api couldn't reach it if it tried.
  environment = local.db_environment
  secrets     = local.db_secrets

  subnet_ids        = module.vpc.private_subnet_ids
  security_group_id = module.security_groups.api_security_group_id
  target_group_arn  = module.alb.api_target_group_arn
}

module "ecs_service_checker" {
  source = "../../modules/ecs_service"

  depends_on = [module.iam]

  name         = "checker"
  project_name = var.name
  region       = var.region
  cluster_id   = module.ecs_cluster.cluster_id

  image          = "${module.ecr.repository_urls["checker"]}:${var.image_tag}"
  container_port = var.checker_container_port
  enable_xray    = true
  cpu            = 512
  memory         = 1024
  desired_count  = 2

  execution_role_arn = module.iam.execution_role_arns["checker"]
  task_role_arn      = module.iam.task_role_arns["checker"]
  log_group_name     = module.iam.log_group_names["checker"]

  environment = local.db_environment
  secrets = concat(local.db_secrets, [
    { name = "SLACK_WEBHOOK_URL", value_from = module.secrets.secret_arns["slack_webhook_url"] },
  ])

  subnet_ids                     = module.vpc.private_subnet_ids
  security_group_id              = module.security_groups.checker_security_group_id
  service_discovery_namespace_id = module.ecs_cluster.service_discovery_namespace_id
}

module "ecs_service_scheduler" {
  source = "../../modules/ecs_service"

  depends_on = [module.iam]

  name         = "scheduler"
  project_name = var.name
  region       = var.region
  cluster_id   = module.ecs_cluster.cluster_id

  image       = "${module.ecr.repository_urls["scheduler"]}:${var.image_tag}"
  enable_xray = true

  execution_role_arn = module.iam.execution_role_arns["scheduler"]
  task_role_arn      = module.iam.task_role_arns["scheduler"]
  log_group_name     = module.iam.log_group_names["scheduler"]

  environment = concat(local.db_environment, [
    { name = "CHECKER_URL", value = "http://${local.checker_dns_name}:${var.checker_container_port}" },
  ])
  secrets = local.db_secrets

  # Exactly one scheduler task, always - see the matching comment in
  # environments/dev/main.tf.
  desired_count                      = 1
  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100

  subnet_ids        = module.vpc.private_subnet_ids
  security_group_id = module.security_groups.scheduler_security_group_id
}

module "ecs_service_grafana" {
  source = "../../modules/ecs_service"

  depends_on = [module.iam]

  name         = "grafana"
  project_name = var.name
  region       = var.region
  cluster_id   = module.ecs_cluster.cluster_id

  image          = "${module.ecr.repository_urls["grafana"]}:${var.image_tag}"
  container_port = var.grafana_container_port
  # Deliberately still 1 task, even in prod: Grafana's own state (sessions,
  # the provisioned-dashboard cache) lives in its embedded SQLite file, which
  # isn't shared across tasks - two replicas behind the same ALB would look
  # like two different Grafana instances randomly swapping in per request,
  # not real redundancy. Fine for now since the one thing that actually
  # matters here (the SLO dashboard) is provisioned from disk on every start
  # regardless - see docker/grafana/Dockerfile.
  #
  # 0/100 (not ECS's 100/200 default) makes that true even mid-deploy: without
  # it, a rolling deploy briefly runs two tasks anyway - exactly the dual-
  # instance problem desired_count=1 above is meant to avoid.
  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100

  execution_role_arn = module.iam.execution_role_arns["grafana"]
  task_role_arn      = module.iam.task_role_arns["grafana"]
  log_group_name     = module.iam.log_group_names["grafana"]

  # DB_HOST/DB_PORT/DB_NAME/DB_USER/DB_PASSWORD (local.db_environment/db_secrets)
  # are the exact env var names docker/grafana/entrypoint.sh reads to build
  # its Postgres datasource - same names Pulse's own src/common/config.py
  # uses, not a coincidence, just one fewer thing to keep in sync.
  environment = concat(local.db_environment, [
    { name = "GF_SERVER_ROOT_URL", value = "http://${module.alb.alb_dns_name}/grafana/" },
    { name = "GF_SERVER_SERVE_FROM_SUB_PATH", value = "true" },
  ])
  secrets = local.db_secrets

  subnet_ids        = module.vpc.private_subnet_ids
  security_group_id = module.security_groups.grafana_security_group_id
  target_group_arn  = module.alb.grafana_target_group_arn
}

module "observability" {
  source = "../../modules/observability"

  name   = var.name
  region = var.region

  alb_arn_suffix              = module.alb.alb_arn_suffix
  api_target_group_arn_suffix = module.alb.api_target_group_arn_suffix
  ecs_cluster_name            = module.ecs_cluster.cluster_name
  ecs_service_names = {
    api       = module.ecs_service_api.service_name
    scheduler = module.ecs_service_scheduler.service_name
    checker   = module.ecs_service_checker.service_name
    grafana   = module.ecs_service_grafana.service_name
  }
  log_group_names        = module.iam.log_group_names
  db_instance_identifier = module.rds.identifier
}
