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

variable "certificate_arn" {
  description = "ACM certificate ARN for an HTTPS listener - leave null (the default) to run HTTP-only, e.g. when there's no domain/cert for this environment yet. Set it and the ALB adds an HTTPS listener and redirects HTTP to it instead of forwarding HTTP directly."
  type        = string
  default     = null

  validation {
    # Every downstream `var.certificate_arn == null` check treats "" as "set"
    # (it isn't null), which would create an HTTPS listener with an empty
    # certificate_arn and fail at apply time with an opaque AWS API error -
    # catch that here instead, with a message that says what's actually wrong.
    condition     = var.certificate_arn == null || length(var.certificate_arn) > 0
    error_message = "certificate_arn must be null (to skip HTTPS) or a non-empty ACM certificate ARN - not an empty string."
  }
}
