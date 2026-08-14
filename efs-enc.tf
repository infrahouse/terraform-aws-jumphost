# Creation tokens are unique per account+region; a random suffix keeps
# concurrent deployments from colliding. Deliberately not derived from the
# hostname: a rename must never replace the filesystem and destroy /home.
resource "random_string" "efs_token" {
  length  = 12
  special = false
}

resource "aws_efs_file_system" "home-enc" {
  creation_token = coalesce(var.efs_creation_token, "jumphost-home-${random_string.efs_token.result}")
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
