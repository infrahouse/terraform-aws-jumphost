data "aws_iam_policy_document" "jumphost_permissions" {
  statement {
    actions   = ["ec2:Describe*"]
    resources = ["*"]
  }
}

data "aws_iam_policy_document" "required_permissions" {
  statement {
    actions = ["autoscaling:DescribeAutoScalingInstances"]
    resources = [
      aws_autoscaling_group.jumphost.arn
    ]
  }
}

data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-${var.ubuntu_codename}-*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name = "state"
    values = [
      "available"
    ]
  }

  owners = ["099720109477"] # Canonical
}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

data "aws_route53_zone" "jumphost_zone" {
  zone_id = var.route53_zone_id
}

data "aws_subnet" "selected" {
  id = var.subnet_ids[0]
}

data "aws_vpc" "selected" {
  id = data.aws_subnet.selected.vpc_id
}

data "aws_subnet" "nlb_selected" {
  id = var.nlb_subnet_ids[0]
}

data "aws_vpc" "nlb_selected" {
  id = data.aws_subnet.nlb_selected.vpc_id
}
