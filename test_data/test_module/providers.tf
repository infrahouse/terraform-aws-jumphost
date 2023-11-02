provider "aws" {
  assume_role {
    role_arn = var.role_arn
  }
  default_tags {
    tags = {
      "created_by" : "infrahouse/terraform-aws-jumphost" # GitHub repository that created a resource
    }

  }
}