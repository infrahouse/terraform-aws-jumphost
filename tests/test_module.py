import json
from os import path as osp
from textwrap import dedent

import pytest
from infrahouse_toolkit.terraform import terraform_apply

from tests.conftest import (
    DESTROY_AFTER,
    LOG,
    REGION,
    TERRAFORM_ROOT_DIR,
    TEST_ROLE_ARN,
    TEST_ZONE,
    TRACE_TERRAFORM,
)


@pytest.mark.parametrize("network", ["subnet_public_ids", "subnet_private_ids"])
def test_module(service_network, ec2_client, route53_client, autoscaling_client, network):
    nlb_subnet_ids = service_network[network]["value"]
    subnet_private_ids = service_network["subnet_private_ids"]["value"]
    internet_gateway_id = service_network["internet_gateway_id"]["value"]

    terraform_module_dir = osp.join(TERRAFORM_ROOT_DIR, "jumphost")

    with open(osp.join(terraform_module_dir, "terraform.tfvars"), "w") as fp:
        fp.write(
            dedent(
                f"""
                region = "{REGION}"
                role_arn = "{TEST_ROLE_ARN}"
                test_zone = "{TEST_ZONE}"

                nlb_subnet_ids = {json.dumps(nlb_subnet_ids)}
                asg_subnet_ids = {json.dumps(subnet_private_ids)}
                internet_gateway_id = "{internet_gateway_id}"
                """
            )
        )

    with terraform_apply(
        terraform_module_dir,
        destroy_after=DESTROY_AFTER,
        json_output=True,
        enable_trace=TRACE_TERRAFORM,
    ) as tf_output:
        LOG.info("%s", json.dumps(tf_output, indent=4))
