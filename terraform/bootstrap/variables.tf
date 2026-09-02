variable "region" {
  description = "AWS region the state backend lives in."
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Short name used to prefix backend resources (bucket, lock table)."
  type        = string
  default     = "pulse"
}

variable "github_org" {
  description = "GitHub org/user that owns the repo - scopes which workflow runs may assume the deploy role below."
  type        = string
  default     = "Hervewrld"
}

variable "github_repo" {
  type    = string
  default = "pulse-sre"
}
