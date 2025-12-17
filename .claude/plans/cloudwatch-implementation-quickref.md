# CloudWatch Implementation Quick Reference

## Overview
This guide provides the exact code changes needed to implement **mandatory** CloudWatch logging for the jumphost module. CloudWatch logging is always-on for security compliance.

## File Changes Summary

### 1. New File: `cloudwatch-logs.tf`
```hcl
# CloudWatch log group for jumphost logs (always created)
resource "aws_cloudwatch_log_group" "jumphost" {
  name              = "/aws/ec2/jumphost/${var.environment}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.cloudwatch_kms_key_arn

  tags = merge(
    local.default_module_tags,
    {
      purpose = "Security and compliance logging"
    }
  )
}

# IAM policy document for CloudWatch logging permissions
data "aws_iam_policy_document" "cloudwatch_logs" {
  # Permissions for CloudWatch Logs
  statement {
    sid    = "CloudWatchLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams"
    ]
    resources = [
      aws_cloudwatch_log_group.jumphost.arn,
      "${aws_cloudwatch_log_group.jumphost.arn}:*"
    ]
  }

  # EC2 metadata access for CloudWatch agent
  statement {
    sid    = "EC2Metadata"
    effect = "Allow"
    actions = [
      "ec2:DescribeVolumes",
      "ec2:DescribeTags",
      "ec2:DescribeInstances",
      "ec2:DescribeInstanceStatus"
    ]
    resources = ["*"]
  }
}
```

### 2. Update: `variables.tf` (add at end)
```hcl
variable "log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 365

  validation {
    condition = contains([
      0, 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180,
      365, 400, 545, 731, 1827, 2192, 2557, 2922, 3288, 3653
    ], var.log_retention_days)
    error_message = "log_retention_days must be a valid CloudWatch retention period."
  }
}

variable "cloudwatch_kms_key_arn" {
  description = "ARN of KMS key for CloudWatch log encryption (null for AWS managed key)"
  type        = string
  default     = null
}
```

### 3. Update: `data_sources.tf` (add after existing data sources)
```hcl
# Combine all required permissions
data "aws_iam_policy_document" "combined_permissions" {
  source_policy_documents = [
    data.aws_iam_policy_document.required_permissions.json,
    data.aws_iam_policy_document.cloudwatch_logs.json
  ]
}
```

### 4. Update: `main.tf` (modify existing resources)

#### Change the IAM policy resource:
```hcl
resource "aws_iam_policy" "required" {
  policy = data.aws_iam_policy_document.combined_permissions.json  # Changed from required_permissions
  tags   = local.default_module_tags
}
```

#### Change the instance profile module:
```hcl
module "jumphost_profile" {
  source         = "registry.infrahouse.com/infrahouse/instance-profile/aws"
  version        = "1.9.0"
  permissions    = data.aws_iam_policy_document.combined_permissions.json  # Changed from required_permissions
  profile_name   = "jumphost-${random_string.profile-suffix.result}"
  role_name      = var.instance_role_name
  extra_policies = var.extra_policies
}
```

#### Update the userdata module with CloudWatch facts:
```hcl
module "jumphost_userdata" {
  source                   = "registry.infrahouse.com/infrahouse/cloud-init/aws"
  version                  = "2.2.2"
  environment              = var.environment
  role                     = "jumphost"
  gzip_userdata            = true
  ubuntu_codename          = var.ubuntu_codename

  # Always include CloudWatch facts merged with user facts
  custom_facts = merge(
    var.puppet_custom_facts,
    {
      jumphost = {
        environment          = var.environment
        role                 = "jumphost"
        cloudwatch_log_group = aws_cloudwatch_log_group.jumphost.name
      }
    }
  )

  puppet_debug_logging     = var.puppet_debug_logging
  puppet_environmentpath   = var.puppet_environmentpath
  puppet_hiera_config_path = var.puppet_hiera_config_path
  puppet_module_path       = var.puppet_module_path
  puppet_root_directory    = var.puppet_root_directory
  puppet_manifest          = var.puppet_manifest

  packages = concat(
    var.packages,
    ["nfs-common"]
  )

  extra_files = var.extra_files
  extra_repos = var.extra_repos

  mounts = [
    [
      "${aws_efs_file_system.home-enc.dns_name}:/",
      "/home",
      "nfs4",
      "nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport,_netdev",
      "0",
      "0"
    ]
  ]

  ssh_host_keys = var.ssh_host_keys == null ? [
    {
      type : "rsa"
      private : tls_private_key.rsa.private_key_openssh
      public : tls_private_key.rsa.public_key_openssh
    },
    {
      type : "ecdsa"
      private : tls_private_key.ecdsa.private_key_openssh
      public : tls_private_key.ecdsa.public_key_openssh
    },
    {
      type : "ed25519"
      private : tls_private_key.ed25519.private_key_openssh
      public : tls_private_key.ed25519.public_key_openssh
    }
  ] : var.ssh_host_keys
}
```

### 5. Update: `outputs.tf` (add at end)
```hcl
output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for jumphost logs"
  value       = aws_cloudwatch_log_group.jumphost.name
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch log group for jumphost logs"
  value       = aws_cloudwatch_log_group.jumphost.arn
}
```

