variable "name" {
  description = "Environment prefix (e.g. \"pulse-dev\") - keeps dev's and prod's repositories from colliding, since ECR repository names are unique per account/region, not per Terraform state."
  type        = string
}

variable "repository_names" {
  description = "Names of the ECR repositories to create, one per service."
  type        = list(string)
  default     = ["api", "scheduler", "checker"]
}

variable "untagged_image_expiry_days" {
  description = "Days after which untagged images are expired by the lifecycle policy."
  type        = number
  default     = 14
}
