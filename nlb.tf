resource "aws_lb" "vault" {
  name_prefix        = "vault-"
  internal           = var.nlb_internal
  load_balancer_type = "network"
  subnets            = var.nlb_internal ? local.vpc.private_subnet_ids : local.vpc.public_subnet_ids

  tags = merge(var.common_tags, { Name = "${var.project_name}-vault" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_target_group" "vault" {
  name_prefix = "vault-"
  port        = 8200
  protocol    = "TLS"
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

  tags = merge(var.common_tags, { Name = "${var.project_name}-vault" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_listener" "vault" {
  load_balancer_arn = aws_lb.vault.arn
  port              = 8200
  protocol          = "TLS"
  certificate_arn   = aws_acm_certificate_validation.vault.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.vault.arn
  }
}

resource "aws_lb_target_group_attachment" "vault" {
  count = local.vault_node_count

  target_group_arn = aws_lb_target_group.vault.arn
  target_id        = aws_instance.vault[count.index].id
  port             = 8200
}
