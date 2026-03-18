data "aws_ami" "debian" {
  most_recent = true
  owners      = ["136693071363"]

  filter {
    name   = "name"
    values = ["debian-13-amd64-*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

module "vault" {
  source = "../../"

  project_name        = "vault-ha"
  route53_zone_name   = var.route53_zone_name
  vault_license       = var.vault_license
  ec2_key_pair_name   = var.ec2_key_pair_name
  ec2_instance_ami_id = data.aws_ami.debian.id
}
