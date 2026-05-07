data "aws_route53_zone" "selected" {
  name = var.route53_zone_name
}

module "vault" {
  # tflint-ignore: terraform_module_pinned_source
  source = "git::https://github.com/craigsloggett/terraform-aws-vault-enterprise"

  vault_enterprise_license = var.vault_enterprise_license
  route53_zone             = data.aws_route53_zone.selected
}
