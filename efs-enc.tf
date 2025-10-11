resource "aws_efs_file_system" "home-enc" {
  creation_token = var.efs_creation_token
  encrypted      = true
  kms_key_id     = var.efs_kms_key_arn != null ? var.efs_kms_key_arn : data.aws_kms_key.efs_default.arn
  protection {
    replication_overwrite = "DISABLED"
  }

  tags = merge(
    {
      Name = "jumphost-home-encrypted"
    },
    local.default_module_tags
  )
}

resource "aws_efs_mount_target" "home-enc" {
  for_each       = toset(var.subnet_ids)
  file_system_id = aws_efs_file_system.home-enc.id
  subnet_id      = each.key
  security_groups = [
    aws_security_group.efs.id
  ]
  lifecycle {
    create_before_destroy = false
  }
}