### 6. Update: `test_data/jumphost/main.tf`
Add these parameters to the module call:
```hcl
module "jumphost" {
  source = "../.."
  # ... existing configuration ...

  # CloudWatch configuration for testing
  log_retention_days = 7  # Short retention for testing
}
```

### 7. Update: `tests/test_module.py`

Add imports at the top of the file:
```python
import time
import uuid
```

Add comprehensive verification function:
```python
def verify_cloudwatch_logging(asg, boto3_session, aws_region):
    """
    Verify CloudWatch logging end-to-end integration for jumphost instances.

    Validates:
    1. CloudWatch log group is configured via Puppet facts
    2. CloudWatch agent service is running (managed by Puppet)
    3. CloudWatch Log Group exists in AWS
    4. End-to-end: logs written on instance appear in CloudWatch

    Note: CloudWatch agent package, configuration, and service management
    are Puppet's responsibility. Terraform only tests the end result.
    """
    LOG.info("Testing CloudWatch logging end-to-end integration...")

    # Get an instance from the ASG
    instances = list(asg.instances)
    assert len(instances) > 0, "No instances found in ASG"

    instance = instances[0]
    LOG.info("Testing CloudWatch logging on instance: %s", instance.instance_id)

    # 0. Wait for Puppet to complete (marked by /var/run/puppet-done)
    LOG.info("0. Waiting for Puppet to complete bootstrap (up to 10 minutes)...")
    max_wait = 600  # 10 minutes
    poll_interval = 10
    puppet_done = False

    for attempt in range(max_wait // poll_interval):
        exit_code, stdout, stderr = instance.execute_command(
            "test -f /var/run/puppet-done && echo 'done' || echo 'not done'"
        )

        if exit_code == 0 and stdout.strip() == "done":
            puppet_done = True
            LOG.info(f"✓ Puppet bootstrap completed (after {(attempt + 1) * poll_interval} seconds)")
            break

        LOG.info(f"   Puppet still running (attempt {attempt + 1}/{max_wait // poll_interval})...")
        time.sleep(poll_interval)

    assert puppet_done, (
        f"Puppet bootstrap did not complete after {max_wait} seconds. "
        f"Marker file /var/run/puppet-done not found."
    )

    # 1. Verify CloudWatch log group is in Puppet facts
    LOG.info("1. Checking Puppet facts for CloudWatch log group...")
    exit_code, stdout, stderr = instance.execute_command(
        "sudo facter -p jumphost.cloudwatch_log_group"
    )
    log_group_name = stdout.strip()
    assert log_group_name, f"CloudWatch log group not found in Puppet facts. stderr: {stderr}"
    assert log_group_name.startswith("/aws/ec2/jumphost/"), f"Invalid log group name format: {log_group_name}"
    LOG.info("✓ CloudWatch log group in Puppet facts: %s", log_group_name)

    # 2. Verify CloudWatch agent service is running
    LOG.info("2. Verifying CloudWatch agent service is running...")
    exit_code, stdout, stderr = instance.execute_command(
        "systemctl is-active amazon-cloudwatch-agent"
    )
    assert exit_code == 0 and stdout.strip() == "active", (
        f"CloudWatch agent service not running. Status: {stdout.strip()}. stderr: {stderr}"
    )
    LOG.info("✓ CloudWatch agent service is active")

    # 3. Verify CloudWatch Log Group exists in AWS
    LOG.info("3. Verifying CloudWatch Log Group exists in AWS...")
    logs_client = boto3_session.client("logs", region_name=aws_region)

    try:
        response = logs_client.describe_log_groups(
            logGroupNamePrefix=log_group_name, limit=1
        )
        log_groups = response.get("logGroups", [])
        assert len(log_groups) > 0, f"Log group {log_group_name} not found in CloudWatch"

        log_group = log_groups[0]
        assert log_group["logGroupName"] == log_group_name, (
            f"Log group name mismatch: {log_group['logGroupName']} != {log_group_name}"
        )

        LOG.info("✓ CloudWatch Log Group exists: %s", log_group_name)

        # Check retention and encryption
        if "kmsKeyId" in log_group:
            LOG.info("  KMS Key: %s", log_group["kmsKeyId"])
        else:
            LOG.info("  Encryption: Default server-side encryption")

        LOG.info("  Retention: %s days", log_group.get("retentionInDays", "Never expire"))

    except Exception as e:
        pytest.fail(f"Failed to verify CloudWatch Log Group: {e}")

    # 4. Verify end-to-end logging
    LOG.info("4. Verifying end-to-end CloudWatch Logs integration...")

    # Generate unique test message
    test_message = f"JUMPHOST_TEST_LOG_{uuid.uuid4().hex}"
    log_stream_name = f"{instance.instance_id}/auth.log"

    # Write test message to auth.log
    LOG.info("  Writing test message to /var/log/auth.log...")
    exit_code, stdout, stderr = instance.execute_command(
        f'echo "{test_message}" | sudo tee -a /var/log/auth.log'
    )
    assert exit_code == 0, f"Failed to write test message. stderr: {stderr}"

    # Wait for log to appear in CloudWatch
    LOG.info("  Waiting for log to appear in CloudWatch (up to 60 seconds)...")
    max_wait = 60
    poll_interval = 5
    message_found = False

    for attempt in range(max_wait // poll_interval):
        time.sleep(poll_interval)

        try:
            response = logs_client.get_log_events(
                logGroupName=log_group_name,
                logStreamName=log_stream_name,
                limit=100,
                startFromHead=False,
            )

            for event in response.get("events", []):
                if test_message in event.get("message", ""):
                    message_found = True
                    LOG.info(f"  ✓ Test message found in CloudWatch after {(attempt + 1) * poll_interval} seconds")
                    break

            if message_found:
                break

        except logs_client.exceptions.ResourceNotFoundException:
            LOG.info(f"  Log stream not found yet (attempt {attempt + 1}/{max_wait // poll_interval})...")
            continue

    assert message_found, (
        f"Test message not found in CloudWatch Logs after {max_wait} seconds. "
        f"Log group: {log_group_name}, Log stream: {log_stream_name}"
    )

    LOG.info("✓ End-to-end CloudWatch Logs integration verified")
    LOG.info("✅ All CloudWatch logging tests passed!")
```

