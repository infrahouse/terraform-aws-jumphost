variable "role_arn" {
  default = null
}
variable "alarm_emails" {
  type    = list(string)
  default = ["devnull@infrahouse.com"]
}
variable "test_zone_id" {}
variable "region" {}

variable "nlb_subnet_ids" {}
variable "asg_subnet_ids" {}
variable "ubuntu_codename" {}
