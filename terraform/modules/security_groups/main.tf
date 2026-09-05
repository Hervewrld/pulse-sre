# Per-service security groups, mirroring the per-service IAM roles in
# modules/iam - each ECS service (created in Phase 6) is reachable only from
# exactly what needs to reach it, not from the rest of the VPC.

resource "aws_security_group" "api" {
  name_prefix = "${var.name}-api-"
  vpc_id      = var.vpc_id
  description = "Pulse api ECS service - reachable only from the ALB"

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.name}-api" }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group_rule" "api_from_alb" {
  type                     = "ingress"
  security_group_id        = aws_security_group.api.id
  source_security_group_id = var.alb_security_group_id
  from_port                = var.api_container_port
  to_port                  = var.api_container_port
  protocol                 = "tcp"
}

resource "aws_security_group" "scheduler" {
  name_prefix = "${var.name}-scheduler-"
  vpc_id      = var.vpc_id
  description = "Pulse scheduler ECS service - no inbound; calls checker and the database"

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.name}-scheduler" }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "checker" {
  name_prefix = "${var.name}-checker-"
  vpc_id      = var.vpc_id
  description = "Pulse checker ECS service - reachable only from the scheduler; needs internet egress to probe monitored targets"

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.name}-checker" }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group_rule" "checker_from_scheduler" {
  type                     = "ingress"
  security_group_id        = aws_security_group.checker.id
  source_security_group_id = aws_security_group.scheduler.id
  from_port                = var.checker_container_port
  to_port                  = var.checker_container_port
  protocol                 = "tcp"
}

resource "aws_security_group" "grafana" {
  name_prefix = "${var.name}-grafana-"
  vpc_id      = var.vpc_id
  description = "Pulse Grafana (Phase 11) - reachable only from the ALB"

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.name}-grafana" }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group_rule" "grafana_from_alb" {
  type                     = "ingress"
  security_group_id        = aws_security_group.grafana.id
  source_security_group_id = var.alb_security_group_id
  from_port                = var.grafana_container_port
  to_port                  = var.grafana_container_port
  protocol                 = "tcp"
}

resource "aws_security_group" "db" {
  name_prefix = "${var.name}-db-"
  vpc_id      = var.vpc_id
  description = "Pulse Postgres - reachable only from the api, scheduler, checker and grafana services"

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.name}-db" }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group_rule" "db_from_api" {
  type                     = "ingress"
  security_group_id        = aws_security_group.db.id
  source_security_group_id = aws_security_group.api.id
  from_port                = var.db_port
  to_port                  = var.db_port
  protocol                 = "tcp"
}

resource "aws_security_group_rule" "db_from_scheduler" {
  type                     = "ingress"
  security_group_id        = aws_security_group.db.id
  source_security_group_id = aws_security_group.scheduler.id
  from_port                = var.db_port
  to_port                  = var.db_port
  protocol                 = "tcp"
}

resource "aws_security_group_rule" "db_from_checker" {
  type                     = "ingress"
  security_group_id        = aws_security_group.db.id
  source_security_group_id = aws_security_group.checker.id
  from_port                = var.db_port
  to_port                  = var.db_port
  protocol                 = "tcp"
}

resource "aws_security_group_rule" "db_from_grafana" {
  type                     = "ingress"
  security_group_id        = aws_security_group.db.id
  source_security_group_id = aws_security_group.grafana.id
  from_port                = var.db_port
  to_port                  = var.db_port
  protocol                 = "tcp"
}
