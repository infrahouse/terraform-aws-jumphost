# CloudWatch Logging Implementation Plan for terraform-aws-jumphost

## Executive Summary
This plan outlines the implementation of **mandatory** CloudWatch logging capabilities 
for the terraform-aws-jumphost module. CloudWatch logging will be always-on to ensure security compliance 
and proper audit trails for this critical infrastructure component.

## Current State Analysis

### Existing CloudWatch Resources
- ✅ CloudWatch metric alarm for CPU utilization (cloudwatch.tf)
- ❌ No CloudWatch log groups
- ❌ No CloudWatch logging IAM permissions
- ❌ No CloudWatch-related module outputs for log groups

### Existing Module Capabilities
- ✅ Custom facts support via `puppet_custom_facts` variable
- ✅ IAM role management via instance-profile module
- ✅ Extra policies attachment support
- ✅ User data configuration via cloud-init module

## Design Decision: Always-On Logging

### Rationale
CloudWatch logging is mandatory for jumphosts because:
1. **Security requirement**: Jumphosts are security perimeters requiring audit trails
2. **Compliance**: SOC2, ISO27001, PCI-DSS all require logging
3. **Incident response**: Essential for security investigations
4. **Minimal cost**: ~$3/month is negligible for critical infrastructure
5. **Best practice**: Security-by-default principle

## Implementation Tasks

### Phase 1: Core CloudWatch Resources (Priority: High)

#### 1.1 Create CloudWatch Log Group Resource
**File**: Create new `cloudwatch-logs.tf`
```hcl
resource "aws_cloudwatch_log_group" "jumphost" {
  name              = "/aws/ec2/jumphost/${var.environment}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.cloudwatch_kms_key_arn

  tags = merge(
    local.default_module_tags,
    {
      Purpose = "Security and compliance logging"
    }
  )
}
```

#### 1.2 Add CloudWatch Logging IAM Permissions
**File**: Add to `cloudwatch-logs.tf`
```hcl
data "aws_iam_policy_document" "cloudwatch_logs" {
  # Log permissions
  statement {
    sid    = "CloudWatchLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams"
    ]
    resources = [
      aws_cloudwatch_log_group.jumphost.arn,
      "${aws_cloudwatch_log_group.jumphost.arn}:*"
    ]
  }

  # EC2 metadata for CloudWatch agent
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

### Phase 2: Variables and Configuration (Priority: High)

#### 2.1 Add New Module Variables
**File**: Update `variables.tf`
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

### Phase 3: Integration and Outputs (Priority: High)

#### 3.1 Update Main Configuration
**File**: Update `data_sources.tf`
```hcl
# Combine all required permissions
data "aws_iam_policy_document" "combined_permissions" {
  source_policy_documents = [
    data.aws_iam_policy_document.required_permissions.json,
    data.aws_iam_policy_document.cloudwatch_logs.json
  ]
}
```

**File**: Update `main.tf`
```hcl
# Update instance profile to use combined permissions
module "jumphost_profile" {
  source         = "registry.infrahouse.com/infrahouse/instance-profile/aws"
  version        = "1.9.0"
  permissions    = data.aws_iam_policy_document.combined_permissions.json
  profile_name   = "jumphost-${random_string.profile-suffix.result}"
  role_name      = var.instance_role_name
  extra_policies = var.extra_policies
}

# Update user data module with CloudWatch facts
module "jumphost_userdata" {
  source                   = "registry.infrahouse.com/infrahouse/cloud-init/aws"
  version                  = "2.2.2"
  environment              = var.environment
  role                     = "jumphost"
  gzip_userdata            = true
  ubuntu_codename          = var.ubuntu_codename

