locals {
  ami_id       = var.ami_id == null ? data.aws_ami.ubuntu.id : var.ami_id
  vpc_id       = data.aws_subnet.selected[var.subnet_ids[0]].vpc_id
  nlb_internal = !data.aws_subnet.nlb_selected[var.nlb_subnet_ids[0]].map_public_ip_on_launch
  default_module_tags = {
    environment : var.environment
    service : "jumphost"
    account : data.aws_caller_identity.current.account_id
    created_by_module : "infrahouse/jumphost/aws"

  }
  ami_name_pattern = contains(
    ["focal", "jammy"], var.ubuntu_codename
  ) ? "ubuntu/images/hvm-ssd/ubuntu-${var.ubuntu_codename}-*" : "ubuntu/images/hvm-ssd-gp3/ubuntu-${var.ubuntu_codename}-*"
}
