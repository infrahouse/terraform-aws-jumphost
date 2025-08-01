resource "aws_efs_replication_configuration" "home" {
  source_file_system_id = aws_efs_file_system.home.id
  destination {
    region         = data.aws_region.current.name
    file_system_id = aws_efs_file_system.home-enc.id
  }
}
