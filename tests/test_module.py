import json
import time
from os import path as osp
from subprocess import check_output
from textwrap import dedent

import pytest
from pytest_infrahouse import terraform_apply

from tests.conftest import (
    LOG,
    TERRAFORM_ROOT_DIR,
)


@pytest.mark.parametrize(
    "network, codename",
    [("subnet_public_ids", "noble"), ("subnet_private_ids", "noble")],
)
def test_module(
    service_network, network, codename, autoscaling_client, aws_region, test_zone_name, test_role_arn, keep_after
):
    nlb_subnet_ids = service_network[network]["value"]
    subnet_private_ids = service_network["subnet_private_ids"]["value"]

    terraform_module_dir = osp.join(TERRAFORM_ROOT_DIR, "jumphost")

    with open(osp.join(terraform_module_dir, "terraform.tfvars"), "w") as fp:
        fp.write(
            dedent(
                f"""
                region = "{aws_region}"
                test_zone = "{test_zone_name}"
                ubuntu_codename = "{codename}"

                nlb_subnet_ids = {json.dumps(nlb_subnet_ids)}
                asg_subnet_ids = {json.dumps(subnet_private_ids)}
                """
            )
        )
        if test_role_arn:
            fp.write(
                dedent(
                    f"""
                    role_arn      = "{test_role_arn}"
                    """
                )
            )

    with terraform_apply(
        terraform_module_dir,
        destroy_after=not keep_after,
        json_output=True,
    ) as tf_output:

        LOG.info("%s", json.dumps(tf_output, indent=4))
        asg_name = tf_output["asg_name"]["value"]

        if network == "subnet_public_ids":

            LOG.info("Wait until all refreshes are done")

            while True:
                all_done = True
                for refresh in autoscaling_client.describe_instance_refreshes(
                    AutoScalingGroupName=asg_name,
                )["InstanceRefreshes"]:
                    status = refresh["Status"]
                    if status not in [
                        "Successful",
                        "Failed",
                        "Cancelled",
                        "RollbackFailed",
                        "RollbackSuccessful",
                    ]:
                        all_done = False
                if all_done:
                    break
                else:
                    time.sleep(60)
            assert (
                check_output(["ssh", tf_output["jumphost_fqdn"]["value"], "lsb_release -sc"]).decode().strip()
                == codename
            )
