# Infra-level observability: CloudWatch alarms -> SNS, Logs Insights saved
# queries, and a RED-metrics dashboard. Deliberately separate from Pulse's own
# app-level alerting (src/alerting, Phase 2, Slack) - that layer watches
# whether a *monitored external target* is up; this layer watches whether
# Pulse's *own infrastructure* (the ALB, ECS tasks, the database) is healthy.
# An operator subscribes their own endpoint to the SNS topic below (email,
# a Slack channel via AWS Chatbot, PagerDuty, ...) - same reasoning as the
# Slack webhook in modules/secrets: Terraform can create the topic, not decide
# who gets paged.

resource "aws_sns_topic" "alerts" {
  name = "${var.name}-infra-alerts"
}

locals {
  # Fixed-dimension alarms - one each, not per-service.
  alarms = {
    alb_5xx_errors = {
      metric_name         = "HTTPCode_Target_5XX_Count"
      namespace           = "AWS/ApplicationELB"
      statistic           = "Sum"
      extended_statistic  = null
      period              = 300
      evaluation_periods  = 1
      threshold           = 10
      comparison_operator = "GreaterThanThreshold"
      dimensions          = { LoadBalancer = var.alb_arn_suffix }
      treat_missing_data  = "notBreaching"
    }
    alb_target_response_time = {
      metric_name         = "TargetResponseTime"
      namespace           = "AWS/ApplicationELB"
      statistic           = null
      extended_statistic  = "p99" # percentiles aren't valid `statistic` values, need this field instead
      period              = 300
      evaluation_periods  = 3
      threshold           = 2
      comparison_operator = "GreaterThanThreshold"
      dimensions          = { LoadBalancer = var.alb_arn_suffix }
      treat_missing_data  = "notBreaching"
    }
    alb_unhealthy_hosts = {
      metric_name         = "UnHealthyHostCount"
      namespace           = "AWS/ApplicationELB"
      statistic           = "Maximum"
      extended_statistic  = null
      period              = 60
      evaluation_periods  = 3
      threshold           = 0
      comparison_operator = "GreaterThanThreshold"
      dimensions          = { LoadBalancer = var.alb_arn_suffix, TargetGroup = var.api_target_group_arn_suffix }
      treat_missing_data  = "notBreaching"
    }
    rds_cpu_high = {
      metric_name         = "CPUUtilization"
      namespace           = "AWS/RDS"
      statistic           = "Average"
      extended_statistic  = null
      period              = 300
      evaluation_periods  = 3
      threshold           = 80
      comparison_operator = "GreaterThanThreshold"
      dimensions          = { DBInstanceIdentifier = var.db_instance_identifier }
      treat_missing_data  = "missing"
    }
    rds_free_storage_low = {
      metric_name         = "FreeStorageSpace"
      namespace           = "AWS/RDS"
      statistic           = "Minimum"
      extended_statistic  = null
      period              = 300
      evaluation_periods  = 1
      threshold           = 2147483648 # 2GB, in the bytes this metric is reported in
      comparison_operator = "LessThanThreshold"
      dimensions          = { DBInstanceIdentifier = var.db_instance_identifier }
      treat_missing_data  = "missing"
    }
    rds_connections_high = {
      metric_name         = "DatabaseConnections"
      namespace           = "AWS/RDS"
      statistic           = "Average"
      extended_statistic  = null
      period              = 300
      evaluation_periods  = 3
      threshold           = 80
      comparison_operator = "GreaterThanThreshold"
      dimensions          = { DBInstanceIdentifier = var.db_instance_identifier }
      treat_missing_data  = "missing"
    }
  }

  # One CPU + one memory alarm per ECS service (api/scheduler/checker) - reads
  # Container Insights metrics, already enabled unconditionally on the cluster
  # (modules/ecs_cluster's containerInsights setting), no extra instrumentation
  # needed for this part.
  ecs_alarms = merge([
    for service, service_name in var.ecs_service_names : {
      "ecs_${service}_cpu_high" = {
        metric_name         = "CPUUtilization"
        namespace           = "ECS/ContainerInsights"
        statistic           = "Average"
        extended_statistic  = null
        period              = 300
        evaluation_periods  = 3
        threshold           = 85
        comparison_operator = "GreaterThanThreshold"
        dimensions          = { ClusterName = var.ecs_cluster_name, ServiceName = service_name }
        treat_missing_data  = "missing"
      }
      "ecs_${service}_memory_high" = {
        metric_name         = "MemoryUtilization"
        namespace           = "ECS/ContainerInsights"
        statistic           = "Average"
        extended_statistic  = null
        period              = 300
        evaluation_periods  = 3
        threshold           = 85
        comparison_operator = "GreaterThanThreshold"
        dimensions          = { ClusterName = var.ecs_cluster_name, ServiceName = service_name }
        treat_missing_data  = "missing"
      }
    }
  ]...)

  all_alarms = merge(local.alarms, local.ecs_alarms)
}

resource "aws_cloudwatch_metric_alarm" "this" {
  for_each = local.all_alarms

  alarm_name          = "${var.name}-${each.key}"
  comparison_operator = each.value.comparison_operator
  evaluation_periods  = each.value.evaluation_periods
  metric_name         = each.value.metric_name
  namespace           = each.value.namespace
  period              = each.value.period
  statistic           = each.value.statistic
  extended_statistic  = each.value.extended_statistic
  threshold           = each.value.threshold
  dimensions          = each.value.dimensions
  treat_missing_data  = each.value.treat_missing_data
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
}

# Saved CloudWatch Logs Insights queries - one per service plus one across all
# three, covering the questions actually asked during an incident (Phase 9):
# "what's erroring right now", "why did this one request fail". Every
# service's log group already exists (modules/iam's aws_cloudwatch_log_group).
resource "aws_cloudwatch_query_definition" "errors_by_service" {
  for_each = var.log_group_names

  name            = "${var.name}/${each.key}/errors"
  log_group_names = [each.value]
  query_string    = <<-QUERY
    fields @timestamp, @message
    | filter @message like /ERROR|WARNING/
    | sort @timestamp desc
    | limit 100
  QUERY
}

resource "aws_cloudwatch_query_definition" "all_services_errors" {
  name            = "${var.name}/all-services/errors"
  log_group_names = values(var.log_group_names)
  query_string    = <<-QUERY
    fields @timestamp, @log, @message
    | filter @message like /ERROR|WARNING/
    | sort @timestamp desc
    | limit 200
  QUERY
}

resource "aws_cloudwatch_query_definition" "checker_slow_checks" {
  name            = "${var.name}/checker/slow-checks"
  log_group_names = [var.log_group_names["checker"]]
  query_string    = <<-QUERY
    fields @timestamp, @message
    | filter @message like /checked monitor_id/
    | parse @message "response_time_ms=*" as response_time_ms
    | filter response_time_ms > 1000
    | sort response_time_ms desc
    | limit 100
  QUERY
}
