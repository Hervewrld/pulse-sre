variable "name" {
  description = "Service name (e.g. \"api\") - used as the container name and, when service discovery is enabled, the DNS label."
  type        = string
}

variable "project_name" {
  description = "Environment name prefix (e.g. \"pulse-dev\"), used to namespace the task family and ECS service name."
  type        = string
}

variable "cluster_id" {
  type = string
}

variable "region" {
  type = string
}

variable "image" {
  description = "Full ECR image URI including tag, e.g. \"<account>.dkr.ecr.<region>.amazonaws.com/pulse-dev/api:abc1234\"."
  type        = string
}

variable "container_port" {
  description = "Port the container listens on, or null for a service with no inbound port (e.g. scheduler)."
  type        = number
  default     = null
}

variable "cpu" {
  type    = number
  default = 256
}

variable "memory" {
  type    = number
  default = 512
}

variable "desired_count" {
  type    = number
  default = 1
}

variable "execution_role_arn" {
  type = string
}

variable "task_role_arn" {
  type = string
}

variable "log_group_name" {
  type = string
}

variable "environment" {
  description = "Plain (non-secret) container environment variables."
  type        = list(object({ name = string, value = string }))
  default     = []
}

variable "secrets" {
  description = "Container environment variables sourced from Secrets Manager - resolved by the ECS agent using execution_role_arn, not visible in the task definition itself."
  type        = list(object({ name = string, value_from = string }))
  default     = []
}

variable "subnet_ids" {
  type = list(string)
}

variable "security_group_id" {
  type = string
}

variable "target_group_arn" {
  description = "ALB target group to register tasks with, or null for a service with no ALB (e.g. scheduler, checker)."
  type        = string
  default     = null
}

variable "service_discovery_namespace_id" {
  description = "Private DNS namespace to register this service in (as \"<name>.<namespace>\"), or null to skip service discovery."
  type        = string
  default     = null
}

variable "health_check_grace_period_seconds" {
  description = "Only applies when target_group_arn is set - how long ECS waits before acting on a failing ALB health check, so a slow-starting task isn't killed mid-boot."
  type        = number
  default     = 60
}

variable "deployment_minimum_healthy_percent" {
  description = "ECS's rolling-deployment floor. Default (100) matches ECS's own default - never drop below desired_count during a deploy."
  type        = number
  default     = 100
}

variable "deployment_maximum_percent" {
  description = "ECS's rolling-deployment ceiling. Default (200) matches ECS's own default. Set to 100 (alongside deployment_minimum_healthy_percent = 0) for a service that must never run more than desired_count instances at once, even briefly mid-deploy."
  type        = number
  default     = 200
}
