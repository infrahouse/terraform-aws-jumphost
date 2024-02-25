output "jumphost_role_arn" {
  description = "Instance IAM role ARN."
  value       = module.jumphost_profile.instance_role_arn
}
output "jumphost_role_name" {
  description = "Instance IAM role name."
  value       = module.jumphost_profile.instance_role_name
}

output "jumphost_instance_profile__arn" {
  description = "Instance IAM profile ARN."
  value       = module.jumphost_profile.instance_profile_arn
}
output "jumphost_instance_profile_name" {
  description = "Instance IAM profile name."
  value       = module.jumphost_profile.instance_profile_name
}

output "jumphost_asg_name" {
  description = "Jumphost autoscaling group"
  value       = aws_autoscaling_group.jumphost.name
}

output "jumphost_hostname" {
  value = "${var.route53_hostname}.${data.aws_route53_zone.jumphost_zone.name}"
}
