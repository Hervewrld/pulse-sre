# Third-party secrets Pulse needs (e.g. the Slack webhook URL) that AWS has no
# way to generate or manage itself, unlike the RDS master password (see
# modules/rds, which sets manage_master_user_password = true instead of using
# this module). Populate each value after apply, e.g.:
#   aws secretsmanager put-secret-value --secret-id <name> --secret-string '<value>'

resource "aws_secretsmanager_secret" "this" {
  for_each = var.secrets

  name        = "${var.name}/${each.key}"
  description = each.value
}

# A secret with no version at all can't be resolved by ECS - a container
# whose task definition references it fails to start (ResourceInitializationError)
# from the very first apply, before anyone's had the chance to run the real
# put-secret-value. This placeholder gets it running (consumers are expected to
# treat "unconfigured" as a valid, non-fatal state - see SlackNotifier's caller).
# ignore_changes means Terraform never overwrites whatever value an operator
# puts here afterwards, and this placeholder is the only value that ever
# passes through a .tf file or plan - the real one never does.
resource "aws_secretsmanager_secret_version" "this" {
  for_each = aws_secretsmanager_secret.this

  secret_id     = each.value.id
  secret_string = "unconfigured"

  lifecycle {
    ignore_changes = [secret_string]
  }
}
