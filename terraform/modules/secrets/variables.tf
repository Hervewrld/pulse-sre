variable "name" {
  description = "Name prefix (e.g. \"pulse-dev\")."
  type        = string
}

variable "secrets" {
  description = "Map of secret key (e.g. \"slack_webhook_url\") -> description. Terraform only creates the secret container, never a value - real credentials are set out-of-band so they never pass through a .tf file, a plan, or state."
  type        = map(string)
  default     = {}
}
