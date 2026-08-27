variable "name" {
  description = "Name prefix (e.g. \"pulse-dev\")."
  type        = string
}

variable "services" {
  description = "Service names to create IAM roles and log groups for."
  type        = list(string)
  default     = ["api", "scheduler", "checker"]
}

variable "ecr_repository_arns" {
  description = "Map of service name -> ECR repository ARN, scoping each execution role's image-pull permission to its own image."
  type        = map(string)
}

variable "log_retention_days" {
  type    = number
  default = 30
}
