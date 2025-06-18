
module "jumphost" {
  source                   = "../.."

  subnet_ids               = var.asg_subnet_ids
  nlb_subnet_ids           = var.nlb_subnet_ids
  environment              = local.environment
  route53_zone_id          = data.aws_route53_zone.cicd.zone_id
  route53_hostname         = local.jumphost_hostname
  asg_min_size             = 1
  asg_max_size             = 1
  instance_type            = "t3a.medium"
  ubuntu_codename          = "noble"
  puppet_hiera_config_path = "/opt/infrahouse-puppet-data/environments/${local.environment}/hiera.yaml"
  packages = [
    "infrahouse-puppet-data"
  ]
}
