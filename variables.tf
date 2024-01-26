variable "ami_id" {
  description = "AMI id for jumphost instances. By default, latest Ubuntu jammy."
  type        = string
  default     = null
}

variable "extra_files" {
  description = "Additional files to create on an instance."
  type = list(object({
    content     = string
    path        = string
    permissions = string
  }))
  default = []
}

variable "extra_policies" {
  description = "A map of additional policy ARNs to attach to the jumphost role"
  type        = map(string)
  default     = {}
}

variable "extra_repos" {
  description = "Additional APT repositories to configure on an instance."
  type = map(object({
    source = string
    key    = string
  }))
  default = {}
}

variable "instance_type" {
  description = "EC2 Instance type"
  default     = "t3a.micro"
}
variable "keypair_name" {
  description = "SSH key pair name that will be added to the jumphost instance"
  type        = string
}

variable "environment" {
  description = "Environment name. Passed on as a puppet fact"
  type        = string
}

variable "packages" {
  description = "List of packages to install when the instances bootstraps."
  type        = list(string)
  default     = []
}

variable "puppet_debug_logging" {
  description = "Enable debug logging if true."
  type        = bool
  default     = false
}

variable "puppet_environmentpath" {
  description = "A path for directory environments."
  default     = "{root_directory}/environments"
}

variable "puppet_hiera_config_path" {
  description = "Path to hiera configuration file."
  default     = "{root_directory}/environments/{environment}/hiera.yaml"
}

variable "puppet_module_path" {
  description = "Path to common puppet modules."
  default     = "{root_directory}/modules"
}

variable "puppet_root_directory" {
  description = "Path where the puppet code is hosted."
  default     = "/opt/puppet-code"
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

variable "subnet_ids" {
  description = "List of subnet ids where the jumphost instances will be created"
  type        = list(string)
}


variable "ubuntu_codename" {
  description = "Ubuntu version to use for the jumphost"
  type        = string
  default     = "jammy"
}
