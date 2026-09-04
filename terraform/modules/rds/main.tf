resource "aws_db_subnet_group" "this" {
  name       = "${var.name}-db"
  subnet_ids = var.private_subnet_ids
}

# A fixed final_snapshot_identifier would collide on a second destroy/recreate
# of the same environment (DBSnapshotAlreadyExists) - this suffix is stable
# across plans (only regenerates if explicitly tainted) but unique per real
# instance lifetime.
resource "random_id" "final_snapshot_suffix" {
  byte_length = 4
}

resource "aws_db_instance" "this" {
  identifier     = "${var.name}-db"
  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class

  allocated_storage = var.allocated_storage_gb
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = var.database_name
  username = var.master_username
  # AWS generates the master password itself and stores it as a Secrets
  # Manager secret (see the master_user_secret_arn output) - no plaintext
  # password ever passes through this config or the state file. This alone
  # doesn't schedule rotation, though - see aws_secretsmanager_secret_rotation
  # below for that part.
  manage_master_user_password = true

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [var.security_group_id]

  multi_az                  = var.multi_az
  backup_retention_period   = var.backup_retention_days
  skip_final_snapshot       = false
  final_snapshot_identifier = "${var.name}-db-final-${random_id.final_snapshot_suffix.hex}"
  deletion_protection       = var.deletion_protection

  tags = { Name = "${var.name}-db" }
}

# For an RDS-managed secret specifically, Secrets Manager uses its own
# built-in rotation function - no rotation_lambda_arn to write or maintain,
# unlike rotating a hand-managed secret. Rotation changes the DB password
# in place, but api/scheduler/checker each only read DB_USER/DB_PASSWORD once,
# at task start (modules/ecs_service's `secrets` block) - a rotation firing
# doesn't push the new value into already-running tasks, so it needs a
# deploy/force-new-deployment afterward to avoid a real connectivity gap
# until tasks happen to restart on their own. See terraform/README.md.
resource "aws_secretsmanager_secret_rotation" "master_password" {
  secret_id = aws_db_instance.this.master_user_secret[0].secret_arn

  # Defaults to true otherwise, which would rotate the password immediately
  # on the first apply of this resource against an already-running database -
  # an unplanned connectivity gap for whatever's running right then, not the
  # eventual/scheduled one the comment above describes. Let it happen on
  # schedule (automatically_after_days) instead.
  rotate_immediately = false

  rotation_rules {
    automatically_after_days = var.password_rotation_days
  }
}
