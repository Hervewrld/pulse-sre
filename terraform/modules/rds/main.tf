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
  # AWS generates and rotates the master password itself, stored as a
  # Secrets Manager secret (see the master_user_secret_arn output) - no
  # plaintext password ever passes through this config or the state file.
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
