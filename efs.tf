data "aws_kms_key" "efs_default" {
  key_id = "alias/aws/elasticfilesystem"
}

resource "aws_efs_file_system" "home" {
  creation_token = "jumphost-home"
  encrypted      = true
  kms_key_id     = var.efs_kms_key_arn != null ? var.efs_kms_key_arn : data.aws_kms_key.efs_default.arn
  tags = merge(
    {
      Name = "jumphost-home"
    },
    local.default_module_tags
  )
}

resource "aws_efs_mount_target" "packages" {
  for_each       = toset(var.subnet_ids)
  file_system_id = aws_efs_file_system.home.id
  subnet_id      = each.key
  security_groups = [
    aws_security_group.efs.id
  ]
  lifecycle {
    create_before_destroy = false
  }
}

resource "aws_security_group" "efs" {
  description = "Security group for the EFS volume"
  name_prefix = "jumphost-efs-"
  vpc_id      = local.vpc_id

  tags = merge(
    {
      Name : "Jumphost EFS home"
    },
    local.default_module_tags
  )
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "efs" {
  for_each          = toset(var.subnet_ids)
  description       = "Allow NFS traffic to EFS volume"
  security_group_id = aws_security_group.efs.id
  from_port         = 2049
  to_port           = 2049
  ip_protocol       = "tcp"
  cidr_ipv4         = data.aws_subnet.selected[each.key].cidr_block
  tags = merge({
    Name = "NFS traffic"
    },
    local.default_module_tags
  )
}

resource "aws_vpc_security_group_ingress_rule" "efs_icmp" {
  description       = "Allow all ICMP traffic"
  security_group_id = aws_security_group.efs.id
  from_port         = -1
  to_port           = -1
  ip_protocol       = "icmp"
  cidr_ipv4         = "0.0.0.0/0"
  tags = merge({
    Name = "ICMP traffic"
    },
    local.default_module_tags
  )
}

resource "aws_vpc_security_group_egress_rule" "efs" {
  security_group_id = aws_security_group.efs.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
  tags = merge({
    Name = "EFS outgoing traffic"
    },
    local.default_module_tags
  )
}
