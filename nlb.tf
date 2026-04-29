resource "aws_lb" "vault" {
  name_prefix        = "vault-"
  internal           = var.nlb_internal
  load_balancer_type = "network"
  subnets            = var.nlb_internal ? local.vpc.private_subnet_ids : local.vpc.public_subnet_ids

  enable_cross_zone_load_balancing = true

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_target_group" "vault" {
  name_prefix = "vault-"
  port        = 8200
  protocol    = "TCP"
  vpc_id      = local.vpc.id

  health_check {
    enabled             = true
    protocol            = "HTTPS"
    port                = "8200"
    path                = "/v1/sys/health?standbyok=true&perfstandbyok=true"
    healthy_threshold   = 3
    unhealthy_threshold = 3
    interval            = 30
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_listener" "vault" {
  load_balancer_arn = aws_lb.vault.arn
  port              = 443
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.vault.arn
  }
}
