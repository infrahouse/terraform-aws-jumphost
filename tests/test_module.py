import json
from os import path as osp
from pprint import pformat, pprint
from textwrap import dedent
from time import sleep

import pytest
from infrahouse_toolkit.terraform import terraform_apply

from tests.conftest import (
    LOG,
    TRACE_TERRAFORM,
    DESTROY_AFTER,
    TEST_ZONE,
    TEST_ROLE_ARN,
    REGION,
)


@pytest.mark.flaky(reruns=0, reruns_delay=30)
@pytest.mark.timeout(1800)
def test_module(ec2_client, route53_client, autoscaling_client):
    terraform_dir = "test_data/test_module"

    with open(osp.join(terraform_dir, "terraform.tfvars"), "w") as fp:
        fp.write(
            dedent(
                f"""
                region = "{REGION}"
                role_arn = "{TEST_ROLE_ARN}"
                test_zone = "{TEST_ZONE}"
                """
            )
        )

    with terraform_apply(
        terraform_dir,
        destroy_after=DESTROY_AFTER,
        json_output=True,
        enable_trace=TRACE_TERRAFORM,
    ) as tf_output:
        pprint(tf_output)
        asg_name = tf_output["jumphost_asg_name"]["value"]
        LOG.debug("ASG name: %s", asg_name)
        response = autoscaling_client.start_instance_refresh(
            AutoScalingGroupName=asg_name,
            Preferences={
                "InstanceWarmup": 60,
            },
        )
        LOG.debug("Response = %s", pformat(response, indent=4))
        refresh_id = response["InstanceRefreshId"]
        while True:
            response = autoscaling_client.describe_instance_refreshes(
                AutoScalingGroupName=tf_output["jumphost_asg_name"]["value"],
                InstanceRefreshIds=[refresh_id],
            )
            if response["InstanceRefreshes"][0]["Status"] == "Successful":
                break
            else:
                LOG.info("Waiting until ASG refresh %s is done.", refresh_id)
                sleep(60)

        LOG.info(json.dumps(tf_output, indent=4))
        zone_id = tf_output["zone_id"]["value"]
        assert zone_id
        jumphost_hostname = tf_output["jumphost_hostname"]["value"]
        response = route53_client.list_resource_record_sets(HostedZoneId=zone_id)
        a_records = [
            a["Name"] for a in response["ResourceRecordSets"] if a["Type"] == "A"
        ]
        for record in [jumphost_hostname]:
            assert (
                "%s.%s." % (record, TEST_ZONE) in a_records
            ), "Record %s is missing in %s: %s" % (
                record,
                TEST_ZONE,
                pformat(a_records, indent=4),
            )
