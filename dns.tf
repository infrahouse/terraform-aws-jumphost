resource "aws_route53_record" "jumphost_cname" {
  name    = "${var.route53_hostname}.${data.aws_route53_zone.jumphost_zone.name}"
  type    = "CNAME"
  zone_id = data.aws_route53_zone.jumphost_zone.zone_id
  ttl     = var.route53_ttl
  records = [
    aws_lb.jumphost.dns_name
  ]
}
