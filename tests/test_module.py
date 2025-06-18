import json
import time
from os import path as osp
from textwrap import dedent

import pytest
from infrahouse_core.aws.asg import ASG
from pytest_infrahouse import terraform_apply

from tests.conftest import (
    LOG,
    TERRAFORM_ROOT_DIR,
)


@pytest.mark.parametrize(
    "network, codename",
    [("subnet_public_ids", "noble"), ("subnet_private_ids", "noble")],
)
def test_module(service_network, network, codename, aws_region, test_zone_name, test_role_arn, keep_after):
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
        asg = ASG(asg_name, region=aws_region, role_arn=test_role_arn)

        LOG.info("Wait until all refreshes are done")

        while True:
            all_done = True
            for refresh in asg.instance_refreshes:
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

        ret_code, cout, _ = asg.instances[0].execute_command("lsb_release -sc")
        assert ret_code == 0
        assert cout.strip() == codename
