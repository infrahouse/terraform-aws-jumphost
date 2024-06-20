resource "aws_iam_policy" "required" {
  policy = data.aws_iam_policy_document.required_permissions.json
}

resource "random_string" "profile-suffix" {
  length  = 12
  special = false
}

module "jumphost_profile" {
  source       = "registry.infrahouse.com/infrahouse/instance-profile/aws"
  version      = "~> 1.3"
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
  source                   = "registry.infrahouse.com/infrahouse/cloud-init/aws"
  version                  = "1.12.4"
  environment              = var.environment
  role                     = "jumphost"
  custom_facts             = var.puppet_custom_facts
  puppet_debug_logging     = var.puppet_debug_logging
  puppet_environmentpath   = var.puppet_environmentpath
  puppet_hiera_config_path = var.puppet_hiera_config_path
  puppet_module_path       = var.puppet_module_path
  puppet_root_directory    = var.puppet_root_directory
  puppet_manifest          = var.puppet_manifest
  packages = concat(
    var.packages,
    [
      "nfs-common"
    ]
  )
  extra_files = var.extra_files
  extra_repos = var.extra_repos
  mounts = [
    # See https://docs.aws.amazon.com/efs/latest/ug/nfs-automount-efs.html
    [
      "${aws_efs_file_system.home.dns_name}:/",
      "/home",
      "nfs4",
      "nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport,_netdev",
      "0",
      "0"
    ]
  ]
  ssh_host_keys = var.ssh_host_keys
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
  tags = local.tags
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
  max_size              = var.asg_max_size == null ? length(var.subnet_ids) + 1 : var.asg_max_size
  min_size              = var.asg_min_size == null ? length(var.subnet_ids) : var.asg_min_size
  vpc_zone_identifier   = var.subnet_ids
  max_instance_lifetime = 90 * 24 * 3600
  launch_template {
    id      = aws_launch_template.jumphost.id
    version = aws_launch_template.jumphost.latest_version
  }
  target_group_arns = [
    aws_lb_target_group.jumphost.arn
  ]

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
  dynamic "tag" {
    for_each = local.tags
    content {
      key                 = tag.key
      propagate_at_launch = true
      value               = tag.value
    }
  }
}

locals {
  lifecycle_hook_wait_time = 300
}
