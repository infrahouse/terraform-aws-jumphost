resource "aws_efs_file_system" "home-enc" {
  creation_token = "jumphost-home-encrypted"
  encrypted      = true
  kms_key_id     = data.aws_kms_key.efs_default.arn
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

resource "aws_efs_mount_target" "packages" {
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
