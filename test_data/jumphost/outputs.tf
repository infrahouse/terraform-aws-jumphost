output "zone_id" {
  value = var.test_zone_id
}

output "jumphost_hostname" {
  value = local.jumphost_hostname
}

output "jumphost_fqdn" {
  value = module.jumphost.jumphost_hostname
}

output "asg_name" {
  value = module.jumphost.jumphost_asg_name
}

output "cloudwatch_log_group_name" {
  value = module.jumphost.cloudwatch_log_group_name
}

output "cloudwatch_log_group_arn" {
  value = module.jumphost.cloudwatch_log_group_arn
}
