provider "aws" {
  region = "ca-central-1"
}

data "aws_ami" "hc_base" {
  most_recent = true
  owners      = ["888995627335"]

  filter {
    name   = "name"
    values = ["hc-base-ubuntu-2404-amd64-*"]
  }
}

# tflint-ignore: terraform_required_version
# tflint-ignore: terraform_module_version
module "vault" {
  source = "../../"

  project_name        = "vault-ha"
  route53_zone_name   = var.route53_zone_name
  vault_license       = var.vault_license
  ec2_key_pair_name   = var.ec2_key_pair_name
  ec2_instance_ami_id = data.aws_ami.hc_base.id
}
