# Troubleshooting

Common issues when deploying and operating the jumphost module.

## EFS Creation Token Conflict

**Symptom**: `terraform apply` fails with an error like:

```
CreationTokenInUse: The creation token 'jumphost-home-encrypted' is already in use
```

**Cause**: two deployments in the same AWS account set `efs_creation_token` explicitly
to the same value. Since module version 6.0, a unique token is generated per deployment,
so this only happens with explicit tokens — typically several upgraded deployments all
pinning the old default `jumphost-home-encrypted`.

**Fix**: only the deployment that owns the existing file system should pin its token;
give the others distinct values, or let them generate one by leaving the variable unset
(new file system):

```hcl
efs_creation_token = "jumphost-home-staging"
```

If the conflicting file system is an orphan from a destroyed deployment, delete it in the
EFS console first — check it holds no data you need.

## Instances Never Become Healthy

**Symptom**: the ASG keeps launching and terminating instances; NLB targets stay
`unhealthy`.

**Cause**: the NLB health-checks TCP port 7 (echo), which is configured by Puppet. If
Puppet fails or the echo service isn't set up, health checks never pass.

**Diagnosis**:

1. Connect to an instance directly (EC2 console → instance → Connect, or SSH to its IP
   from inside the VPC).
2. Inspect the cloud-init and Puppet logs:

    ```bash
    sudo tail -100 /var/log/cloud-init-output.log
    ls /var/run/puppet-done   # created only after Puppet succeeds
    ```

3. Verify something listens on port 7: `sudo ss -tlnp | grep :7`.

**Fix**: make sure the instance receives working Puppet code — the simplest setup installs
the `infrahouse-puppet-data` package (see [Getting Started](getting-started.md)). Enable
`puppet_debug_logging = true` for more verbose logs.

## SSH Connection Times Out

**Symptom**: `ssh jumphost.example.com` hangs or times out.

**Checks**:

- **DNS**: `dig jumphost.example.com` — the record is a CNAME to the NLB and uses a
  300-second TTL by default; give a fresh deployment a few minutes.
- **NLB scheme**: if `nlb_subnet_ids` are private subnets, the NLB is internal and only
  reachable from inside the VPC (SSH ingress is limited to the VPC CIDR). Check the
  `map_public_ip_on_launch` attribute of the NLB subnets.
- **Targets**: confirm the target group has healthy targets (see the previous section).

## Host Key Verification Failed

**Symptom**: SSH reports `REMOTE HOST IDENTIFICATION HAS CHANGED`.

**Cause**: the module generates SSH host keys once and shares them across all instances,
so this should *not* happen on routine instance replacement. It does happen when the
jump host was destroyed and recreated (new keys generated), or when `ssh_host_keys` input
changed.

**Fix**: remove the stale entry and reconnect:

```bash
ssh-keygen -R jumphost.example.com
```

To keep a stable identity across full redeployments, pass your own `ssh_host_keys`.

## Home Directory Is Empty or Missing Files

**Symptom**: after logging in, `/home/<user>` doesn't contain expected files.

**Cause**: the EFS file system failed to mount and users see the local root volume's
`/home` instead.

**Diagnosis** on the instance:

```bash
df -h /home        # should show an fs-*.efs.*.amazonaws.com:/ device
sudo mount -a      # try mounting; errors point at the cause
```

**Common causes**:

- EFS mount targets missing in the instance's subnet (they are created per `subnet_ids`)
- Security group changes blocking NFS port 2049
- A recreated file system after `efs_creation_token` changed — the data lived on the old
  file system

## Terraform Wants to Recreate the EFS File System

**Symptom**: `terraform plan` shows `aws_efs_file_system.home-enc` must be replaced.

**Cause**: `efs_creation_token` (or `efs_kms_key_arn`) changed — both force a new file
system.

**Fix**: if the change is unintentional, revert it. If intentional, back up `/home`
first — replacement destroys all data on the old file system.

## Unsupported Ubuntu Codename

**Symptom**: no AMI found, or an error mentioning `ubuntu_codename`.

**Cause**: only Ubuntu `noble` (24.04) is currently supported.

**Fix**: leave `ubuntu_codename` at its default, or pass a specific `ami_id` if you must
run a different image.

## No Logs in CloudWatch

**Symptom**: the log group `/aws/ec2/jumphost/<environment>/<hostname>.<zone>` exists but stays
empty.

**Cause**: the CloudWatch agent on the instances is installed and configured by Puppet.
If Puppet didn't run successfully, the agent isn't shipping logs.

**Diagnosis** on an instance:

```bash
systemctl status amazon-cloudwatch-agent
sudo tail /opt/aws/amazon-cloudwatch-agent/logs/amazon-cloudwatch-agent.log
```

Also verify the instance role kept its CloudWatch permissions if you customized IAM.

## Jumphost Missing from Inspector Findings

**Symptom**: a jumphost never appears in AWS Inspector findings — not "clean", simply absent.

**Cause**: instances launch tagged `InspectorEc2Exclusion` so Inspector does not scan them
before security updates are applied, and Puppet removes the tag once it has patched. If
nothing removes it, the instance stays excluded forever. This fails open, so nothing alerts.

**Diagnosis** — check whether the tag is still on the instance:

```bash
aws ec2 describe-tags --filters Name=resource-id,Values=i-xxxxxxxx Name=key,Values=InspectorEc2Exclusion
```

Empty output is the healthy case. If the tag is still there, look at the instance:

```bash
sudo grep -i InspectorEc2Exclusion /var/log/cloud-init-output.log
```

- `could not remove ... (no ec2:DeleteTags?)` — the instance role lost the `ec2:DeleteTags`
  statement, most likely because IAM was customized. Removal is best effort by design and
  never fails a Puppet run, so this is only ever a log line.
- nothing at all — the Puppet code that removes the tag (`profile::boot_security_upgrade`,
  included by `role::jumphost`) did not run. Check that Puppet completed:
  `ls /var/run/puppet-done`.

**Fix**: restore the permission or the Puppet code, then replace the instance — the tag is
applied at launch, so the next instance goes through the cycle cleanly. To unblock scanning
immediately, delete the tag by hand with `aws ec2 delete-tags`.

## Test Resources Left Behind

**Symptom**: integration tests failed midway and AWS resources linger.

**Fix**: from the repository root:

```bash
make test-clean
```

Terraform state for the test deployment lives in `test_data/jumphost/` — inspect it with
`terraform -chdir=test_data/jumphost state list` when cleanup needs manual help.

## Getting Help

- [Open an issue](https://github.com/infrahouse/terraform-aws-jumphost/issues) with your
  module configuration and Terraform output
- [Contact InfraHouse](https://infrahouse.com/contact) for commercial support
