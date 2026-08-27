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
