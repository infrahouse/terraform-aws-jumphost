import json
import time
import uuid
from os import path as osp, remove
from shutil import rmtree
from textwrap import dedent

import pytest
from infrahouse_core.aws.asg import ASG
from pytest_infrahouse import terraform_apply
from pytest_infrahouse.utils import wait_for_instance_refresh

from tests.conftest import (
    LOG,
    TERRAFORM_ROOT_DIR,
)


def verify_cloudwatch_logging(instance, boto3_session, aws_region):
    """
    Verify CloudWatch logging end-to-end integration for jumphost instances.

    Validates:
    1. CloudWatch log group is configured via Puppet facts
    2. CloudWatch agent service is running (managed by Puppet)
    3. CloudWatch Log Group exists in AWS
    4. End-to-end: logs written on instance appear in CloudWatch

    Note: CloudWatch agent package, configuration, and service management
    are Puppet's responsibility. Terraform only tests the end result.

    Assumes the instance finished bootstrapping (see EC2Instance.wait_for_bootstrap).
    """
    LOG.info("Testing CloudWatch logging end-to-end integration on %s...", instance.instance_id)

    # 1. Verify CloudWatch log group is in Puppet facts
    LOG.info("1. Checking Puppet facts for CloudWatch log group...")
    exit_code, stdout, stderr = instance.execute_command("sudo facter -p jumphost.cloudwatch_log_group")
    log_group_name = stdout.strip()
    assert log_group_name, f"CloudWatch log group not found in Puppet facts. stderr: {stderr}"
    assert log_group_name.startswith("/aws/ec2/jumphost/"), f"Invalid log group name format: {log_group_name}"
    LOG.info("✓ CloudWatch log group in Puppet facts: %s", log_group_name)

    # 2. Verify CloudWatch agent service is running
    LOG.info("2. Verifying CloudWatch agent service is running...")
    exit_code, stdout, stderr = instance.execute_command("systemctl is-active amazon-cloudwatch-agent")
    assert (
        exit_code == 0 and stdout.strip() == "active"
    ), f"CloudWatch agent service not running. Status: {stdout.strip()}. stderr: {stderr}"
    LOG.info("✓ CloudWatch agent service is active")

    # 3. Verify CloudWatch Log Group exists in AWS
    LOG.info("3. Verifying CloudWatch Log Group exists in AWS...")
    logs_client = boto3_session.client("logs", region_name=aws_region)

    try:
        response = logs_client.describe_log_groups(logGroupNamePrefix=log_group_name, limit=1)
        log_groups = response.get("logGroups", [])
        assert len(log_groups) > 0, f"Log group {log_group_name} not found in CloudWatch"

        log_group = log_groups[0]
        assert (
            log_group["logGroupName"] == log_group_name
        ), f"Log group name mismatch: {log_group['logGroupName']} != {log_group_name}"

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
    log_stream_name = f"{instance.instance_id}/auth/ssh"

    # Write test message to auth.log
    LOG.info("  Writing test message to /var/log/auth.log...")
    exit_code, stdout, stderr = instance.execute_command(f'echo "{test_message}" | sudo tee -a /var/log/auth.log')
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


