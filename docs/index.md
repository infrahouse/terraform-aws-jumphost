# InfraHouse jumphost

This Terraform module creates a jump host (bastion) that provides SSH access to AWS network
resources not accessible from the internet.

The module deploys an EC2 Auto Scaling Group fronted by a Network Load Balancer (NLB),
with an encrypted EFS file system mounted at `/home` so user data survives instance
replacements.

## Why This Module?

A bastion host sounds simple until you build one that survives real operations.
A single EC2 instance loses user home directories when it's replaced, becomes a single
point of failure, and quietly drifts out of patch compliance. This module packages the
production-grade answer in one place:

- **Highly available**: an Auto Scaling Group behind a Network Load Balancer — an unhealthy
  instance is replaced automatically and SSH stays reachable at the same DNS name.
- **Nothing is lost on instance replacement**: home directories live on an encrypted EFS
  file system mounted at `/home`, and SSH host keys are stable across instance refreshes,
  so clients never see "host key changed" warnings.
- **Secure by default**: Ubuntu Pro images, encrypted EFS, IMDSv2 required, least-privilege
  IAM, and an always-on CloudWatch audit trail for compliance (SOC 2, ISO 27001).
- **Cost-optimized**: optional spot instances with a configurable on-demand base capacity.
- **Fresh instances, always**: a 90-day maximum instance lifetime and rolling instance
  refresh keep the fleet patched without downtime.

## Features

- Network Load Balancer for high availability SSH access
- Ubuntu Pro images with security updates and compliance certifications
- EFS-backed `/home` directory for data persistence
- Encrypted EFS file system with optional custom KMS key support
- Stable SSH host keys across instance replacements
- Least-privilege IAM permissions with extensible policy support
- Always-on CloudWatch logging for security audit trails
- CloudWatch monitoring and alarms
- Spot instance support with configurable on-demand base capacity
- Route53 DNS record for a stable SSH endpoint
- Internet-facing or internal scheme inferred from the NLB subnets

## Quick Start

```hcl
module "jumphost" {
  source  = "registry.infrahouse.com/infrahouse/jumphost/aws"
  version = "5.0.0"

  environment     = "production"
  subnet_ids      = module.vpc.subnet_public_ids
  nlb_subnet_ids  = module.vpc.subnet_public_ids
  route53_zone_id = data.aws_route53_zone.example.zone_id
}
```

After `terraform apply`, connect with:

```bash
ssh ubuntu@jumphost.example.com
```

## Documentation

- [Getting Started](getting-started.md) — Prerequisites and first deployment
- [Architecture](architecture.md) — How the module works
- [Configuration](configuration.md) — All available options
- [Examples](examples.md) — Common use cases
- [Troubleshooting](troubleshooting.md) — Common issues and solutions
- [Changelog](changelog.md) — Release history
