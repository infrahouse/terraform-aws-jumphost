# Basic Example

The minimum configuration required to deploy an internet-facing jumphost with the
terraform-aws-jumphost module.

## What This Example Creates

- VPC with public subnets
- Route53 hosted zone
- Network Load Balancer with a TCP listener on port 22
- Auto Scaling Group of Ubuntu Pro instances
- Encrypted EFS file system mounted at `/home`
- CloudWatch log group for the SSH audit trail
- DNS record `jumphost.example.com` pointing at the NLB

## Prerequisites

- AWS CLI configured with appropriate credentials
- Terraform >= 1.5

## Usage

```bash
terraform init
terraform plan
terraform apply
```

Then connect:

```bash
ssh <your-user>@$(terraform output -raw jumphost_hostname)
```

## Outputs

| Name | Description |
|------|-------------|
| jumphost_hostname | DNS name to SSH to |
| jumphost_asg_name | Auto Scaling Group name |
| cloudwatch_log_group_name | CloudWatch log group with the jumphost audit trail |

## Notes

- The Route53 zone created in this example uses `example.com`. Replace it with your
  actual domain (typically via a `data "aws_route53_zone"` lookup instead).
- SSH users are managed by the Puppet code shipped in the `infrahouse-puppet-data`
  package, not by the Terraform module.
- When deploying more than one jumphost in the same AWS account, set a unique
  `efs_creation_token` for each (see the [documentation](https://infrahouse.github.io/terraform-aws-jumphost/)).
