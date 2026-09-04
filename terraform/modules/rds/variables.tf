variable "name" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "security_group_id" {
  description = "Security group allowing Postgres access from the app services (from modules/security_groups)."
  type        = string
}

variable "instance_class" {
  type    = string
  default = "db.t4g.micro"
}

variable "allocated_storage_gb" {
  type    = number
  default = 20
}

variable "multi_az" {
  type    = bool
  default = false
}

variable "deletion_protection" {
  description = "Blocks terraform destroy / console deletion without first disabling this. Set true for any environment holding data you can't casually lose."
  type        = bool
  default     = false
}

variable "engine_version" {
  type    = string
  default = "16.4"
}

variable "database_name" {
  type    = string
  default = "pulse"
}

variable "master_username" {
  type    = string
  default = "pulse"
}

variable "backup_retention_days" {
  type    = number
  default = 7
}

variable "password_rotation_days" {
  type    = number
  default = 30
}
