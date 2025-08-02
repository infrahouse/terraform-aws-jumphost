resource "aws_iam_policy" "required" {
  policy = data.aws_iam_policy_document.required_permissions.json
  tags   = local.default_module_tags
}

resource "random_string" "profile-suffix" {
  length  = 12
  special = false
}

module "jumphost_profile" {
  source         = "registry.infrahouse.com/infrahouse/instance-profile/aws"
  version        = "1.8.1"
  permissions    = data.aws_iam_policy_document.required_permissions.json
  profile_name   = "jumphost-${random_string.profile-suffix.result}"
  role_name      = var.instance_role_name
  extra_policies = var.extra_policies
}

module "jumphost_userdata" {
  source                   = "registry.infrahouse.com/infrahouse/cloud-init/aws"
  version                  = "1.18.0"
  environment              = var.environment
  role                     = "jumphost"
  gzip_userdata            = true
  ubuntu_codename          = var.ubuntu_codename
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
      "${aws_efs_file_system.home-enc.dns_name}:/",
      "/home",
      "nfs4",
      "nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport,_netdev",
      "0",
      "0"
    ]
  ]
  ssh_host_keys = var.ssh_host_keys == null ? [
    {
      type : "rsa"
      private : tls_private_key.rsa.private_key_openssh
      public : tls_private_key.rsa.public_key_openssh
    },
    {
      type : "ecdsa"
      private : tls_private_key.ecdsa.private_key_openssh
      public : tls_private_key.ecdsa.public_key_openssh
    },
    {
      type : "ed25519"
      private : tls_private_key.ed25519.private_key_openssh
      public : tls_private_key.ed25519.public_key_openssh
    }
  ] : var.ssh_host_keys
}

resource "tls_private_key" "deployer" {
  algorithm = "RSA"
}

resource "aws_key_pair" "deployer" {
  key_name_prefix = "${local.service_name}-deployer-generated-"
  public_key      = tls_private_key.deployer.public_key_openssh
  tags            = local.default_module_tags
}

resource "aws_launch_template" "jumphost" {
  name_prefix   = "jumphost-"
  instance_type = var.instance_type
  key_name      = var.keypair_name != null ? var.keypair_name : aws_key_pair.deployer.key_name
  image_id      = data.aws_ami.selected.id
  iam_instance_profile {
    arn = module.jumphost_profile.instance_profile_arn
  }
  block_device_mappings {
    device_name = data.aws_ami.selected.root_device_name
    ebs {
      volume_size           = var.root_volume_size
      delete_on_termination = true
    }
  }
  metadata_options {
    http_tokens            = "required"
    http_endpoint          = "enabled"
    instance_metadata_tags = "enabled"
  }
  user_data = module.jumphost_userdata.userdata
  vpc_security_group_ids = [
    aws_security_group.jumphost.id
  ]
  tags = local.default_module_tags
  tag_specifications {
    resource_type = "volume"
    tags = merge(
      data.aws_default_tags.provider.tags,
      local.default_module_tags
    )
  }
  tag_specifications {
    resource_type = "network-interface"
    tags = merge(
      data.aws_default_tags.provider.tags,
      local.default_module_tags
    )
  }
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
  dynamic "launch_template" {
    for_each = var.on_demand_base_capacity == null ? [1] : []
    content {
      id      = aws_launch_template.jumphost.id
      version = aws_launch_template.jumphost.latest_version
    }
  }
  dynamic "mixed_instances_policy" {
    for_each = var.on_demand_base_capacity == null ? [] : [1]
    content {
      instances_distribution {
        on_demand_base_capacity                  = var.on_demand_base_capacity
        on_demand_percentage_above_base_capacity = 0
      }
      launch_template {
        launch_template_specification {
          launch_template_id = aws_launch_template.jumphost.id
          version            = aws_launch_template.jumphost.latest_version
        }
      }
    }
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
    triggers = [
      "tag",
    ]
  }
  tag {
    key                 = "Name"
    propagate_at_launch = true
    value               = var.route53_hostname
  }
  tag {
    key                 = "ubuntu_codename"
    propagate_at_launch = true
    value               = var.ubuntu_codename
  }
  dynamic "tag" {
    for_each = merge(
      local.default_module_tags,
      data.aws_default_tags.provider.tags,
    )
    content {
      key                 = tag.key
      propagate_at_launch = true
      value               = tag.value
    }
  }
}
