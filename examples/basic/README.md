# Example - Basic Usage

```hcl
module "vault" {
  source  = "craigsloggett/vault-enterprise-ha/aws"
  version = "x.x.x"

  project_name      = "vault-enterprise"
  route53_zone_name = "example.com"
  vault_license     = var.vault_license
  ec2_key_pair_name = "my-key-pair"
}
```