  # Always include CloudWatch facts
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
  packages                 = concat(var.packages, ["nfs-common"])
  extra_files              = var.extra_files
  extra_repos              = var.extra_repos
  mounts                   = [
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

#### 3.2 Add Module Outputs
**File**: Update `outputs.tf`
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

### Phase 4: Testing (Priority: High)

#### 4.1 Update Test Module
**File**: Update `test_data/jumphost/main.tf`
```hcl
module "jumphost" {
  # ... existing configuration ...

  # CloudWatch configuration for testing
  log_retention_days = 7  # Short retention for testing
}
```

#### 4.2 Add Test Function
**File**: Update `tests/test_module.py`

Add comprehensive CloudWatch verification function at the top of the file:
```python
import time
import uuid

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

Then update the test function to add `boto3_session` parameter and call the verification:
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

### Phase 5: Documentation (Priority: Medium)

#### 5.1 Update README.md
Add new section after the IAM instance profile section:

```markdown
## CloudWatch Logging

The module creates a CloudWatch log group for centralized logging and audit trails. This is a **mandatory** security feature that cannot be disabled.

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
```

#### 5.2 Update CLAUDE.md
Add CloudWatch section:
```markdown
### CloudWatch Integration
- Always-on CloudWatch logging at `/aws/ec2/jumphost/{environment}`
- IAM permissions automatically configured for CloudWatch agent
- Custom facts provided to Puppet for agent configuration
- Default 365-day retention for compliance
```

## Implementation Schedule

### Week 1: Core Implementation
- [ ] Day 1: Create cloudwatch-logs.tf with resources and IAM policies
- [ ] Day 2: Update data_sources.tf and main.tf for permission merging
- [ ] Day 3: Add variables and outputs
- [ ] Day 4: Update test configuration
- [ ] Day 5: Write and run tests

### Week 2: Documentation and Release
- [ ] Day 1-2: Update README.md and CLAUDE.md
- [ ] Day 3: Code review
- [ ] Day 4: Final testing
- [ ] Day 5: Release preparation

## Migration Impact

### For Existing Deployments
This is a **non-breaking but additive** change:
1. CloudWatch log group will be created on next apply
2. IAM permissions will be extended (not replaced)
3. New cost: ~$3/month per jumphost
4. No action required from users

### Version Notes
Document in release notes:
```
Version X.0.0 adds mandatory CloudWatch logging for security compliance.
- Adds CloudWatch log group with configurable retention
- Extends IAM permissions for CloudWatch agent
- Provides facts to Puppet for automatic agent configuration
- Expected additional cost: ~$3/month per jumphost
```

## Success Criteria

1. ✅ CloudWatch log group created automatically
2. ✅ IAM permissions include CloudWatch access
3. ✅ Custom facts available to Puppet
4. ✅ All tests pass
5. ✅ Documentation updated
6. ✅ No breaking changes to existing deployments
7. ✅ Module outputs expose log group information

## Risk Assessment

### Technical Risks
1. **IAM Permission Merge**: Combining permissions might cause conflicts
   - Mitigation: Test with various extra_policies configurations

2. **Puppet Fact Conflicts**: Merging facts might override user settings
   - Mitigation: Merge strategy preserves user facts, jumphost facts are nested

3. **Cost Impact**: Additional ~$3/month per jumphost
   - Mitigation: Document clearly in README, provide retention options

### Operational Risks
1. **Log Volume**: High log volume could exceed expectations
   - Mitigation: Monitor initial usage, document log filtering options

## Post-Implementation Tasks

1. Monitor CloudWatch costs for first month
2. Create CloudWatch dashboard template
3. Document CloudWatch Insights queries
4. Set up sample CloudWatch alarms
5. Create runbook for log analysis

## Notes

- CloudWatch logs are encrypted by default with AWS managed keys
- Custom KMS key support included for enhanced security
- Facts are merged with existing puppet_custom_facts
- No option to disable - security by default

## Approval

This plan requires approval from:
- [ ] Module maintainer
- [ ] Security team (confirms mandatory logging meets requirements)
- [ ] Operations team (for monitoring integration)
- [ ] Puppet team (for facts integration)