def verify_inspector_exclusion_tag_removed(asg, instance):
    """
    Verify the Inspector exclusion tag lifecycle.

    The ASG tags instances with InspectorEc2Exclusion at launch and
    profile::boot_security_upgrade removes it once security updates are applied.

    Both halves matter: without the ASG assertion, "the tag is gone" also passes
    on a module that never tags at all.

    Assumes the instance finished bootstrapping (see EC2Instance.wait_for_bootstrap).
    """
    LOG.info("Verifying the Inspector exclusion tag lifecycle...")

    # 1. The ASG still asks for the tag at launch
    assert (
        "InspectorEc2Exclusion" in asg.launch_tags
    ), f"ASG does not propagate InspectorEc2Exclusion at launch. Launch tags: {sorted(asg.launch_tags)}"
    LOG.info("✓ ASG propagates InspectorEc2Exclusion at launch")

    # 2. Puppet removed it from the running instance. EC2 tag reads are eventually
    #    consistent and EC2Instance caches its describe call for 10 seconds, so poll
    #    on a longer interval than that TTL rather than asserting once.
    max_wait = 60
    poll_interval = 15

    for _ in range(max_wait // poll_interval):
        if "InspectorEc2Exclusion" not in instance.tags:
            LOG.info("✓ InspectorEc2Exclusion removed from %s", instance.instance_id)
            return
        time.sleep(poll_interval)

    # Still tagged. The likely cause is a missing or mis-scoped ec2:DeleteTags
    # statement -- boot-security-upgrade.sh logs that case and exits 0.
    _, cout, cerr = instance.execute_command(
        "sudo grep -i InspectorEc2Exclusion /var/log/cloud-init-output.log",
        execution_timeout=120,
    )
    pytest.fail(
        f"InspectorEc2Exclusion still present on {instance.instance_id} {max_wait} seconds after "
        f"the instance bootstrapped -- it would be invisible to Inspector forever. "
        f"Check the ec2:DeleteTags statement in data_sources.tf.\n"
        f"----- cloud-init-output.log -----\n{cout}{cerr}"
    )


@pytest.mark.parametrize("aws_provider_version", ["~> 6.0"], ids=["aws-6"])
@pytest.mark.parametrize(
    "codename",
    ["noble"],
)
def test_module(
    aws_provider_version,
    service_network,
    codename,
    aws_region,
    subzone,
    test_role_arn,
    keep_after,
    autoscaling_client,
    boto3_session,
):
    nlb_subnet_ids = service_network["subnet_public_ids"]["value"]
    subnet_private_ids = service_network["subnet_private_ids"]["value"]

    terraform_module_dir = osp.join(TERRAFORM_ROOT_DIR, "jumphost")

    # Delete .terraform directory and .terraform.lock.hcl to allow provider version changes
    terraform_dir_path = osp.join(terraform_module_dir, ".terraform")
    lock_file_path = osp.join(terraform_module_dir, ".terraform.lock.hcl")

    try:
        rmtree(terraform_dir_path)
    except FileNotFoundError:
        pass

    try:
        remove(lock_file_path)
    except FileNotFoundError:
        pass

    # Update provider version. Written terraform-fmt clean: `make lint` and the
    # pre-commit hook run `terraform fmt -recursive`, which does not skip generated
    # or gitignored files.
    with open(f"{terraform_module_dir}/terraform.tf", "w") as fp:
        fp.write(dedent(f"""
                terraform {{
                  required_version = "~> 1.0"
                  required_providers {{
                    aws = {{
                      source  = "hashicorp/aws"
                      version = "{aws_provider_version}"
                    }}
                  }}
                }}
                """))

    with open(osp.join(terraform_module_dir, "terraform.tfvars"), "w") as fp:
        fp.write(dedent(f"""
                region          = "{aws_region}"
                test_zone_id    = "{subzone["subzone_id"]["value"]}"
                ubuntu_codename = "{codename}"

                nlb_subnet_ids = {json.dumps(nlb_subnet_ids)}
                asg_subnet_ids = {json.dumps(subnet_private_ids)}
                """))
        if test_role_arn:
            fp.write(dedent(f"""
                    role_arn = "{test_role_arn}"
                    """))

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
            asg_name=asg_name, autoscaling_client=autoscaling_client, timeout=3600, poll_interval=60
        )

        instances = list(asg.instances)
        assert len(instances) > 0, "No instances found in ASG"
        instance = instances[0]

        # Every check below needs a converged instance. cloud-init reports `done`
        # only after ih-bootstrap - and therefore `ih-puppet apply` - succeeded,
        # and raises with cloud-init diagnostics when it did not.
        instance.wait_for_bootstrap()

        # Verify CloudWatch log group fact is passed to Puppet
        LOG.info("Verifying CloudWatch log group in Puppet facts...")
        ret_code, cout, cerr = instance.execute_command(
            "bash -lc 'facter -p jumphost.cloudwatch_log_group'", execution_timeout=300
        )
        expected_log_group = tf_output["cloudwatch_log_group_name"]["value"]
        assert ret_code == 0, f"Failed to get Puppet fact. stderr: {cerr}"
        assert expected_log_group in cout, f"Expected log group {expected_log_group} not found in Puppet facts: {cout}"
        LOG.info(f"✓ CloudWatch log group fact verified: {expected_log_group}")

        # Test CloudWatch Logging Configuration
        verify_cloudwatch_logging(
            instance=instance,
            boto3_session=boto3_session,
            aws_region=aws_region,
        )

        # Inspector exclusion tag: applied at launch, removed once Puppet patched
        verify_inspector_exclusion_tag_removed(asg=asg, instance=instance)

        ret_code, cout, _ = instance.execute_command("lsb_release -sc")
        assert ret_code == 0
        assert cout.strip() == codename
