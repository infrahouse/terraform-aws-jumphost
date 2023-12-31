# terraform-aws-jumphost

The module creates a jump host to provide SSH access to the AWS network.

![jumphost](https://github.com/infrahouse/terraform-aws-jumphost/assets/1763754/c4e0bf15-c7c6-4bab-8399-a7b5b711bfbc)

The module deploys an autoscaling group with only one EC2 instance that serves as a jump host
to access internal resources not accessible from the Internet otherwise.

To make sense, the autoscaling group has to reside in a public subnet, and the EC2 instance
has to get a public IP address.

When the instance launches or terminates, it updates the Route53 zone, so the jump host
has the DNS name `jumphost.yourzone.com`.

```hcl
module "jumphost" {
  source            = "infrahouse/jumphost/aws"
  version           = "~> 1.2"
  keypair_name      = aws_key_pair.aleks.key_name
  subnet_ids        = module.management.subnet_public_ids
  environment       = var.environment
  route53_zone_id   = module.infrahouse_com.infrahouse_zone_id
  route53_zone_name = module.infrahouse_com.infrahouse_zone_name
  extra_policies = {
    (aws_iam_policy.package-publisher.name) : aws_iam_policy.package-publisher.arn
  }
  gpg_public_key = file("./files/DEB-GPG-KEY-infrahouse-jammy")
}
```

> Note: initial instances do not trigger the DNS lambda. We need to refresh the ASG manually to update DNS.
> This limitation should be fixed in the future.

## IAM instance profile

The module creates an instance profile called `jumphost` 
using the [instance-profile](https://registry.terraform.io/modules/infrahouse/instance-profile/aws/latest) 
module. The profile has a role with a quite limited permissions policy.
```hcl
data "aws_iam_policy_document" "jumphost_permissions" {
  statement {
    actions   = ["ec2:Describe*"]
    resources = ["*"]
  }
}
```
If you need the jump host to have more permissions, attach additional policies to the role.
The role is returned as outputs `jumphost_role_name` and `jumphost_role_arn`.

Alternatively, you can specify a map of additional permissions in the `var.extra_policies` map:

```hcl
module "jumphost" {
...
  extra_policies = {
    (aws_iam_policy.package-publisher.name) : aws_iam_policy.package-publisher.arn
  }
...
}
```
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 5.11 |
| <a name="requirement_cloudinit"></a> [cloudinit](#requirement\_cloudinit) | >= 2.3 |
| <a name="requirement_null"></a> [null](#requirement\_null) | >= 3.2 |
| <a name="requirement_random"></a> [random](#requirement\_random) | >= 3.5 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_archive"></a> [archive](#provider\_archive) | n/a |
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 5.11 |
| <a name="provider_null"></a> [null](#provider\_null) | >= 3.2 |
| <a name="provider_random"></a> [random](#provider\_random) | >= 3.5 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_jumphost_profile"></a> [jumphost\_profile](#module\_jumphost\_profile) | infrahouse/instance-profile/aws | ~> 1.0 |
| <a name="module_jumphost_userdata"></a> [jumphost\_userdata](#module\_jumphost\_userdata) | infrahouse/cloud-init/aws | ~> 1.6 |

## Resources

| Name | Type |
|------|------|
| [aws_autoscaling_group.jumphost](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/autoscaling_group) | resource |
| [aws_autoscaling_lifecycle_hook.launching](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/autoscaling_lifecycle_hook) | resource |
| [aws_autoscaling_lifecycle_hook.terminating](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/autoscaling_lifecycle_hook) | resource |
| [aws_cloudwatch_event_rule.scale](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_event_rule) | resource |
| [aws_cloudwatch_event_target.scale-out](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_event_target) | resource |
| [aws_cloudwatch_log_group.update_dns](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_iam_policy.lambda_logging](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_policy.lambda_permissions](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_policy.required](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_role.iam_for_lambda](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy_attachment.AWSLambdaBasicExecutionRole](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.lambda_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.lambda_permissions](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_lambda_function.update_dns](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_function) | resource |
| [aws_lambda_function_event_invoke_config.update_dns](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_function_event_invoke_config) | resource |
| [aws_lambda_permission.allow_cloudwatch](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_permission) | resource |
| [aws_launch_template.jumphost](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/launch_template) | resource |
| [aws_s3_bucket.lambda_tmp](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket_public_access_block.public_access](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block) | resource |
| [aws_s3_object.lambda_package](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_object) | resource |
| [null_resource.install_python_dependencies](https://registry.terraform.io/providers/hashicorp/null/latest/docs/resources/resource) | resource |
| [random_uuid.lamda_src_hash](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/uuid) | resource |
| [archive_file.lambda](https://registry.terraform.io/providers/hashicorp/archive/latest/docs/data-sources/file) | data source |
| [aws_ami.ubuntu](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ami) | data source |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_iam_policy.AWSLambdaBasicExecutionRole](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy) | data source |
| [aws_iam_policy_document.assume_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.jumphost_permissions](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.lambda-permissions](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.lambda_logging](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.required_permissions](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |
| [aws_route53_zone.jumphost_zone](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/route53_zone) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_ami_id"></a> [ami\_id](#input\_ami\_id) | AMI id for jumphost instances. By default, latest Ubuntu jammy. | `string` | `null` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | Environment name. Passed on as a puppet fact | `string` | n/a | yes |
| <a name="input_extra_files"></a> [extra\_files](#input\_extra\_files) | Additional files to create on an instance. | <pre>list(object({<br>    content     = string<br>    path        = string<br>    permissions = string<br>  }))</pre> | `[]` | no |
| <a name="input_extra_policies"></a> [extra\_policies](#input\_extra\_policies) | A map of additional policy ARNs to attach to the jumphost role | `map(string)` | `{}` | no |
| <a name="input_extra_repos"></a> [extra\_repos](#input\_extra\_repos) | Additional APT repositories to configure on an instance. | <pre>map(object({<br>    source = string<br>    key    = string<br>  }))</pre> | `{}` | no |
| <a name="input_keypair_name"></a> [keypair\_name](#input\_keypair\_name) | SSH key pair name that will be added to the jumphost instance | `string` | n/a | yes |
| <a name="input_packages"></a> [packages](#input\_packages) | List of packages to install when the instances bootstraps. | `list(string)` | `[]` | no |
| <a name="input_puppet_debug_logging"></a> [puppet\_debug\_logging](#input\_puppet\_debug\_logging) | Enable debug logging if true. | `bool` | `false` | no |
| <a name="input_puppet_environmentpath"></a> [puppet\_environmentpath](#input\_puppet\_environmentpath) | A path for directory environments. | `string` | `"{root_directory}/environments"` | no |
| <a name="input_puppet_hiera_config_path"></a> [puppet\_hiera\_config\_path](#input\_puppet\_hiera\_config\_path) | Path to hiera configuration file. | `string` | `"{root_directory}/environments/{environment}/hiera.yaml"` | no |
| <a name="input_puppet_module_path"></a> [puppet\_module\_path](#input\_puppet\_module\_path) | Path to common puppet modules. | `string` | `"{root_directory}/modules"` | no |
| <a name="input_puppet_root_directory"></a> [puppet\_root\_directory](#input\_puppet\_root\_directory) | Path where the puppet code is hosted. | `string` | `"/opt/puppet-code"` | no |
| <a name="input_route53_hostname"></a> [route53\_hostname](#input\_route53\_hostname) | An A record with this name will be created in the rout53 zone | `string` | `"jumphost"` | no |
| <a name="input_route53_ttl"></a> [route53\_ttl](#input\_route53\_ttl) | TTL in seconds on the route53 record | `number` | `300` | no |
| <a name="input_route53_zone_id"></a> [route53\_zone\_id](#input\_route53\_zone\_id) | Route53 zone id of a zone where this jumphost will put an A record | `any` | n/a | yes |
| <a name="input_subnet_ids"></a> [subnet\_ids](#input\_subnet\_ids) | List of subnet ids where the jumphost instances will be created | `list(string)` | n/a | yes |
| <a name="input_ubuntu_codename"></a> [ubuntu\_codename](#input\_ubuntu\_codename) | Ubuntu version to use for the jumphost | `string` | `"jammy"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_jumphost_role_arn"></a> [jumphost\_role\_arn](#output\_jumphost\_role\_arn) | Instance IAM role ARN. |
| <a name="output_jumphost_role_name"></a> [jumphost\_role\_name](#output\_jumphost\_role\_name) | Instance IAM role name. |
