output "execution_role_arns" {
  value = { for name, role in aws_iam_role.execution : name => role.arn }
}

output "task_role_arns" {
  value = { for name, role in aws_iam_role.task : name => role.arn }
}

output "log_group_names" {
  value = { for name, lg in aws_cloudwatch_log_group.this : name => lg.name }
}
