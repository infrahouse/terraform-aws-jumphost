import json
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


@pytest.mark.parametrize("aws_provider_version", ["~> 5.31", "~> 6.0"], ids=["aws-5", "aws-6"])
@pytest.mark.parametrize(
    "codename",
    ["noble"],
)
def test_module(
    aws_provider_version, service_network, codename, aws_region, subzone, test_role_arn, keep_after, autoscaling_client
):
    nlb_subnet_ids = service_network["subnet_private_ids"]["value"]
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

    # Update provider version
    with open(f"{terraform_module_dir}/terraform.tf", "w") as fp:
        fp.write(
            f"""
            terraform {{
                required_version = "~> 1.0"
                required_providers {{
                    aws = {{
                      source  = "hashicorp/aws"
                      version = "{aws_provider_version}"
                    }}
                  }}
                }}
            """
        )

    with open(osp.join(terraform_module_dir, "terraform.tfvars"), "w") as fp:
        fp.write(
            dedent(
                f"""
                region = "{aws_region}"
                test_zone_id = "{subzone["subzone_id"]["value"]}"
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

        # Wait for any in-progress instance refreshes to complete
        wait_for_instance_refresh(
            asg_name=asg_name, autoscaling_client=autoscaling_client, timeout=3600, poll_interval=60
        )

        ret_code, cout, _ = asg.instances[0].execute_command("lsb_release -sc")
        assert ret_code == 0
        assert cout.strip() == codename
