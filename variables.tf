variable "ami_id" {
  description = "AMI id for jumphost instances. By default, latest Ubuntu Pro var.ubuntu_codename."
  type        = string
  default     = null
}

variable "asg_min_size" {
  description = "Minimal number of EC2 instances in the ASG. By default, the number of subnets."
  type        = number
  default     = null
}

variable "asg_max_size" {
  description = "Maximum number of EC2 instances in the ASG. By default, the number of subnets plus one"
  type        = number
  default     = null
}

variable "efs_creation_token" {
  description = "A unique name used as reference when creating the EFS file system. Must be unique across all EFS file systems in the AWS account. Change this value when creating multiple jumphosts to avoid conflicts."
  type        = string
  default     = "jumphost-home-encrypted"
}

variable "efs_kms_key_arn" {
  description = "KMS key ARN to use for EFS encryption. If not specified, AWS will use the default AWS managed key for EFS."
  type        = string
  default     = null
}

variable "extra_files" {
  description = "Additional files to create on an instance."
  type = list(
    object(
      {
        content     = string
        path        = string
        permissions = string
      }
    )
  )
  default = []
}

variable "extra_policies" {
  description = "A map of additional policy ARNs to attach to the jumphost role."
  type        = map(string)
  default     = {}
}

variable "extra_repos" {
  description = "Additional APT repositories to configure on an instance."
  type = map(
    object(
      {
        source = string
        key    = string
      }
    )
  )
  default = {}
}

variable "instance_role_name" {
  description = "If specified, the instance profile will have a role with this name."
  type        = string
  default     = null
}

variable "instance_type" {
  description = "EC2 Instance type."
  type        = string
  default     = "t3a.micro"
}

variable "keypair_name" {
  description = "SSH key pair name that will be added to the jumphost instance."
  type        = string
  default     = null
}

variable "environment" {
  description = "Environment name. Passed on as a puppet fact."
  type        = string
}

variable "nlb_subnet_ids" {
  description = "List of subnet ids where the NLB will be created."
  type        = list(string)
}

variable "on_demand_base_capacity" {
  description = "If specified, the ASG will request spot instances and this will be the minimal number of on-demand instances."
  type        = number
  default     = null
}

variable "packages" {
  description = "List of packages to install when the instance bootstraps."
  type        = list(string)
  default     = []
}

variable "puppet_custom_facts" {
  description = <<-EOF
    A map of custom puppet facts. The module uses deep merge to combine user facts
    with module-managed facts. User-provided values take precedence on conflicts.

    Module automatically provides:
    - jumphost.cloudwatch_log_group: CloudWatch log group name for logging configuration

    Example: If you provide { jumphost = { foo = "bar" } }, the result will be:
    { jumphost = { foo = "bar", cloudwatch_log_group = "/aws/ec2/jumphost/..." } }

    Both your custom facts and module facts are preserved.
  EOF
  type        = any
  default     = {}
}

variable "puppet_debug_logging" {
  description = "Enable debug logging if true."
  type        = bool
  default     = false
}

variable "puppet_environmentpath" {
  description = "A path for directory environments."
  type        = string
  default     = "{root_directory}/environments"
}

variable "puppet_hiera_config_path" {
  description = "Path to hiera configuration file."
  type        = string
  default     = "{root_directory}/environments/{environment}/hiera.yaml"
}

variable "puppet_manifest" {
  description = "Path to puppet manifest. By default ih-puppet will apply {root_directory}/environments/{environment}/manifests/site.pp."
  type        = string
  default     = null
}

variable "puppet_module_path" {
  description = "Path to common puppet modules."
  type        = string
  default     = "{root_directory}/environments/{environment}/modules:{root_directory}/modules"
}

variable "puppet_root_directory" {
  description = "Path where the puppet code is hosted."
  type        = string
  default     = "/opt/puppet-code"
}

variable "root_volume_size" {
  description = "Root volume size in EC2 instance in Gigabytes."
  type        = number
  default     = 30
}

variable "route53_zone_id" {
  description = "Route53 zone id of a zone where this jumphost will put an A record."
  type        = string
}

variable "route53_hostname" {
  description = "An A record with this name will be created in the Route53 zone."
  type        = string
  default     = "jumphost"
}

variable "route53_ttl" {
  description = "TTL in seconds on the Route53 record."
  type        = number
  default     = 300
}

variable "sns_topic_alarm_arn" {
  description = "ARN of SNS topic for Cloudwatch alarms on base EC2 instance."
  type        = string
  default     = null
}

variable "ssh_host_keys" {
  description = "List of instance's SSH host keys."
  type = list(
    object(
      {
        type : string
        private : string
        public : string
      }
    )
  )
  default = null
}

variable "subnet_ids" {
  description = "List of subnet ids where the jumphost instances will be created."
  type        = list(string)
}

variable "ubuntu_codename" {
  description = "Ubuntu version to use for the jumphost. Only Ubuntu noble is supported ATM."
  type        = string
  default     = "noble"
}

variable "log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 365

  validation {
    condition = contains([
      0, 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180,
      365, 400, 545, 731, 1827, 2192, 2557, 2922, 3288, 3653
    ], var.log_retention_days)
    error_message = "log_retention_days must be a valid CloudWatch retention period."
  }
}

variable "cloudwatch_kms_key_arn" {
  description = "ARN of KMS key for CloudWatch log encryption (null for AWS managed key)"
  type        = string
  default     = null
}
