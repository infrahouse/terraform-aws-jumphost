resource "aws_iam_policy" "required" {
  policy = data.aws_iam_policy_document.required_permissions.json
}

module "jumphost_profile" {
  source       = "infrahouse/instance-profile/aws"
  version      = "~> 1.0"
  permissions  = data.aws_iam_policy_document.jumphost_permissions.json
  profile_name = "jumphost"
  extra_policies = merge(
    {
      required : aws_iam_policy.required.arn
    },
    var.extra_policies
  )
}

module "jumphost_userdata" {
  source                   = "infrahouse/cloud-init/aws"
  version                  = "~> 1.5"
  environment              = var.environment
  role                     = "jumphost"
  puppet_debug_logging     = var.puppet_debug_logging
  puppet_hiera_config_path = var.puppet_hiera_config_path
  puppet_module_path       = var.puppet_module_path
  puppet_root_directory    = var.puppet_root_directory
  packages                 = var.packages
  extra_files              = var.extra_files
  extra_repos              = var.extra_repos
}

resource "aws_launch_template" "jumphost" {
  name_prefix   = "jumphost-"
  instance_type = "t3a.micro"
  key_name      = var.keypair_name
  image_id      = var.ami_id == null ? data.aws_ami.ubuntu.id : var.ami_id
  iam_instance_profile {
    arn = module.jumphost_profile.instance_profile_arn
  }
  user_data = module.jumphost_userdata.userdata
}

resource "aws_autoscaling_group" "jumphost" {
  name_prefix           = aws_launch_template.jumphost.name_prefix
  max_size              = 3
  min_size              = 1
  vpc_zone_identifier   = var.subnet_ids
  max_instance_lifetime = 90 * 24 * 3600
  launch_template {
    id      = aws_launch_template.jumphost.id
    version = aws_launch_template.jumphost.latest_version
  }

  lifecycle {
    create_before_destroy = true
  }
  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 100
    }
  }
  tag {
    key                 = "Name"
    propagate_at_launch = true
    value               = "jumphost"
  }
}

resource "aws_cloudwatch_event_rule" "scale" {
  name_prefix = "jumphost-scale"
  description = "Jumphost ASG lifecycle hook"
  event_pattern = jsonencode(
    {
      "source" : ["aws.autoscaling"],
      "detail-type" : [
        "EC2 Instance-launch Lifecycle Action",
        "EC2 Instance-terminate Lifecycle Action"
      ],
      "detail" : {
        "AutoScalingGroupName" : [
          aws_autoscaling_group.jumphost.name
        ]
      }
    }
  )
}

resource "aws_cloudwatch_event_target" "scale-out" {
  arn  = aws_lambda_function.update_dns.arn
  rule = aws_cloudwatch_event_rule.scale.name
}


locals {
  lifecycle_hook_wait_time = 300
}

resource "aws_autoscaling_lifecycle_hook" "launching" {
  name                   = "launching"
  autoscaling_group_name = aws_autoscaling_group.jumphost.name
  lifecycle_transition   = "autoscaling:EC2_INSTANCE_LAUNCHING"
  heartbeat_timeout      = local.lifecycle_hook_wait_time
  default_result         = "ABANDON"
}

resource "aws_autoscaling_lifecycle_hook" "terminating" {
  name                   = "terminating"
  autoscaling_group_name = aws_autoscaling_group.jumphost.name
  lifecycle_transition   = "autoscaling:EC2_INSTANCE_TERMINATING"
  heartbeat_timeout      = local.lifecycle_hook_wait_time
  default_result         = "ABANDON"
}
