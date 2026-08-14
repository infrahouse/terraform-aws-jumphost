# Basic Example
# The minimum configuration required to deploy an internet-facing jumphost.

terraform {
  required_version = "~> 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0, < 7.0"
    }
  }
}

provider "aws" {
  region = "us-west-2"
}

locals {
  environment = "development"
}

# Create a VPC with public subnets for the example
module "network" {
  source  = "registry.infrahouse.com/infrahouse/service-network/aws"
  version = "5.0.2"

  environment           = local.environment
  service_name          = "jumphost"
  vpc_cidr_block        = "10.1.0.0/16"
  management_cidr_block = "10.1.0.0/16"
  replication_region    = "us-east-1"
  subnets = [
    {
      cidr                    = "10.1.0.0/24"
      availability_zone       = "us-west-2a"
      map_public_ip_on_launch = true
    },
    {
      cidr                    = "10.1.1.0/24"
      availability_zone       = "us-west-2b"
      map_public_ip_on_launch = true
    }
  ]
}

# Create a Route53 zone (or use an existing one via a data source)
resource "aws_route53_zone" "example" {
  name = "example.com"
}

module "jumphost" {
  source  = "registry.infrahouse.com/infrahouse/jumphost/aws"
  version = "6.0.0"

  environment     = local.environment
  subnet_ids      = module.network.subnet_public_ids
  nlb_subnet_ids  = module.network.subnet_public_ids
  route53_zone_id = aws_route53_zone.example.zone_id

  # Each address receives an SNS subscription confirmation email that
  # must be confirmed before alarm notifications are delivered.
  alarm_emails = ["ops-team@example.com"]

  # InfraHouse Puppet code configures SSH users, the NLB health check
  # echo service, and the CloudWatch agent on the instances.
  puppet_hiera_config_path = "/opt/infrahouse-puppet-data/environments/${local.environment}/hiera.yaml"
  packages = [
    "infrahouse-puppet-data"
  ]
}

output "jumphost_hostname" {
  description = "DNS name to SSH to"
  value       = module.jumphost.jumphost_hostname
}

output "jumphost_asg_name" {
  description = "Auto Scaling Group name"
  value       = module.jumphost.jumphost_asg_name
}

output "cloudwatch_log_group_name" {
  description = "CloudWatch log group with the jumphost audit trail"
  value       = module.jumphost.cloudwatch_log_group_name
}
