output "jumphost_role_arn" {
  description = "Instance IAM role ARN."
  value       = module.jumphost_profile.instance_profile_arn
}
output "jumphost_role_name" {
  description = "Instance IAM role name."
  value       = module.jumphost_profile.instance_profile_name
}
