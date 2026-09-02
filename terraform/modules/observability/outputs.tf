output "sns_topic_arn" {
  description = "Subscribe an endpoint (email, Slack via AWS Chatbot, PagerDuty, ...) to this out-of-band - Terraform only creates the topic, the same reasoning as modules/secrets' Slack webhook."
  value       = aws_sns_topic.alerts.arn
}
