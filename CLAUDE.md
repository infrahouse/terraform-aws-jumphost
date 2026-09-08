# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Terraform module that creates an AWS jumphost (bastion host) to provide SSH access to AWS network 
resources not accessible from the internet. The module deploys an autoscaling group fronted by 
a Network Load Balancer in public subnets, using Ubuntu Pro images with EFS-backed home directories.

## Architecture & Module Structure

### Core Terraform Components
- **main.tf**: Defines the launch template and ASG configuration with spot instance support
- **nlb.tf**: Network Load Balancer and target group configuration for SSH access
- **efs.tf** & **efs-enc.tf**: EFS file system for persistent /home directory with encryption
- **security_group.tf**: Security group rules for jumphost and EFS access
- **dns.tf**: Route53 DNS record configuration
- **ssh.tf**: SSH host keys generation and management
- **cloudwatch.tf**: Monitoring and alerting configuration
- **cloudwatch-logs.tf**: CloudWatch Logs configuration for security audit trails

### CloudWatch Integration
- **Always-on CloudWatch logging** at `/aws/ec2/jumphost/{environment}/{hostname}.{zone}`
- Log group naming ensures multiple jumphosts can coexist in same environment
- IAM permissions automatically configured for CloudWatch agent
- Log group name passed to instances via Puppet facts for agent configuration
- Default 365-day retention for compliance (configurable via `log_retention_days`)
- Optional custom KMS key support via `cloudwatch_kms_key_arn`
- CloudWatch agent installation and configuration is managed by Puppet

### Dependencies
- Uses InfraHouse modules:
  - `registry.infrahouse.com/infrahouse/instance-profile/aws` (v2.0.0) - IAM instance profile management
  - `registry.infrahouse.com/infrahouse/cloud-init/aws` (v2.4.1) - Cloud-init configuration

## Development Commands

### Building and Linting
```bash
# Format all Terraform files (required before commit)
make format

# Check formatting without modifying files
make lint

# Install git hooks (runs automatically with make help)
make install-hooks
```

### Testing
```bash
# Bootstrap the development environment
make bootstrap

# Run all tests
make test

# Run specific test and keep resources for debugging
make test-keep

# Clean up test resources
make test-clean

# Run a single test
pytest -xvvs -k test_name tests/test_module.py
```

`test-keep` and `test-clean` tee their output to `pytest-<timestamp>-output.log` (gitignored).
The Makefile sets `SHELL`/`.SHELLFLAGS` for `pipefail` so a failing suite is not masked by `tee`.

### Test Configuration
Tests use pytest with the `pytest-infrahouse` plugin. Key parameters:
- `--aws-region`: AWS region for testing (default: us-west-2)
- `--test-role-arn`: IAM role for cross-account testing
- `--keep-after`: Keep resources after test completion
- Tests create real AWS resources in test_data/jumphost/

## Key Implementation Details

### EFS and Data Persistence
- Home directories are backed by encrypted EFS filesystem mounted at /home
- A unique EFS creation token is generated per deployment; `efs_creation_token` overrides it (needed to keep filesystems created by module < 6.0, whose default was `jumphost-home-encrypted`)
- Changing the creation token will destroy and recreate the EFS filesystem

### IAM and Security
- Follows least-privilege principle with minimal IAM permissions
- Additional permissions can be added via:
  - `extra_policies` variable (map of policy ARNs)
  - Direct attachment to the output role (`jumphost_role_name`)

### AWS Inspector Exclusion
- The ASG tags instances `InspectorEc2Exclusion` at launch (`main.tf`), and Puppet's
  `profile::boot_security_upgrade` removes it after applying pending security updates
- `ec2:DeleteTags` in `data_sources.tf` is what allows the removal — scoped to that tag key
  and to instances tagged `created_by_module = infrahouse/jumphost/aws`
- **Fail-open**: an instance whose tag is never removed is invisible to Inspector forever.
  The tag block and the IAM statement must ship together
- `tests/test_module.py` asserts both halves: the ASG propagates the tag at launch, and the
  tag is gone from the instance after bootstrap

### Instance Configuration
- Uses Ubuntu Pro images (currently supports "noble" only)
- Supports both on-demand and spot instances
- Cloud-init handles initial configuration with puppet support

## Pre-commit Hooks

The repository uses pre-commit hooks that automatically:
1. Check Terraform formatting (terraform fmt -check)
2. Update README.md with terraform-docs (if installed)

Hooks are automatically installed when running any make command.

## Common Troubleshooting

### Multiple Jumphost Deployments
Multiple jumphosts coexist in one AWS account without extra configuration: EFS creation tokens are generated per deployment and log groups are namespaced by hostname/zone. Conflicts only arise when `efs_creation_token` is explicitly set to the same value in two deployments.

### Testing
- Tests require AWS credentials and appropriate permissions
- Test resources are created in real AWS environment
- Use `make test-clean` to remove stuck test resources
- Check test_data/jumphost/ for Terraform state during debugging

## Module Outputs

Key outputs available for integration:
- `jumphost_hostname`: DNS hostname for SSH access
- `jumphost_asg_name`: Autoscaling group name
- `jumphost_role_name` / `jumphost_role_arn`: IAM role for permission attachments
- `jumphost_instance_profile_name` / `jumphost_instance_profile__arn`: Instance profile details
- `cloudwatch_log_group_name` / `cloudwatch_log_group_arn`: CloudWatch log group for audit trails
