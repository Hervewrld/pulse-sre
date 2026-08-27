terraform {
  required_version = ">= 1.9"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Filled in via `terraform init -backend-config=backend.hcl`, using the
  # bucket/table names output by terraform/bootstrap. Keeping those values out
  # of version control means the same config works in any AWS account.
  backend "s3" {
    key = "pulse/dev/terraform.tfstate"
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = "pulse"
      Environment = "dev"
      ManagedBy   = "terraform"
    }
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}
