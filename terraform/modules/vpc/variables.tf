variable "name" {
  description = "Name prefix for VPC resources (e.g. \"pulse-dev\")."
  type        = string
}

variable "cidr_block" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "azs" {
  description = "Exactly two availability zones to spread subnets across."
  type        = list(string)

  validation {
    condition     = length(var.azs) == 2
    error_message = "Provide exactly two availability zones."
  }
}

variable "single_nat_gateway" {
  description = "Use one shared NAT gateway instead of one per AZ. Cheaper, less resilient - fine for dev, not for prod."
  type        = bool
  default     = true
}
