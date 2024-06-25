locals {
  name_prefix = substr("jumphost", 0, 6)

}
resource "aws_lb" "jumphost" {
  name_prefix                      = local.name_prefix
  load_balancer_type               = "network"
  subnets                          = var.nlb_subnet_ids
  enable_cross_zone_load_balancing = true
  security_groups = [
    aws_security_group.jumphost.id
  ]
  tags = local.tags
}

resource "aws_lb_target_group" "jumphost" {
  name_prefix = local.name_prefix
  port        = 22
  protocol    = "TCP"
  vpc_id      = data.aws_vpc.nlb_selected.id
  tags        = local.tags
  stickiness {
    enabled = true
    type    = "source_ip"
  }
  health_check {
    protocol = "TCP"
    port     = 7
  }
}

resource "aws_lb_listener" "jumphost" {
  load_balancer_arn = aws_lb.jumphost.arn
  port              = 22
  protocol          = "TCP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.jumphost.arn
  }
}
