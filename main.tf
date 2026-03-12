data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_region" "current" {}

data "aws_route53_zone" "vault" {
  name = var.route53_zone_name
}

data "aws_ami" "debian" {
  most_recent = true
  owners      = ["136693071363"]

  filter {
    name   = "name"
    values = [var.ec2_instance_ami_name]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

locals {
  vault_fqdn       = "${var.vault_subdomain}.${data.aws_route53_zone.vault.name}"
  vault_node_count = 3
  azs              = slice(data.aws_availability_zones.available.names, 0, 3)
}
