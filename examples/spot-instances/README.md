# Spot Instances Example

A cost-optimized jumphost running entirely on spot instances.

Setting `on_demand_base_capacity` switches the Auto Scaling Group to a mixed instances
policy: that many instances stay on-demand, and the rest of the fleet runs on spot
capacity. With `0`, the entire fleet is spot — typically a 60–90% saving over on-demand
pricing.

This works well for a jumphost because:

- Home directories live on EFS, so no user data is lost when a spot instance is reclaimed
- The NLB health checks replace an interrupted instance automatically
- SSH host keys are shared across instances, so reconnecting is seamless

The trade-off: an active SSH session on a reclaimed instance is dropped and the user must
reconnect. Keep `on_demand_base_capacity = 1` or higher if that is unacceptable.

## Usage

```bash
terraform init
terraform plan
terraform apply
```

## Outputs

| Name | Description |
|------|-------------|
| jumphost_hostname | DNS name to SSH to |
| jumphost_asg_name | Auto Scaling Group name |

## Notes

- The Route53 zone created in this example uses `example.com`. Replace it with your
  actual domain.
- See the [basic example](../basic) for a walk-through of the common configuration.
