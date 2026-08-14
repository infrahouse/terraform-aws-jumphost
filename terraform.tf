terraform {
  # removed blocks with lifecycle.destroy require Terraform 1.7
  required_version = ">= 1.7"

  //noinspection HILUnresolvedReference
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0, < 7.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.5"
    }
    tls = {
      source  = "hashicorp/tls"
      version = ">= 4.0"
    }
  }
}
