resource "aws_ecs_cluster" "this" {
  name = var.name

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

resource "aws_ecs_cluster_capacity_providers" "this" {
  cluster_name = aws_ecs_cluster.this.name

  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
  }
}

# Internal DNS so the scheduler can reach the checker service at
# checker.<name>.local without a second, internal load balancer - empty until
# Phase 6 registers each ECS service here via service_registries.
resource "aws_service_discovery_private_dns_namespace" "this" {
  name = "${var.name}.local"
  vpc  = var.vpc_id
}
