output "zone_id" {
  value = data.aws_route53_zone.cicd.zone_id
}

output "jumphost_hostname" {
  value = local.jumphost_hostname
}

output "jumphost_asg_name" {
  value = module.test.jumphost_asg_name
}
