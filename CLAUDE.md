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

### Dependencies
- Uses InfraHouse modules:
  - `registry.infrahouse.com/infrahouse/instance-profile/aws` (v1.9.0) - IAM instance profile management
  - `registry.infrahouse.com/infrahouse/cloud-init/aws` (v2.2.2) - Cloud-init configuration

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

### Test Configuration
Tests use pytest with the `pytest-infrahouse` plugin. Key parameters:
- `--aws-region`: AWS region for testing (default: us-west-2)
- `--test-role-arn`: IAM role for cross-account testing
- `--keep-after`: Keep resources after test completion
- Tests create real AWS resources in test_data/jumphost/

## Key Implementation Details

### EFS and Data Persistence
- Home directories are backed by encrypted EFS filesystem mounted at /home
- EFS uses `efs_creation_token` to ensure uniqueness (critical for multiple deployments)
- Changing `efs_creation_token` will destroy and recreate the EFS filesystem

### IAM and Security
- Follows least-privilege principle with minimal IAM permissions
- Additional permissions can be added via:
  - `extra_policies` variable (map of policy ARNs)
  - Direct attachment to the output role (`jumphost_role_name`)

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
When deploying multiple jumphosts in the same AWS account, always provide unique `efs_creation_token` values to avoid EFS conflicts.

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
