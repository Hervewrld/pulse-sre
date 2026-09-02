variable "name" {
  description = "Name prefix (e.g. \"pulse-dev\")."
  type        = string
}

variable "region" {
  type = string
}

variable "alb_arn_suffix" {
  type = string
}

variable "api_target_group_arn_suffix" {
  type = string
}

variable "ecs_cluster_name" {
  type = string
}

variable "ecs_service_names" {
  description = "Map of service name (api/scheduler/checker) -> actual ECS service name, for per-service CPU/memory alarms and dashboard widgets."
  type        = map(string)
}

variable "log_group_names" {
  description = "Map of service name -> CloudWatch Logs log group name, for the Logs Insights saved queries."
  type        = map(string)
}

variable "db_instance_identifier" {
  type = string
}
