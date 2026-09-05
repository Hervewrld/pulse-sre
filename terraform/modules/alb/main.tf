resource "aws_security_group" "alb" {
  name_prefix = "${var.name}-alb-"
  vpc_id      = var.vpc_id
  description = "Pulse ALB - public HTTP entrypoint"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.name}-alb" }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb" "this" {
  name               = "${var.name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.public_subnet_ids
}

resource "aws_lb_target_group" "api" {
  name        = "${var.name}-api"
  port        = var.target_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip" # Fargate tasks register by IP, not instance ID

  health_check {
    path                = var.health_check_path
    healthy_threshold   = 3
    unhealthy_threshold = 3
    interval            = 30
    timeout             = 5
    matcher             = "200"
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  # Forwards to a target group with nothing registered yet - Phase 6 attaches
  # the api ECS service's tasks here. Until then, ALB's own no-healthy-targets
  # 503 is the honest answer, and no listener change is needed once it's live.
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api.arn
  }
}

# Grafana (Phase 11) shares this same ALB instead of getting its own -
# path-based routing off the one public entrypoint this project already
# pays for, rather than a second load balancer just for one more service.
resource "aws_lb_target_group" "grafana" {
  name        = "${var.name}-grafana"
  port        = var.grafana_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    # Grafana's own built-in health endpoint - under /grafana, not /, because
    # GF_SERVER_SERVE_FROM_SUB_PATH=true (environments/*/main.tf) makes
    # Grafana serve everything under its root_url's path, including this,
    # once the ALB is forwarding /grafana/* without stripping the prefix
    # (see aws_lb_listener_rule.grafana's own comment on that).
    path                = "/grafana/api/health"
    healthy_threshold   = 3
    unhealthy_threshold = 3
    interval            = 30
    timeout             = 5
    matcher             = "200"
  }
}

resource "aws_lb_listener_rule" "grafana" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.grafana.arn
  }

  condition {
    path_pattern {
      # ALB doesn't rewrite the path when forwarding - Grafana itself is
      # configured (GF_SERVER_SERVE_FROM_SUB_PATH, environments/*/main.tf) to
      # expect requests still carrying this prefix, not to have it stripped.
      values = ["/grafana", "/grafana/*"]
    }
  }
}
