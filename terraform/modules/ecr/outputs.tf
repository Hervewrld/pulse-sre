output "repository_urls" {
  description = "Map of service name -> ECR repository URL, for `docker push` and task definitions."
  value       = { for name, repo in aws_ecr_repository.this : name => repo.repository_url }
}

output "repository_arns" {
  description = "Map of service name -> ECR repository ARN, for scoping each service's IAM execution role."
  value       = { for name, repo in aws_ecr_repository.this : name => repo.arn }
}
