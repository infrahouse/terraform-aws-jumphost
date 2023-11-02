variable "ami_id" {
  description = "AMI id for jumphost instances. By default, latest Ubuntu jammy."
  type        = string
  default     = null
}

variable "extra_policies" {
  description = "A map of additional policy ARNs to attach to the jumphost role"
  type        = map(string)
  default     = {}
}

variable "keypair_name" {
  description = "SSH key pair name that will be added to the jumphost instance"
  type        = string
}

variable "subnet_ids" {
  description = "List of subnet ids where the jumphost instances will be created"
  type        = list(string)
}

variable "environment" {
  description = "Environment name. Passed on as a puppet fact"
  type        = string
}

variable "route53_zone_id" {
  description = "Route53 zone id of a zone where this jumphost will put an A record"
}

variable "route53_hostname" {
  description = "An A record with this name will be created in the rout53 zone"
  type        = string
  default     = "jumphost"
}

variable "route53_ttl" {
  description = "TTL in seconds on the route53 record"
  type        = number
  default     = 300
}

variable "ubuntu_codename" {
  description = "Ubuntu version to use for the jumphost"
  type        = string
  default     = "jammy"
}