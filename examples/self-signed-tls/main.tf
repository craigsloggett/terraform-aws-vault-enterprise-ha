data "aws_route53_zone" "selected" {
  name = var.route53_zone_name
}

data "aws_ami" "selected" {
  most_recent = true
  owners      = [var.ami_owner]

  filter {
    name   = "name"
    values = [var.ami_name]
  }
}

module "vault" {
  # tflint-ignore: terraform_module_pinned_source
  source = "git::https://github.com/craigsloggett/terraform-aws-vault-enterprise"

  vault_enterprise_license = var.vault_enterprise_license
  route53_zone             = data.aws_route53_zone.selected
  ami                      = data.aws_ami.selected
}
