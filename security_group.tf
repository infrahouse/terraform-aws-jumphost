resource "aws_security_group" "jumphost" {
  vpc_id      = data.aws_subnet.selected.vpc_id
  name_prefix = "jumphost"
  description = "Manage traffic to jumphost"
  tags = merge({
    Name : "jumphost"
    },
    local.tags
  )
}

resource "aws_vpc_security_group_ingress_rule" "ssh" {
  description       = "Allow SSH traffic"
  security_group_id = aws_security_group.jumphost.id
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"
  tags = merge({
    Name = "SSH access"
    },
    local.tags
  )
}

resource "aws_vpc_security_group_ingress_rule" "echo" {
  description       = "Allow NLB healthchecks"
  security_group_id = aws_security_group.jumphost.id
  from_port         = 7
  to_port           = 7
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"
  tags = merge(
    {
      Name = "Echo access"
    },
    local.tags
  )
}

resource "aws_vpc_security_group_ingress_rule" "icmp" {
  description       = "Allow all ICMP traffic"
  security_group_id = aws_security_group.jumphost.id
  from_port         = -1
  to_port           = -1
  ip_protocol       = "icmp"
  cidr_ipv4         = "0.0.0.0/0"
  tags = merge(
    {
      Name = "ICMP traffic"
    },
    local.tags
  )
}

resource "aws_vpc_security_group_egress_rule" "default" {
  description       = "Allow all traffic"
  security_group_id = aws_security_group.jumphost.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
  tags = merge(
    {
      Name = "outgoing traffic"
    },
    local.tags
  )
}
