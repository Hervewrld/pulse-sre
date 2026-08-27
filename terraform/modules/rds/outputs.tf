output "endpoint" {
  value = aws_db_instance.this.endpoint
}

output "address" {
  value = aws_db_instance.this.address
}

output "port" {
  value = aws_db_instance.this.port
}

output "master_user_secret_arn" {
  description = "Secrets Manager secret ARN holding the RDS-managed master credentials (JSON: username/password). Phase 6 wires this into the ECS task definitions' `secrets` block to build DATABASE_URL."
  value       = aws_db_instance.this.master_user_secret[0].secret_arn
}

output "database_name" {
  value = var.database_name
}
