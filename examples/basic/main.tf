# tflint-ignore: terraform_required_version
# tflint-ignore: terraform_module_version
module "vault" {
  source = "craigsloggett/vault-enterprise-ha/aws"

  project_name      = "vault-ha"
  route53_zone_name = "example.com"
  vault_license     = var.vault_license
  ec2_key_pair_name = "my-key-pair"
}
