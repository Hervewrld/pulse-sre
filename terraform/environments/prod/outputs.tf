output "alb_dns_name" {
  value = module.alb.alb_dns_name
}

output "api_target_group_arn" {
  value = module.alb.api_target_group_arn
}

output "ecr_repository_urls" {
  value = module.ecr.repository_urls
}

output "ecs_cluster_name" {
  value = module.ecs_cluster.cluster_name
}

output "service_discovery_namespace_id" {
  value = module.ecs_cluster.service_discovery_namespace_id
}

output "execution_role_arns" {
  value = module.iam.execution_role_arns
}

output "task_role_arns" {
  value = module.iam.task_role_arns
}

output "db_endpoint" {
  value = module.rds.endpoint
}

output "db_master_user_secret_arn" {
  value = module.rds.master_user_secret_arn
}

output "security_group_ids" {
  value = {
    api       = module.security_groups.api_security_group_id
    scheduler = module.security_groups.scheduler_security_group_id
    checker   = module.security_groups.checker_security_group_id
  }
}

output "ecs_service_names" {
  value = {
    api       = module.ecs_service_api.service_name
    scheduler = module.ecs_service_scheduler.service_name
    checker   = module.ecs_service_checker.service_name
  }
}

output "slack_webhook_secret_arn" {
  description = "Set the real value with: aws secretsmanager put-secret-value --secret-id <this arn> --secret-string '<webhook url>'"
  value       = module.secrets.secret_arns["slack_webhook_url"]
}
