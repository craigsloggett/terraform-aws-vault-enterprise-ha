data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  vault_fqdn        = "${var.vault_subdomain}.${var.route53_zone.name}"
  vault_node_count  = 3
  azs               = slice(data.aws_availability_zones.available.names, 0, 3)
  cluster_tag_key   = "vault-cluster"
  cluster_tag_value = var.project_name
  ebs_device_name   = "/dev/xvdf" # AWS convention for the first additional EBS volume
}
