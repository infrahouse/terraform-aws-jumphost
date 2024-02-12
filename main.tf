resource "aws_iam_policy" "required" {
  policy = data.aws_iam_policy_document.required_permissions.json
}

resource "random_string" "profile-suffix" {
  length  = 12
  special = false
}

module "jumphost_profile" {
  source       = "infrahouse/instance-profile/aws"
  version      = "~> 1.0"
  permissions  = data.aws_iam_policy_document.jumphost_permissions.json
  profile_name = "jumphost-${random_string.profile-suffix.result}"
  extra_policies = merge(
    {
      required : aws_iam_policy.required.arn
    },
    var.extra_policies
  )
}

module "jumphost_userdata" {
  source                   = "infrahouse/cloud-init/aws"
  version                  = "~> 1.6"
  environment              = var.environment
  role                     = "jumphost"
  puppet_debug_logging     = var.puppet_debug_logging
  puppet_environmentpath   = var.puppet_environmentpath
  puppet_hiera_config_path = var.puppet_hiera_config_path
  puppet_module_path       = var.puppet_module_path
  puppet_root_directory    = var.puppet_root_directory
  packages                 = var.packages
  extra_files              = var.extra_files
  extra_repos              = var.extra_repos
}

resource "aws_launch_template" "jumphost" {
  name_prefix   = "jumphost-"
  instance_type = var.instance_type
  key_name      = var.keypair_name
  image_id      = var.ami_id == null ? data.aws_ami.ubuntu.id : var.ami_id
  iam_instance_profile {
    arn = module.jumphost_profile.instance_profile_arn
  }
  user_data = module.jumphost_userdata.userdata
  vpc_security_group_ids = [
    aws_security_group.jumphost.id
  ]
}

resource "random_string" "asg_name" {
  length  = 6
  special = false
}
locals {
  asg_name = "${aws_launch_template.jumphost.name}-${random_string.asg_name.result}"
}

resource "aws_autoscaling_group" "jumphost" {
  name                  = local.asg_name
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
    value               = var.route53_hostname
  }
  depends_on = [
    module.update_dns
  ]
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
