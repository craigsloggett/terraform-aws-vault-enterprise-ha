data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

data "aws_route53_zone" "vault" {
  name = var.route53_zone_name
}

data "aws_ami" "selected" {
  filter {
    name   = "image-id"
    values = [var.ec2_instance_ami_id]
  }
}

locals {
  vault_fqdn        = "${var.vault_subdomain}.${data.aws_route53_zone.vault.name}"
  vault_node_count  = 3
  azs               = slice(data.aws_availability_zones.available.names, 0, 3)
  cluster_tag_key   = "vault-cluster"
  cluster_tag_value = var.project_name
  ebs_device_name   = "/dev/xvdf" # AWS convention for the first additional EBS volume
}
