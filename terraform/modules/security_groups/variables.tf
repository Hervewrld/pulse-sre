variable "name" {
  description = "Name prefix (e.g. \"pulse-dev\")."
  type        = string
}

variable "vpc_id" {
  type = string
}

variable "alb_security_group_id" {
  description = "The ALB's security group - api's security group allows inbound from this on its container port."
  type        = string
}

variable "api_container_port" {
  type    = number
  default = 8000
}

variable "checker_container_port" {
  type    = number
  default = 8001
}

variable "db_port" {
  type    = number
  default = 5432
}