Update the test_module function signature to include boto3_session and call the verification:
```python
def test_module(
    aws_provider_version, service_network, codename, aws_region, subzone,
    test_role_arn, keep_after, autoscaling_client, boto3_session
):
    # ... existing test code ...

    with terraform_apply(
        terraform_module_dir,
        destroy_after=not keep_after,
        json_output=True,
    ) as tf_output:
        LOG.info("%s", json.dumps(tf_output, indent=4))
        asg_name = tf_output["asg_name"]["value"]
        asg = ASG(asg_name, region=aws_region, role_arn=test_role_arn)

        # Wait for any in-progress instance refreshes to complete
        wait_for_instance_refresh(
            asg_name=asg_name,
            autoscaling_client=autoscaling_client,
            timeout=3600,
            poll_interval=60
        )

        # Test CloudWatch Logging Configuration
        verify_cloudwatch_logging(
            asg=asg,
            boto3_session=boto3_session,
            aws_region=aws_region,
        )

        # Test Ubuntu codename
        ret_code, cout, _ = asg.instances[0].execute_command("lsb_release -sc")
        assert ret_code == 0
        assert cout.strip() == codename
```

## Implementation Checklist

### Before Starting
- [ ] Create a feature branch
- [ ] Review current `main.tf` and `data_sources.tf` structure

### Implementation Steps
1. [ ] Create `cloudwatch-logs.tf` with log group and IAM policy
2. [ ] Add two new variables to `variables.tf`
3. [ ] Add `combined_permissions` data source to `data_sources.tf`
4. [ ] Update `aws_iam_policy.required` to use combined permissions
5. [ ] Update `module.jumphost_profile` to use combined permissions
6. [ ] Update `module.jumphost_userdata` with CloudWatch facts
7. [ ] Add two new outputs to `outputs.tf`
8. [ ] Update test configuration in `test_data/jumphost/main.tf`
9. [ ] Add test function to `tests/test_module.py`

### Testing
- [ ] Run `terraform fmt -recursive`
- [ ] Run `terraform validate` in test_data/jumphost
- [ ] Run `make test TEST_FILTER=""` to test all scenarios
- [ ] Verify IAM permissions are correctly merged
- [ ] SSH to test instance and verify facts: `sudo facter -p jumphost`

### Documentation
- [ ] Update README.md with CloudWatch section
- [ ] Update CLAUDE.md with CloudWatch details
- [ ] Create release notes highlighting new mandatory logging

## Verification Commands

After deployment, SSH to jumphost and run:
```bash
# Check custom facts
sudo facter -p jumphost
# Expected output:
# {
#   "cloudwatch_log_group": "/aws/ec2/jumphost/development",
#   "environment": "development",
#   "role": "jumphost"
# }

# Verify IAM permissions
aws sts get-caller-identity
aws logs describe-log-groups --log-group-name-prefix "/aws/ec2/jumphost"
```

## Migration Notes

### For Existing Deployments
- CloudWatch log group will be created on next `terraform apply`
- IAM permissions will be extended (not replaced)
- No user action required
- Cost impact: ~$3/month per jumphost

### Rollback (Emergency Only)
If critical issues arise:
1. Remove `cloudwatch-logs.tf`
2. Revert changes in `main.tf`, `data_sources.tf`, `outputs.tf`
3. Run `terraform apply` to remove CloudWatch resources
4. Note: This would violate security compliance requirements

## Cost Breakdown
- **Log Ingestion**: $0.50 per GB
- **Log Storage**: $0.03 per GB per month
- **Typical Usage**: 5GB/month = $2.50 ingestion + $0.15 storage
- **Total**: ~$3/month per jumphost

## Security Notes
- Logs are encrypted by default with AWS managed keys
- Custom KMS key can be specified via `cloudwatch_kms_key_arn`
- Log retention defaults to 365 days for compliance
- No option to disable - this is intentional for security