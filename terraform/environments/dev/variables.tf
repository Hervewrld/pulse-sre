variable "region" {
  type    = string
  default = "us-east-1"
}

variable "name" {
  description = "Name prefix for every resource in this environment."
  type        = string
  default     = "pulse-dev"
}

variable "services" {
  description = "Service names that get an ECR repository and IAM roles here, and (in Phase 6) an ECS service - single source of truth so the two stay in sync. grafana (Phase 11) is a custom image (docker/grafana/Dockerfile with Pulse's dashboard baked in), not one of the api/scheduler/checker images built from the shared docker/Dockerfile - it still follows this same per-service repo/IAM/service pattern."
  type        = list(string)
  default     = ["api", "scheduler", "checker", "grafana"]
}

variable "api_container_port" {
  description = "Port the api container listens on - shared between the ALB target group and the api security group so they can't drift apart."
  type        = number
  default     = 8000
}

variable "checker_container_port" {
  description = "Port the checker container listens on - shared with Phase 6's task definition so they can't drift apart."
  type        = number
  default     = 8001
}

variable "grafana_container_port" {
  description = "Port the grafana container listens on - shared between the ALB target group and the grafana security group so they can't drift apart."
  type        = number
  default     = 3000
}

variable "image_tag" {
  description = "Tag to deploy for all four service images (e.g. a git short SHA from scripts/push_images.sh). No default: ECR repositories are IMMUTABLE (see modules/ecr), so \"latest\" can only ever be pushed once - every real deploy needs its own tag."
  type        = string
}
