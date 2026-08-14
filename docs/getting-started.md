# Getting Started

This guide walks you through deploying your first jump host with the InfraHouse jumphost module.

## Prerequisites

### AWS Resources

Before deploying, you need:

1. **A VPC with subnets** — subnets for the jump host instances (`subnet_ids`) and subnets
   for the Network Load Balancer (`nlb_subnet_ids`). They can be the same subnets. For an
   internet-facing jump host, place the NLB in public subnets.
2. **A Route53 hosted zone** — the module creates a DNS record for the jump host in it.

!!! tip "Public or private?"

    The module infers the NLB scheme from the **NLB subnets**: subnets with
    `map_public_ip_on_launch = true` produce an internet-facing NLB, others an internal one.
    When the NLB is internal, SSH access is restricted to the VPC CIDR instead of `0.0.0.0/0`.
    You don't configure the scheme explicitly.

### Tooling

- Terraform >= 1.5
- AWS provider >= 6.0
- AWS credentials with permissions to create EC2, EFS, ELB, IAM, Route53,
  and CloudWatch resources

### Instance Configuration

The instances bootstrap with cloud-init and Puppet using the
[InfraHouse cloud-init module](https://github.com/infrahouse/terraform-aws-cloud-init).
The Puppet code configures SSH users, the echo service used by NLB health checks, and the
CloudWatch agent. The simplest way to provide it is to install the `infrahouse-puppet-data`
package, as the example below does.

## Basic Deployment

### Step 1: Look Up the Hosted Zone

```hcl
data "aws_route53_zone" "example" {
  name = "example.com"
}
```

### Step 2: Deploy the Module

```hcl
module "jumphost" {
  source  = "registry.infrahouse.com/infrahouse/jumphost/aws"
  version = "5.0.0"

  environment      = "production"
  subnet_ids       = module.vpc.subnet_public_ids
  nlb_subnet_ids   = module.vpc.subnet_public_ids
  route53_zone_id  = data.aws_route53_zone.example.zone_id
  route53_hostname = "jumphost" # the default

  puppet_hiera_config_path = "/opt/infrahouse-puppet-data/environments/production/hiera.yaml"
  packages = [
    "infrahouse-puppet-data"
  ]
}
```

### Step 3: Apply and Verify

```bash
terraform init
terraform plan
terraform apply
```

Verify DNS and connectivity:

```bash
dig jumphost.example.com
ssh ubuntu@jumphost.example.com
```

The first instance can take a few minutes to pass health checks while cloud-init
and Puppet configure it.

## What Gets Created

- A Network Load Balancer with a TCP listener on port 22
- A target group with TCP health checks and source IP stickiness
- An Auto Scaling Group of Ubuntu Pro instances spanning `subnet_ids`
- An encrypted EFS file system with mount targets in each subnet, mounted at `/home`
- Generated SSH host keys (RSA, ECDSA, ED25519) shared by all instances
- An IAM instance profile with least-privilege permissions
- A CloudWatch log group at `/aws/ec2/jumphost/<environment>/<hostname>.<zone>`
- Security groups for the jump host instances and the EFS mount targets
- A Route53 record `<route53_hostname>.<zone name>` pointing at the NLB

## SSH Access

Users and their SSH public keys are managed by Puppet, not by this module.
With `infrahouse-puppet-data`, users are defined in Hiera data.

Because home directories live on EFS, anything a user stores under `/home`
survives instance replacements. SSH host keys are generated once by Terraform
and shared by all instances, so the jump host identity is stable and clients
never see "REMOTE HOST IDENTIFICATION HAS CHANGED" warnings.

## Next Steps

- [Review the architecture](architecture.md) to understand how the pieces fit together
- [Explore configuration options](configuration.md) for sizing, spot instances, and logging
- [See more examples](examples.md) including spot instances and multiple jumphosts
