variable "name" {
  description = "Name prefix (e.g. \"pulse-dev\")."
  type        = string
}

variable "vpc_id" {
  type = string
}

variable "public_subnet_ids" {
  type = list(string)
}

variable "target_port" {
  description = "Port the api container listens on."
  type        = number
  default     = 8000
}

variable "health_check_path" {
  type    = string
  default = "/health"
}

variable "grafana_port" {
  description = "Port the grafana container listens on."
  type        = number
  default     = 3000
}
