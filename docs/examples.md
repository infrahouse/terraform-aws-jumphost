# Examples

Common jumphost configurations. Complete, working root modules live in the
[examples/](https://github.com/infrahouse/terraform-aws-jumphost/tree/main/examples)
directory of the repository.

## Basic Internet-Facing Jumphost

The minimal production setup: instances and NLB in public subnets, DNS record
`jumphost.example.com`.

```hcl
data "aws_route53_zone" "example" {
  name = "example.com"
}

module "jumphost" {
  source  = "registry.infrahouse.com/infrahouse/jumphost/aws"
  version = "5.0.0"

  environment     = "production"
  subnet_ids      = module.vpc.subnet_public_ids
  nlb_subnet_ids  = module.vpc.subnet_public_ids
  route53_zone_id = data.aws_route53_zone.example.zone_id

  puppet_hiera_config_path = "/opt/infrahouse-puppet-data/environments/production/hiera.yaml"
  packages = [
    "infrahouse-puppet-data"
  ]
}
```

## Cost-Optimized with Spot Instances

Run the fleet on spot instances. `on_demand_base_capacity` sets how many instances stay
on-demand; `0` means the entire fleet is spot. Because home directories live on EFS and
the NLB replaces unhealthy targets automatically, a spot interruption costs only a brief
reconnect.

```hcl
module "jumphost" {
  source  = "registry.infrahouse.com/infrahouse/jumphost/aws"
  version = "5.0.0"

  environment     = "production"
  subnet_ids      = module.vpc.subnet_public_ids
  nlb_subnet_ids  = module.vpc.subnet_public_ids
  route53_zone_id = data.aws_route53_zone.example.zone_id

  on_demand_base_capacity = 0
}
```

## Internal Jumphost

Place the NLB in private subnets and the module deploys an internal NLB; SSH ingress is
then limited to the VPC CIDR. Useful when the jump host is reached over a VPN or
Direct Connect.

```hcl
module "jumphost" {
  source  = "registry.infrahouse.com/infrahouse/jumphost/aws"
  version = "5.0.0"

  environment     = "production"
  subnet_ids      = module.vpc.subnet_private_ids
  nlb_subnet_ids  = module.vpc.subnet_private_ids
  route53_zone_id = data.aws_route53_zone.internal.zone_id
}
```

## Multiple Jumphosts in One Account

Each deployment needs a unique `efs_creation_token`. Distinct `route53_hostname` values
give each jump host its own DNS name and CloudWatch log group.

```hcl
module "jumphost_prod" {
  source  = "registry.infrahouse.com/infrahouse/jumphost/aws"
  version = "5.0.0"

  environment        = "production"
  efs_creation_token = "jumphost-home-prod"
  route53_hostname   = "jumphost"
  # ... network configuration ...
}

module "jumphost_staging" {
  source  = "registry.infrahouse.com/infrahouse/jumphost/aws"
  version = "5.0.0"

  environment        = "staging"
  efs_creation_token = "jumphost-home-staging"
  route53_hostname   = "jumphost-staging"
  # ... network configuration ...
}
```

## Extra IAM Permissions

Let jump host users run SSM sessions and read a deployment bucket:

```hcl
module "jumphost" {
  source  = "registry.infrahouse.com/infrahouse/jumphost/aws"
  version = "5.0.0"

  # ... network configuration ...

  extra_policies = {
    "ssm-access" = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
    "deploys"    = aws_iam_policy.deploy_bucket_reader.arn
  }
}
```

## Custom KMS Keys and Alerting

Encrypt EFS and CloudWatch logs with customer-managed keys and send CPU alarms to an
SNS topic:

```hcl
module "jumphost" {
  source  = "registry.infrahouse.com/infrahouse/jumphost/aws"
  version = "5.0.0"

  # ... network configuration ...

  efs_kms_key_arn        = aws_kms_key.efs.arn
  cloudwatch_kms_key_arn = aws_kms_key.logs.arn
  log_retention_days     = 731
  sns_topic_alarm_arn    = aws_sns_topic.alarms.arn
}
```

## Custom Puppet Facts and Packages

Pass extra facts to Puppet and install additional tooling at boot:

```hcl
module "jumphost" {
  source  = "registry.infrahouse.com/infrahouse/jumphost/aws"
  version = "5.0.0"

  # ... network configuration ...

  packages = [
    "infrahouse-puppet-data",
    "postgresql-client",
  ]
  puppet_custom_facts = {
    jumphost = {
      team = "platform"
    }
  }
}
```

The module deep-merges your facts with its own `jumphost.cloudwatch_log_group` and
`jumphost.cloudwatch_namespace` facts; your values win on conflicts.
