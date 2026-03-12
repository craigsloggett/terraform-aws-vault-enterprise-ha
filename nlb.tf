resource "aws_lb" "vault" {
  name               = "${var.project_name}-vault"
  internal           = var.nlb_internal
  load_balancer_type = "network"
  subnets            = var.nlb_internal ? module.vpc.private_subnets : module.vpc.public_subnets

  tags = merge(var.common_tags, { Name = "${var.project_name}-vault" })
}

resource "aws_lb_target_group" "vault" {
  name     = "${var.project_name}-vault"
  port     = 8200
  protocol = "TCP"
  vpc_id   = module.vpc.vpc_id

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
}

resource "aws_lb_listener" "vault" {
  load_balancer_arn = aws_lb.vault.arn
  port              = 8200
  protocol          = "TCP"

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
