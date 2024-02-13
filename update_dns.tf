module "update_dns" {
  source            = "infrahouse/update-dns/aws"
  version           = "~> 0.1"
  asg_name          = local.asg_name
  route53_zone_id   = var.route53_zone_id
  route53_hostname  = var.route53_hostname
  route53_public_ip = true
}
