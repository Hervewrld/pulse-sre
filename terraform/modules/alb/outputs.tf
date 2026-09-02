output "alb_dns_name" {
  value = aws_lb.this.dns_name
}

output "alb_security_group_id" {
  value = aws_security_group.alb.id
}

output "api_target_group_arn" {
  description = "Phase 6's api ECS service registers its tasks into this target group."
  value       = aws_lb_target_group.api.arn
}

output "alb_arn_suffix" {
  description = "CloudWatch's AWS/ApplicationELB metrics use this short form (e.g. \"app/pulse-dev-alb/50dc6c495c0c9188\"), not the full ARN - modules/observability's LoadBalancer dimension."
  value       = aws_lb.this.arn_suffix
}

output "api_target_group_arn_suffix" {
  description = "Same arn_suffix format as alb_arn_suffix, for CloudWatch's TargetGroup dimension."
  value       = aws_lb_target_group.api.arn_suffix
}
