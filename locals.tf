locals {
  ami_id       = var.ami_id == null ? data.aws_ami.ubuntu.id : var.ami_id
  vpc_id       = data.aws_subnet.selected[var.subnet_ids[0]].vpc_id
  nlb_internal = !data.aws_subnet.nlb_selected[var.nlb_subnet_ids[0]].map_public_ip_on_launch
  tags = {
    created_by_module : "infrahouse/jumphost/aws"
  }
}
