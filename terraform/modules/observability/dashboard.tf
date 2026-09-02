# One dashboard, RED-shaped per service. api gets real Rate/Errors/Duration
# from the ALB (it's the only service with a client-facing HTTP entrypoint to
# measure that way). scheduler/checker have no such entrypoint the ALB can see
# - Container Insights (CPU/memory/running-task-count, already enabled
# unconditionally on the cluster) stands in as the closest infra-level proxy
# instead of adding custom app metrics just for this dashboard. Real
# app-level RED (e.g. checker's actual check success rate) already exists as
# SLO math - see Phase 3/11's error-budget dashboard - this one is about
# infra health, not monitored-target health.

locals {
  dashboard_body = {
    widgets = [
      {
        type       = "text", x = 0, y = 0, width = 24, height = 1
        properties = { markdown = "# ${var.name} - RED metrics" }
      },

      # api: Rate / Errors / Duration, straight from the ALB.
      {
        type = "metric", x = 0, y = 1, width = 8, height = 6
        properties = {
          title  = "api - Rate (requests/5min)"
          region = var.region
          period = 300
          stat   = "Sum"
          view   = "timeSeries"
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", var.alb_arn_suffix],
          ]
        }
      },
      {
        type = "metric", x = 8, y = 1, width = 8, height = 6
        properties = {
          title  = "api - Errors (5xx/4xx per 5min)"
          region = var.region
          period = 300
          stat   = "Sum"
          view   = "timeSeries"
          metrics = [
            ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", var.alb_arn_suffix],
            ["AWS/ApplicationELB", "HTTPCode_Target_4XX_Count", "LoadBalancer", var.alb_arn_suffix],
          ]
        }
      },
      {
        type = "metric", x = 16, y = 1, width = 8, height = 6
        properties = {
          title  = "api - Duration (p50/p99, seconds)"
          region = var.region
          period = 300
          view   = "timeSeries"
          metrics = [
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", var.alb_arn_suffix, { stat = "p50" }],
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", var.alb_arn_suffix, { stat = "p99" }],
          ]
        }
      },

      # scheduler/checker: CPU/memory/running-task-count from Container
      # Insights - see the module comment above for why, not ALB-derived RED.
      {
        type = "metric", x = 0, y = 7, width = 8, height = 6
        properties = {
          title  = "scheduler/checker - CPU %"
          region = var.region
          period = 300
          stat   = "Average"
          view   = "timeSeries"
          metrics = [
            ["ECS/ContainerInsights", "CPUUtilization", "ClusterName", var.ecs_cluster_name, "ServiceName", var.ecs_service_names["scheduler"]],
            ["ECS/ContainerInsights", "CPUUtilization", "ClusterName", var.ecs_cluster_name, "ServiceName", var.ecs_service_names["checker"]],
          ]
        }
      },
      {
        type = "metric", x = 8, y = 7, width = 8, height = 6
        properties = {
          title  = "scheduler/checker - Memory %"
          region = var.region
          period = 300
          stat   = "Average"
          view   = "timeSeries"
          metrics = [
            ["ECS/ContainerInsights", "MemoryUtilization", "ClusterName", var.ecs_cluster_name, "ServiceName", var.ecs_service_names["scheduler"]],
            ["ECS/ContainerInsights", "MemoryUtilization", "ClusterName", var.ecs_cluster_name, "ServiceName", var.ecs_service_names["checker"]],
          ]
        }
      },
      {
        type = "metric", x = 16, y = 7, width = 8, height = 6
        properties = {
          title  = "scheduler/checker - Running tasks"
          region = var.region
          period = 300
          stat   = "Average"
          view   = "timeSeries"
          metrics = [
            ["ECS/ContainerInsights", "RunningTaskCount", "ClusterName", var.ecs_cluster_name, "ServiceName", var.ecs_service_names["scheduler"]],
            ["ECS/ContainerInsights", "RunningTaskCount", "ClusterName", var.ecs_cluster_name, "ServiceName", var.ecs_service_names["checker"]],
          ]
        }
      },

      # Database - the one dependency all three services share.
      {
        type = "metric", x = 0, y = 13, width = 8, height = 6
        properties = {
          title  = "RDS - CPU %"
          region = var.region
          period = 300
          stat   = "Average"
          view   = "timeSeries"
          metrics = [
            ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", var.db_instance_identifier],
          ]
        }
      },
      {
        type = "metric", x = 8, y = 13, width = 8, height = 6
        properties = {
          title  = "RDS - Connections"
          region = var.region
          period = 300
          stat   = "Average"
          view   = "timeSeries"
          metrics = [
            ["AWS/RDS", "DatabaseConnections", "DBInstanceIdentifier", var.db_instance_identifier],
          ]
        }
      },
      {
        type = "metric", x = 16, y = 13, width = 8, height = 6
        properties = {
          title  = "RDS - Free storage (bytes)"
          region = var.region
          period = 300
          stat   = "Minimum"
          view   = "timeSeries"
          metrics = [
            ["AWS/RDS", "FreeStorageSpace", "DBInstanceIdentifier", var.db_instance_identifier],
          ]
        }
      },
    ]
  }
}

resource "aws_cloudwatch_dashboard" "this" {
  dashboard_name = "${var.name}-red-metrics"
  dashboard_body = jsonencode(local.dashboard_body)
}
