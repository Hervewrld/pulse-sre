output "api_security_group_id" {
  value = aws_security_group.api.id
}

output "scheduler_security_group_id" {
  value = aws_security_group.scheduler.id
}

output "checker_security_group_id" {
  value = aws_security_group.checker.id
}

output "db_security_group_id" {
  value = aws_security_group.db.id
}

output "grafana_security_group_id" {
  value = aws_security_group.grafana.id
}
