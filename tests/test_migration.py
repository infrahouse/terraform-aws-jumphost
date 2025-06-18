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

MAIN_TF_BEFORE = """
module "jumphost" {
  source  = "infrahouse/jumphost/aws"
  version = "2.9.0"

  subnet_ids               = var.asg_subnet_ids
  nlb_subnet_ids           = var.nlb_subnet_ids
  environment              = local.environment
  route53_zone_id          = data.aws_route53_zone.cicd.zone_id
  route53_hostname         = local.jumphost_hostname
  keypair_name             = aws_key_pair.rsa.key_name
  asg_min_size             = 1
  asg_max_size             = 1
  instance_type            = "t3a.medium"
  ubuntu_codename          = "jammy"
  puppet_hiera_config_path = "/opt/infrahouse-puppet-data/environments/${local.environment}/hiera.yaml"
  packages = [
    "infrahouse-puppet-data"
  ]
}
"""

MAIN_TF_AFTER = """
module "jumphost" {
  source                   = "../.."

  subnet_ids               = var.asg_subnet_ids
  nlb_subnet_ids           = var.nlb_subnet_ids
  environment              = local.environment
  route53_zone_id          = data.aws_route53_zone.cicd.zone_id
  route53_hostname         = local.jumphost_hostname
  asg_min_size             = 1
  asg_max_size             = 1
  instance_type            = "t3a.medium"
  ubuntu_codename          = "noble"
  puppet_hiera_config_path = "/opt/infrahouse-puppet-data/environments/${local.environment}/hiera.yaml"
  packages = [
    "infrahouse-puppet-data"
  ]
}
"""

def test_module(
    service_network, aws_region, test_zone_name, test_role_arn, keep_after
):
    nlb_subnet_ids = service_network["subnet_private_ids"]["value"]
    subnet_private_ids = service_network["subnet_private_ids"]["value"]

    terraform_module_dir = osp.join(TERRAFORM_ROOT_DIR, "jumphost-2.9")

    with open(osp.join(terraform_module_dir, "terraform.tfvars"), "w") as fp:
        fp.write(
            dedent(
                f"""
                region = "{aws_region}"
                test_zone = "{test_zone_name}"

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

    with open(osp.join(terraform_module_dir, "main.tf"), "w") as fp:
        fp.write(MAIN_TF_BEFORE)


    with terraform_apply(
        terraform_module_dir,
        destroy_after=False,
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
        assert cout.strip() == "jammy"

    with open(osp.join(terraform_module_dir, "main.tf"), "w") as fp:
        fp.write(MAIN_TF_AFTER)


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
        assert cout.strip() == "noble"
