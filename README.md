# terraform-aws-jumphost

[![Need Help?](https://img.shields.io/badge/Need%20Help%3F-Contact%20Us-0066CC)](https://infrahouse.com/contact)
[![Docs](https://img.shields.io/badge/docs-github.io-blue)](https://infrahouse.github.io/terraform-aws-jumphost/)
[![Registry](https://img.shields.io/badge/Terraform-Registry-purple?logo=terraform)](https://registry.terraform.io/modules/infrahouse/jumphost/aws/latest)
[![Release](https://img.shields.io/github/release/infrahouse/terraform-aws-jumphost.svg)](https://github.com/infrahouse/terraform-aws-jumphost/releases/latest)
[![AWS EC2](https://img.shields.io/badge/AWS-EC2-orange?logo=amazonec2)](https://aws.amazon.com/ec2/)
[![AWS EFS](https://img.shields.io/badge/AWS-EFS-orange?logo=amazonwebservices)](https://aws.amazon.com/efs/)
[![Security](https://img.shields.io/github/actions/workflow/status/infrahouse/terraform-aws-jumphost/vuln-scanner-pr.yml?label=Security)](https://github.com/infrahouse/terraform-aws-jumphost/actions/workflows/vuln-scanner-pr.yml)
[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)

The module creates a jump host to provide SSH access to AWS network resources not accessible from the internet.

![jumphost](https://github.com/infrahouse/terraform-aws-jumphost/assets/1763754/c4e0bf15-c7c6-4bab-8399-a7b5b711bfbc)

## Why This Module?

A bastion host sounds simple until you build one that survives real operations. A single EC2 instance
loses user home directories when it's replaced, becomes a single point of failure, and quietly drifts
out of patch compliance. This module packages the production-grade answer in one place:

- **Highly available**: An autoscaling group fronted by a Network Load Balancer — an unhealthy
  instance is replaced automatically and SSH stays reachable at the same DNS name.
- **Nothing is lost on instance replacement**: Home directories live on an encrypted EFS file system
  mounted at `/home`, and SSH host keys are stable across instance refreshes, so clients never see
  "host key changed" warnings.
- **Secure by default**: Ubuntu Pro images, encrypted EFS, IMDSv2 required, least-privilege IAM,
  and an always-on CloudWatch audit trail for compliance (SOC 2, ISO 27001).
- **Cost-optimized**: Optional spot instances with a configurable on-demand base capacity.

## Overview

The module deploys an autoscaling group fronted by a Network Load Balancer (NLB) in public subnets.
The jump host instances use Ubuntu Pro images for enhanced security and mount an EFS volume at
`/home` to preserve user data during instance refresh operations.

## Features

- Network Load Balancer for high availability SSH access
- Ubuntu Pro images with security updates and compliance certifications
- Patched before the first AWS Inspector scan, so a fresh instance never opens a finding
- EFS-backed `/home` directory for data persistence
- Encrypted EFS file system with optional custom KMS key support
- Stable SSH host keys across instance replacements
- Least-privilege IAM permissions with extensible policy support
- Always-on CloudWatch logging for security audit trails
- CloudWatch monitoring and alarms
- Spot instance support with configurable on-demand base capacity
- Route53 DNS record for a stable SSH endpoint

## Documentation

For detailed documentation, visit the [GitHub Pages documentation site](https://infrahouse.github.io/terraform-aws-jumphost/).

- [Getting Started](https://infrahouse.github.io/terraform-aws-jumphost/getting-started/)
- [Architecture](https://infrahouse.github.io/terraform-aws-jumphost/architecture/)
- [Configuration Reference](https://infrahouse.github.io/terraform-aws-jumphost/configuration/)
- [Examples](https://infrahouse.github.io/terraform-aws-jumphost/examples/)
- [Troubleshooting](https://infrahouse.github.io/terraform-aws-jumphost/troubleshooting/)

## Quick Start

```hcl
module "jumphost" {
  source  = "registry.infrahouse.com/infrahouse/jumphost/aws"
  version = "6.1.1"

  environment      = var.environment
  subnet_ids       = module.management.subnet_public_ids
  nlb_subnet_ids   = module.management.subnet_public_ids
  route53_zone_id  = module.infrahouse_com.infrahouse_zone_id
  route53_hostname = "bastion" # jumphost by default
  alarm_emails     = ["ops-team@example.com"]
  extra_policies = {
    (aws_iam_policy.package-publisher.name) : aws_iam_policy.package-publisher.arn
  }
}
```
## Deploying Multiple Jumphosts

Multiple jumphosts coexist in the same AWS account out of the box: the module generates
a unique EFS creation token per deployment, and CloudWatch log groups are namespaced by
hostname and zone. Give each jumphost its own `route53_hostname` (or zone) and deploy:

```hcl
module "jumphost_prod" {
  source  = "registry.infrahouse.com/infrahouse/jumphost/aws"
  version = "6.1.1"

  environment      = "production"
  route53_hostname = "jumphost"
  # ... other configuration ...
}

module "jumphost_staging" {
  source  = "registry.infrahouse.com/infrahouse/jumphost/aws"
  version = "6.1.1"

  environment      = "staging"
  route53_hostname = "jumphost-staging"
  # ... other configuration ...
}
```

Note: Set `efs_creation_token` explicitly only to keep a file system created by module
version < 6.0 (the old default was `jumphost-home-encrypted`). Changing the token on an
existing deployment will destroy and recreate the EFS file system, resulting in data loss.

## IAM instance profile

The module creates an instance profile called `jumphost` using the [instance-profile](https://registry.terraform.io/modules/infrahouse/instance-profile/aws/latest) module.

The instance profile follows the **principle of least privilege**, granting only essential permissions:

```hcl
  data "aws_iam_policy_document" "jumphost_permissions" {
    statement {
      actions   = ["ec2:DescribeInstances"]
      resources = ["*"]
    }
    statement {
      actions = ["autoscaling:DescribeAutoScalingInstances"]
      resources = [
        aws_autoscaling_group.jumphost.arn
      ]
    }
    # Lets Puppet drop the InspectorEc2Exclusion tag once security updates
    # are applied. Restricted to that one tag key, on instances this module
    # created.
    statement {
      actions   = ["ec2:DeleteTags"]
      resources = ["arn:aws:ec2:*:${data.aws_caller_identity.current.account_id}:instance/*"]
      condition {
        test     = "ForAllValues:StringEquals"
        variable = "aws:TagKeys"
        values   = ["InspectorEc2Exclusion"]
      }
      condition {
        test     = "StringEquals"
        variable = "ec2:ResourceTag/created_by_module"
        values   = ["infrahouse/jumphost/aws"]
      }
    }
  }
```

### Adding additional permissions

**Method 1**: Attach policies to the existing role

```hcl
  resource "aws_iam_role_policy_attachment" "additional" {
    role       = module.jumphost.jumphost_role_name
    policy_arn = aws_iam_policy.your_policy.arn
  }
```

**Method 2**: Use the extra_policies variable

```hcl
  module "jumphost" {
    # ... other configuration ...
    extra_policies = {
      "s3-access"    = aws_iam_policy.s3_policy.arn
      "ssm-access"   = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
    }
  }

```

> Note: The jumphost role name and ARN are available as outputs: `jumphost_role_name` and `jumphost_role_arn`.

## CloudWatch Logging

The module creates a CloudWatch log group for centralized logging and audit trails. This is a **mandatory** security feature that cannot be disabled.

The CloudWatch log group is automatically created with the naming pattern `/aws/ec2/jumphost/${environment}/${hostname}.${zone}` and its name is passed to instances via Puppet facts. Because the hostname/zone pair is unique per deployment, multiple jumphosts can coexist in the same environment — even in the same AWS account — without conflicts. The Puppet configuration is responsible for installing and configuring the CloudWatch agent to ship logs to this log group.

### Log Configuration

```hcl
module "jumphost" {
  # ... other configuration ...

  # CloudWatch log retention (default: 365 days for compliance)
  log_retention_days = 365

  # Custom KMS key for log encryption (optional)
  cloudwatch_kms_key_arn = aws_kms_key.logs.arn
}
```

### Cost Estimate
- Log ingestion: ~$0.50/GB
- Log storage: ~$0.03/GB/month
- Typical cost: ~$3/month per jumphost

### Outputs
- `cloudwatch_log_group_name` - Log group name for the jumphost
- `cloudwatch_log_group_arn` - Log group ARN for IAM policies

<!-- BEGIN_TF_DOCS -->

## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.7 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.0, < 7.0 |
| <a name="requirement_random"></a> [random](#requirement\_random) | >= 3.5 |
| <a name="requirement_tls"></a> [tls](#requirement\_tls) | >= 4.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 6.0, < 7.0 |
| <a name="provider_random"></a> [random](#provider\_random) | >= 3.5 |
| <a name="provider_tls"></a> [tls](#provider\_tls) | >= 4.0 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_jumphost_profile"></a> [jumphost\_profile](#module\_jumphost\_profile) | registry.infrahouse.com/infrahouse/instance-profile/aws | 2.0.0 |
| <a name="module_jumphost_userdata"></a> [jumphost\_userdata](#module\_jumphost\_userdata) | registry.infrahouse.com/infrahouse/cloud-init/aws | 2.4.1 |

## Resources

| Name | Type |
|------|------|
| [aws_autoscaling_group.jumphost](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/autoscaling_group) | resource |
| [aws_cloudwatch_log_group.jumphost_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_cloudwatch_metric_alarm.cpu_utilization_alarm](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_efs_file_system.home-enc](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/efs_file_system) | resource |
| [aws_efs_mount_target.home-enc](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/efs_mount_target) | resource |
| [aws_iam_policy.required](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_key_pair.deployer](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/key_pair) | resource |
| [aws_launch_template.jumphost](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/launch_template) | resource |
| [aws_lb.jumphost](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb) | resource |
| [aws_lb_listener.jumphost](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener) | resource |
| [aws_lb_target_group.jumphost](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_target_group) | resource |
| [aws_route53_record.jumphost_cname](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record) | resource |
| [aws_security_group.efs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.jumphost](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_sns_topic.alarms](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sns_topic) | resource |
| [aws_sns_topic_subscription.alarm_emails](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sns_topic_subscription) | resource |
| [aws_vpc_security_group_egress_rule.default](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_egress_rule.efs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.echo](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.efs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.efs_icmp](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.icmp](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.ssh](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [random_string.asg_name](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/string) | resource |
| [random_string.efs_token](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/string) | resource |
| [random_string.profile-suffix](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/string) | resource |
| [tls_private_key.deployer](https://registry.terraform.io/providers/hashicorp/tls/latest/docs/resources/private_key) | resource |
| [tls_private_key.ecdsa](https://registry.terraform.io/providers/hashicorp/tls/latest/docs/resources/private_key) | resource |
| [tls_private_key.ed25519](https://registry.terraform.io/providers/hashicorp/tls/latest/docs/resources/private_key) | resource |
| [tls_private_key.rsa](https://registry.terraform.io/providers/hashicorp/tls/latest/docs/resources/private_key) | resource |
| [aws_ami.selected](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ami) | data source |
| [aws_ami.ubuntu_pro](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ami) | data source |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_default_tags.provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/default_tags) | data source |
| [aws_iam_policy_document.cloudwatch_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.combined_permissions](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.required_permissions](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_kms_key.efs_default](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/kms_key) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |
| [aws_route53_zone.jumphost_zone](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/route53_zone) | data source |
| [aws_subnet.nlb_selected](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/subnet) | data source |
| [aws_subnet.selected](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/subnet) | data source |
| [aws_vpc.selected](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/vpc) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_alarm_emails"></a> [alarm\_emails](#input\_alarm\_emails) | List of email addresses to receive CloudWatch alarm notifications.<br/>AWS SNS sends a confirmation email to each address - recipients MUST<br/>click the confirmation link to activate notifications. Until confirmed,<br/>alarms fire but notifications are not delivered. | `list(string)` | n/a | yes |
| <a name="input_ami_id"></a> [ami\_id](#input\_ami\_id) | AMI id for jumphost instances. By default, latest Ubuntu Pro var.ubuntu\_codename. | `string` | `null` | no |
| <a name="input_asg_max_size"></a> [asg\_max\_size](#input\_asg\_max\_size) | Maximum number of EC2 instances in the ASG. By default, the number of subnets plus one | `number` | `null` | no |
| <a name="input_asg_min_size"></a> [asg\_min\_size](#input\_asg\_min\_size) | Minimal number of EC2 instances in the ASG. By default, the number of subnets. | `number` | `null` | no |
| <a name="input_cloudwatch_kms_key_arn"></a> [cloudwatch\_kms\_key\_arn](#input\_cloudwatch\_kms\_key\_arn) | ARN of KMS key for CloudWatch log encryption (null for AWS managed key) | `string` | `null` | no |
| <a name="input_cloudwatch_namespace"></a> [cloudwatch\_namespace](#input\_cloudwatch\_namespace) | CloudWatch namespace for custom metrics published by the jumphost | `string` | `"Jumphost/System"` | no |
| <a name="input_efs_creation_token"></a> [efs\_creation\_token](#input\_efs\_creation\_token) | A unique name used as reference when creating the EFS file system.<br/>Must be unique across all EFS file systems in the AWS account.<br/>By default, a unique token is generated per deployment. Set it explicitly<br/>to keep a filesystem created by module version < 6.0 (the old default was<br/>"jumphost-home-encrypted"). Changing the token replaces the filesystem<br/>and destroys its data. | `string` | `null` | no |
| <a name="input_efs_kms_key_arn"></a> [efs\_kms\_key\_arn](#input\_efs\_kms\_key\_arn) | KMS key ARN to use for EFS encryption.<br/>If not specified, AWS will use the default AWS managed key for EFS. | `string` | `null` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | Environment name. Passed on as a puppet fact. | `string` | n/a | yes |
| <a name="input_extra_files"></a> [extra\_files](#input\_extra\_files) | Additional files to create on an instance. | <pre>list(<br/>    object(<br/>      {<br/>        content     = string<br/>        path        = string<br/>        permissions = string<br/>      }<br/>    )<br/>  )</pre> | `[]` | no |
| <a name="input_extra_policies"></a> [extra\_policies](#input\_extra\_policies) | A map of additional policy ARNs to attach to the jumphost role. | `map(string)` | `{}` | no |
| <a name="input_extra_repos"></a> [extra\_repos](#input\_extra\_repos) | Additional APT repositories to configure on an instance. | <pre>map(<br/>    object(<br/>      {<br/>        source = string<br/>        key    = string<br/>      }<br/>    )<br/>  )</pre> | `{}` | no |
| <a name="input_instance_role_name"></a> [instance\_role\_name](#input\_instance\_role\_name) | If specified, the instance profile will have a role with this name. | `string` | `null` | no |
| <a name="input_instance_type"></a> [instance\_type](#input\_instance\_type) | EC2 Instance type. | `string` | `"t3a.micro"` | no |
| <a name="input_keypair_name"></a> [keypair\_name](#input\_keypair\_name) | SSH key pair name that will be added to the jumphost instance. | `string` | `null` | no |
| <a name="input_log_retention_days"></a> [log\_retention\_days](#input\_log\_retention\_days) | Number of days to retain CloudWatch logs | `number` | `365` | no |
| <a name="input_nlb_subnet_ids"></a> [nlb\_subnet\_ids](#input\_nlb\_subnet\_ids) | List of subnet ids where the NLB will be created. | `list(string)` | n/a | yes |
| <a name="input_on_demand_base_capacity"></a> [on\_demand\_base\_capacity](#input\_on\_demand\_base\_capacity) | If specified, the ASG will request spot instances<br/>and this will be the minimal number of on-demand instances. | `number` | `null` | no |
| <a name="input_packages"></a> [packages](#input\_packages) | List of packages to install when the instance bootstraps. | `list(string)` | `[]` | no |
| <a name="input_puppet_custom_facts"></a> [puppet\_custom\_facts](#input\_puppet\_custom\_facts) | A map of custom puppet facts. The module uses deep merge to combine user facts<br/>with module-managed facts. User-provided values take precedence on conflicts.<br/><br/>Module automatically provides:<br/>- jumphost.cloudwatch\_log\_group: CloudWatch log group name for logging configuration<br/>- jumphost.cloudwatch\_namespace: CloudWatch namespace for custom metrics<br/><br/>Example: If you provide { jumphost = { foo = "bar" } }, the result will be:<br/>{ jumphost = { foo = "bar", cloudwatch\_log\_group = "/aws/ec2/jumphost/...",<br/>  cloudwatch\_namespace = "Jumphost/System" } }<br/><br/>Both your custom facts and module facts are preserved. | `any` | `{}` | no |
| <a name="input_puppet_debug_logging"></a> [puppet\_debug\_logging](#input\_puppet\_debug\_logging) | Enable debug logging if true. | `bool` | `false` | no |
| <a name="input_puppet_environmentpath"></a> [puppet\_environmentpath](#input\_puppet\_environmentpath) | A path for directory environments. | `string` | `"{root_directory}/environments"` | no |
| <a name="input_puppet_hiera_config_path"></a> [puppet\_hiera\_config\_path](#input\_puppet\_hiera\_config\_path) | Path to hiera configuration file. | `string` | `"{root_directory}/environments/{environment}/hiera.yaml"` | no |
| <a name="input_puppet_manifest"></a> [puppet\_manifest](#input\_puppet\_manifest) | Path to puppet manifest. By default ih-puppet will apply<br/>{root\_directory}/environments/{environment}/manifests/site.pp. | `string` | `null` | no |
| <a name="input_puppet_module_path"></a> [puppet\_module\_path](#input\_puppet\_module\_path) | Path to common puppet modules. | `string` | `"{root_directory}/environments/{environment}/modules:{root_directory}/modules"` | no |
| <a name="input_puppet_root_directory"></a> [puppet\_root\_directory](#input\_puppet\_root\_directory) | Path where the puppet code is hosted. | `string` | `"/opt/puppet-code"` | no |
| <a name="input_root_volume_size"></a> [root\_volume\_size](#input\_root\_volume\_size) | Root volume size in EC2 instance in Gigabytes. | `number` | `30` | no |
| <a name="input_route53_hostname"></a> [route53\_hostname](#input\_route53\_hostname) | An A record with this name will be created in the Route53 zone. | `string` | `"jumphost"` | no |
| <a name="input_route53_ttl"></a> [route53\_ttl](#input\_route53\_ttl) | TTL in seconds on the Route53 record. | `number` | `300` | no |
| <a name="input_route53_zone_id"></a> [route53\_zone\_id](#input\_route53\_zone\_id) | Route53 zone id of a zone where this jumphost will put an A record. | `string` | n/a | yes |
| <a name="input_ssh_host_keys"></a> [ssh\_host\_keys](#input\_ssh\_host\_keys) | List of instance's SSH host keys. | <pre>list(<br/>    object(<br/>      {<br/>        type : string<br/>        private : string<br/>        public : string<br/>      }<br/>    )<br/>  )</pre> | `null` | no |
| <a name="input_subnet_ids"></a> [subnet\_ids](#input\_subnet\_ids) | List of subnet ids where the jumphost instances will be created. | `list(string)` | n/a | yes |
| <a name="input_ubuntu_codename"></a> [ubuntu\_codename](#input\_ubuntu\_codename) | Ubuntu version to use for the jumphost. Only Ubuntu noble is supported ATM. | `string` | `"noble"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_alarm_sns_topic_arn"></a> [alarm\_sns\_topic\_arn](#output\_alarm\_sns\_topic\_arn) | ARN of the SNS topic that receives CloudWatch alarm notifications. |
| <a name="output_cloudwatch_log_group_arn"></a> [cloudwatch\_log\_group\_arn](#output\_cloudwatch\_log\_group\_arn) | ARN of the CloudWatch log group for jumphost logs |
| <a name="output_cloudwatch_log_group_name"></a> [cloudwatch\_log\_group\_name](#output\_cloudwatch\_log\_group\_name) | Name of the CloudWatch log group for jumphost logs |
| <a name="output_jumphost_asg_name"></a> [jumphost\_asg\_name](#output\_jumphost\_asg\_name) | Jumphost autoscaling group |
| <a name="output_jumphost_hostname"></a> [jumphost\_hostname](#output\_jumphost\_hostname) | n/a |
| <a name="output_jumphost_instance_profile__arn"></a> [jumphost\_instance\_profile\_\_arn](#output\_jumphost\_instance\_profile\_\_arn) | Instance IAM profile ARN. |
| <a name="output_jumphost_instance_profile_name"></a> [jumphost\_instance\_profile\_name](#output\_jumphost\_instance\_profile\_name) | Instance IAM profile name. |
| <a name="output_jumphost_role_arn"></a> [jumphost\_role\_arn](#output\_jumphost\_role\_arn) | Instance IAM role ARN. |
| <a name="output_jumphost_role_name"></a> [jumphost\_role\_name](#output\_jumphost\_role\_name) | Instance IAM role name. |
<!-- END_TF_DOCS -->

## Examples

Working examples live in the [examples/](examples/) directory:

- [examples/basic](examples/basic) — a minimal internet-facing jumphost
- [examples/spot-instances](examples/spot-instances) — a cost-optimized jumphost running on spot instances

The [test_data/jumphost](test_data/jumphost) root module used by the integration tests
is another complete, working configuration.

## Contributing

Contributions are welcome! See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

This module is licensed under the Apache License 2.0. See [LICENSE](LICENSE) for details.
