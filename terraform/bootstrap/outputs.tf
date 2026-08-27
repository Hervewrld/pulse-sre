output "state_bucket" {
  description = "S3 bucket holding Terraform remote state - use as `bucket` in each environment's backend.hcl."
  value       = aws_s3_bucket.state.id
}

output "lock_table" {
  description = "DynamoDB table for state locking - use as `dynamodb_table` in each environment's backend.hcl."
  value       = aws_dynamodb_table.lock.name
}

output "region" {
  value = var.region
}
