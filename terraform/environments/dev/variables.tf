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
  description = "Service names that get an ECR repository and IAM roles here, and (in Phase 6) an ECS service - single source of truth so the two stay in sync."
  type        = list(string)
  default     = ["api", "scheduler", "checker"]
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
