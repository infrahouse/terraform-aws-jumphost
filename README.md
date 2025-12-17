# terraform-aws-jumphost

The module creates a jump host to provide SSH access to AWS network resources not accessible from the internet.

![jumphost](https://github.com/infrahouse/terraform-aws-jumphost/assets/1763754/c4e0bf15-c7c6-4bab-8399-a7b5b711bfbc)

## Overview

The module deploys an autoscaling group fronted by a Network Load Balancer (NLB) in public subnets.
The jump host instances use Ubuntu Pro images for enhanced security and mount an EFS volume at
`/home` to preserve user data during instance refresh operations.

**Key Features:**
- Network Load Balancer for high availability SSH access
- Ubuntu Pro images with security updates and compliance certifications
- EFS-backed `/home` directory for data persistence
- Encrypted EFS file system with optional custom KMS key support
- Least-privilege IAM permissions with extensible policy support
- CloudWatch monitoring and alarms

```hcl
  module "jumphost" {
  source  = "registry.infrahouse.com/infrahouse/jumphost/aws"
  version = "4.4.0"

  subnet_ids        = module.management.subnet_public_ids
  environment       = var.environment
  route53_zone_id   = module.infrahouse_com.infrahouse_zone_id
  route53_hostname  = "basion"  # jumphost by default
  extra_policies = {
    (aws_iam_policy.package-publisher.name) : aws_iam_policy.package-publisher.arn
  }
}
```
## Deploying Multiple Jumphosts

When deploying multiple jumphost instances in the same AWS account, 
you must provide a unique `efs_creation_token` for each deployment to avoid EFS conflicts:

  ```hcl
  module "jumphost_prod" {
  source  = "registry.infrahouse.com/infrahouse/jumphost/aws"
  version = "4.4.0"

  efs_creation_token = "jumphost-home-prod"
  environment        = "production"
  # ... other configuration ...
}

module "jumphost_staging" {
  source  = "registry.infrahouse.com/infrahouse/jumphost/aws"
  version = "4.4.0"

  efs_creation_token = "jumphost-home-staging"
  environment        = "staging"
  # ... other configuration ...
}

Note: Changing efs_creation_token on an existing deployment will destroy and recreate the EFS file system, 
resulting in data loss. Plan carefully when modifying this value.

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

The CloudWatch log group is automatically created with the naming pattern `/aws/ec2/jumphost/${environment}/${hostname}` and its name is passed to instances via Puppet facts. This naming scheme ensures that multiple jumphosts can coexist in the same environment without conflicts. The Puppet configuration is responsible for installing and configuring the CloudWatch agent to ship logs to this log group.

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
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 5.31, < 7.0 |
| <a name="requirement_random"></a> [random](#requirement\_random) | >= 3.5 |
| <a name="requirement_tls"></a> [tls](#requirement\_tls) | >= 4.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 5.31, < 7.0 |
| <a name="provider_random"></a> [random](#provider\_random) | >= 3.5 |
| <a name="provider_tls"></a> [tls](#provider\_tls) | >= 4.0 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_jumphost_profile"></a> [jumphost\_profile](#module\_jumphost\_profile) | registry.infrahouse.com/infrahouse/instance-profile/aws | 1.9.0 |
| <a name="module_jumphost_userdata"></a> [jumphost\_userdata](#module\_jumphost\_userdata) | registry.infrahouse.com/infrahouse/cloud-init/aws | 2.2.2 |

## Resources

| Name | Type |
|------|------|
| [aws_autoscaling_group.jumphost](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/autoscaling_group) | resource |
| [aws_cloudwatch_log_group.jumphost](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
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
| [aws_vpc_security_group_egress_rule.default](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_egress_rule.efs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.echo](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.efs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.efs_icmp](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.icmp](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.ssh](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [random_string.asg_name](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/string) | resource |
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
| <a name="input_ami_id"></a> [ami\_id](#input\_ami\_id) | AMI id for jumphost instances. By default, latest Ubuntu Pro var.ubuntu\_codename. | `string` | `null` | no |
| <a name="input_asg_max_size"></a> [asg\_max\_size](#input\_asg\_max\_size) | Maximum number of EC2 instances in the ASG. By default, the number of subnets plus one | `number` | `null` | no |
| <a name="input_asg_min_size"></a> [asg\_min\_size](#input\_asg\_min\_size) | Minimal number of EC2 instances in the ASG. By default, the number of subnets. | `number` | `null` | no |
| <a name="input_cloudwatch_kms_key_arn"></a> [cloudwatch\_kms\_key\_arn](#input\_cloudwatch\_kms\_key\_arn) | ARN of KMS key for CloudWatch log encryption (null for AWS managed key) | `string` | `null` | no |
| <a name="input_efs_creation_token"></a> [efs\_creation\_token](#input\_efs\_creation\_token) | A unique name used as reference when creating the EFS file system. Must be unique across all EFS file systems in the AWS account. Change this value when creating multiple jumphosts to avoid conflicts. | `string` | `"jumphost-home-encrypted"` | no |
| <a name="input_efs_kms_key_arn"></a> [efs\_kms\_key\_arn](#input\_efs\_kms\_key\_arn) | KMS key ARN to use for EFS encryption. If not specified, AWS will use the default AWS managed key for EFS. | `string` | `null` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | Environment name. Passed on as a puppet fact. | `string` | n/a | yes |
| <a name="input_extra_files"></a> [extra\_files](#input\_extra\_files) | Additional files to create on an instance. | <pre>list(<br/>    object(<br/>      {<br/>        content     = string<br/>        path        = string<br/>        permissions = string<br/>      }<br/>    )<br/>  )</pre> | `[]` | no |
| <a name="input_extra_policies"></a> [extra\_policies](#input\_extra\_policies) | A map of additional policy ARNs to attach to the jumphost role. | `map(string)` | `{}` | no |
| <a name="input_extra_repos"></a> [extra\_repos](#input\_extra\_repos) | Additional APT repositories to configure on an instance. | <pre>map(<br/>    object(<br/>      {<br/>        source = string<br/>        key    = string<br/>      }<br/>    )<br/>  )</pre> | `{}` | no |
| <a name="input_instance_role_name"></a> [instance\_role\_name](#input\_instance\_role\_name) | If specified, the instance profile will have a role with this name. | `string` | `null` | no |
| <a name="input_instance_type"></a> [instance\_type](#input\_instance\_type) | EC2 Instance type. | `string` | `"t3a.micro"` | no |
| <a name="input_keypair_name"></a> [keypair\_name](#input\_keypair\_name) | SSH key pair name that will be added to the jumphost instance. | `string` | `null` | no |
| <a name="input_log_retention_days"></a> [log\_retention\_days](#input\_log\_retention\_days) | Number of days to retain CloudWatch logs | `number` | `365` | no |
| <a name="input_nlb_subnet_ids"></a> [nlb\_subnet\_ids](#input\_nlb\_subnet\_ids) | List of subnet ids where the NLB will be created. | `list(string)` | n/a | yes |
| <a name="input_on_demand_base_capacity"></a> [on\_demand\_base\_capacity](#input\_on\_demand\_base\_capacity) | If specified, the ASG will request spot instances and this will be the minimal number of on-demand instances. | `number` | `null` | no |
| <a name="input_packages"></a> [packages](#input\_packages) | List of packages to install when the instance bootstraps. | `list(string)` | `[]` | no |
| <a name="input_puppet_custom_facts"></a> [puppet\_custom\_facts](#input\_puppet\_custom\_facts) | A map of custom puppet facts. The module uses deep merge to combine user facts<br/>with module-managed facts. User-provided values take precedence on conflicts.<br/><br/>Module automatically provides:<br/>- jumphost.cloudwatch\_log\_group: CloudWatch log group name for logging configuration<br/><br/>Example: If you provide { jumphost = { foo = "bar" } }, the result will be:<br/>{ jumphost = { foo = "bar", cloudwatch\_log\_group = "/aws/ec2/jumphost/..." } }<br/><br/>Both your custom facts and module facts are preserved. | `any` | `{}` | no |
| <a name="input_puppet_debug_logging"></a> [puppet\_debug\_logging](#input\_puppet\_debug\_logging) | Enable debug logging if true. | `bool` | `false` | no |
| <a name="input_puppet_environmentpath"></a> [puppet\_environmentpath](#input\_puppet\_environmentpath) | A path for directory environments. | `string` | `"{root_directory}/environments"` | no |
| <a name="input_puppet_hiera_config_path"></a> [puppet\_hiera\_config\_path](#input\_puppet\_hiera\_config\_path) | Path to hiera configuration file. | `string` | `"{root_directory}/environments/{environment}/hiera.yaml"` | no |
| <a name="input_puppet_manifest"></a> [puppet\_manifest](#input\_puppet\_manifest) | Path to puppet manifest. By default ih-puppet will apply {root\_directory}/environments/{environment}/manifests/site.pp. | `string` | `null` | no |
| <a name="input_puppet_module_path"></a> [puppet\_module\_path](#input\_puppet\_module\_path) | Path to common puppet modules. | `string` | `"{root_directory}/environments/{environment}/modules:{root_directory}/modules"` | no |
| <a name="input_puppet_root_directory"></a> [puppet\_root\_directory](#input\_puppet\_root\_directory) | Path where the puppet code is hosted. | `string` | `"/opt/puppet-code"` | no |
| <a name="input_root_volume_size"></a> [root\_volume\_size](#input\_root\_volume\_size) | Root volume size in EC2 instance in Gigabytes. | `number` | `30` | no |
| <a name="input_route53_hostname"></a> [route53\_hostname](#input\_route53\_hostname) | An A record with this name will be created in the Route53 zone. | `string` | `"jumphost"` | no |
| <a name="input_route53_ttl"></a> [route53\_ttl](#input\_route53\_ttl) | TTL in seconds on the Route53 record. | `number` | `300` | no |
| <a name="input_route53_zone_id"></a> [route53\_zone\_id](#input\_route53\_zone\_id) | Route53 zone id of a zone where this jumphost will put an A record. | `string` | n/a | yes |
| <a name="input_sns_topic_alarm_arn"></a> [sns\_topic\_alarm\_arn](#input\_sns\_topic\_alarm\_arn) | ARN of SNS topic for Cloudwatch alarms on base EC2 instance. | `string` | `null` | no |
| <a name="input_ssh_host_keys"></a> [ssh\_host\_keys](#input\_ssh\_host\_keys) | List of instance's SSH host keys. | <pre>list(<br/>    object(<br/>      {<br/>        type : string<br/>        private : string<br/>        public : string<br/>      }<br/>    )<br/>  )</pre> | `null` | no |
| <a name="input_subnet_ids"></a> [subnet\_ids](#input\_subnet\_ids) | List of subnet ids where the jumphost instances will be created. | `list(string)` | n/a | yes |
| <a name="input_ubuntu_codename"></a> [ubuntu\_codename](#input\_ubuntu\_codename) | Ubuntu version to use for the jumphost. Only Ubuntu noble is supported ATM. | `string` | `"noble"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_cloudwatch_log_group_arn"></a> [cloudwatch\_log\_group\_arn](#output\_cloudwatch\_log\_group\_arn) | ARN of the CloudWatch log group for jumphost logs |
| <a name="output_cloudwatch_log_group_name"></a> [cloudwatch\_log\_group\_name](#output\_cloudwatch\_log\_group\_name) | Name of the CloudWatch log group for jumphost logs |
| <a name="output_jumphost_asg_name"></a> [jumphost\_asg\_name](#output\_jumphost\_asg\_name) | Jumphost autoscaling group |
| <a name="output_jumphost_hostname"></a> [jumphost\_hostname](#output\_jumphost\_hostname) | n/a |
| <a name="output_jumphost_instance_profile__arn"></a> [jumphost\_instance\_profile\_\_arn](#output\_jumphost\_instance\_profile\_\_arn) | Instance IAM profile ARN. |
| <a name="output_jumphost_instance_profile_name"></a> [jumphost\_instance\_profile\_name](#output\_jumphost\_instance\_profile\_name) | Instance IAM profile name. |
| <a name="output_jumphost_role_arn"></a> [jumphost\_role\_arn](#output\_jumphost\_role\_arn) | Instance IAM role ARN. |
| <a name="output_jumphost_role_name"></a> [jumphost\_role\_name](#output\_jumphost\_role\_name) | Instance IAM role name. |
<!-- END_TF_DOCS -->
