resource "random_pet" "hostname" {}

locals {
  jumphost_hostname = "jumphost-${random_pet.hostname.id}"
  environment       = "development"
}

resource "tls_private_key" "rsa" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "rsa" {
  public_key = tls_private_key.rsa.public_key_openssh
}
