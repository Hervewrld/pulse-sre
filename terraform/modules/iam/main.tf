data "aws_iam_policy_document" "assume_ecs_tasks" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_cloudwatch_log_group" "this" {
  for_each          = toset(var.services)
  name              = "/ecs/${var.name}-${each.value}"
  retention_in_days = var.log_retention_days
}

# Execution role: what ECS itself needs to start the task - pull the image,
# ship logs. Scoped per service so api's execution role can't pull checker's
# image or write to scheduler's log group, even though all three trust the
# same ecs-tasks.amazonaws.com principal.
resource "aws_iam_role" "execution" {
  for_each           = toset(var.services)
  name               = "${var.name}-${each.value}-execution"
  assume_role_policy = data.aws_iam_policy_document.assume_ecs_tasks.json
}

data "aws_iam_policy_document" "execution" {
  for_each = toset(var.services)

  statement {
    sid       = "PullOwnImage"
    actions   = ["ecr:GetDownloadUrlForLayer", "ecr:BatchGetImage", "ecr:BatchCheckLayerAvailability"]
    resources = [var.ecr_repository_arns[each.value]]
  }

  statement {
    sid       = "EcrAuth"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"] # this action does not support resource-level scoping
  }

  statement {
    sid       = "WriteOwnLogs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.this[each.value].arn}:*"]
  }

  dynamic "statement" {
    for_each = length(lookup(var.secret_arns, each.value, [])) > 0 ? [1] : []
    content {
      sid       = "ReadOwnSecrets"
      actions   = ["secretsmanager:GetSecretValue"]
      resources = lookup(var.secret_arns, each.value, [])
    }
  }
}

resource "aws_iam_role_policy" "execution" {
  for_each = toset(var.services)
  name     = "${var.name}-${each.value}-execution"
  role     = aws_iam_role.execution[each.value].id
  policy   = data.aws_iam_policy_document.execution[each.value].json
}

# Task role: what the application code itself is allowed to do at runtime, as
# opposed to the execution role's infra-level image-pull/logging duties. Each
# service gets its own so a future capability can be scoped to just that
# service instead of loosening a shared role for everyone.
resource "aws_iam_role" "task" {
  for_each           = toset(var.services)
  name               = "${var.name}-${each.value}-task"
  assume_role_policy = data.aws_iam_policy_document.assume_ecs_tasks.json
}

# Every service's X-Ray daemon sidecar (modules/ecs_service's enable_xray)
# calls these on the app's behalf to actually ship trace data - not scoped
# per-service since none of these actions support resource-level ARNs anyway
# (same tradeoff as ecr:GetAuthorizationToken above), and granting it
# unconditionally to every task role is simpler than threading an
# enable_xray-shaped variable through this module too just to gate it.
data "aws_iam_policy_document" "task" {
  statement {
    sid = "XRayDaemon"
    actions = [
      "xray:PutTraceSegments",
      "xray:PutTelemetryRecords",
      "xray:GetSamplingRules",
      "xray:GetSamplingTargets",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "task" {
  for_each = toset(var.services)
  name     = "${var.name}-${each.value}-task"
  role     = aws_iam_role.task[each.value].id
  policy   = data.aws_iam_policy_document.task.json
}
