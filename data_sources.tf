data "aws_iam_policy_document" "required_permissions" {
  statement {
    actions   = ["ec2:DescribeInstances"]
    resources = ["*"]
  }
  statement {
    actions = ["autoscaling:DescribeAutoScalingInstances"]
    resources = [
      aws_autoscaling_group.jumphost.arn
    ]
  }
}

data "aws_ami" "ubuntu_pro" {
  most_recent = true

  filter {
    name   = "name"
    values = [local.ami_name_pattern_pro]
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
data "aws_default_tags" "provider" {}

data "aws_route53_zone" "jumphost_zone" {
  zone_id = var.route53_zone_id
}

data "aws_subnet" "selected" {
  for_each = toset(var.subnet_ids)
  id       = each.key
}

data "aws_vpc" "selected" {
  for_each = toset(var.subnet_ids)
  id       = data.aws_subnet.selected[each.key].vpc_id
}

data "aws_subnet" "nlb_selected" {
  for_each = toset(var.nlb_subnet_ids)
  id       = each.key
}

data "aws_ami" "selected" {
  filter {
    name = "image-id"
    values = [
      local.ami_id
    ]
  }
}

data "aws_kms_key" "efs_default" {
  key_id = "alias/aws/elasticfilesystem"
}

# Combine all required permissions
data "aws_iam_policy_document" "combined_permissions" {
  source_policy_documents = [
    data.aws_iam_policy_document.required_permissions.json,
    data.aws_iam_policy_document.cloudwatch_logs.json
  ]
}
