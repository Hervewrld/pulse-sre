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
