resource "aws_secretsmanager_secret" "license" {
  name_prefix = var.vault.secretsmanager_secret.license_name_prefix
  description = "Vault Enterprise License"
}

resource "aws_secretsmanager_secret_version" "license" {
  secret_id     = aws_secretsmanager_secret.license.id
  secret_string = var.vault_enterprise_license
}

resource "aws_secretsmanager_secret" "recovery_keys" {
  name_prefix = var.vault.secretsmanager_secret.recovery_keys_name_prefix
  description = "Vault Enterprise Recovery Keys"
}

resource "aws_secretsmanager_secret" "root_token" {
  name_prefix = var.vault.secretsmanager_secret.root_token_name_prefix
  description = "Vault Enterprise Root Token"
}

resource "aws_secretsmanager_secret" "vault_pki_signed_intermediate_ca" {
  name_prefix = var.vault_pki.secretsmanager_secret.signed_intermediate_ca_name_prefix
  description = "Vault Enterprise Signed Intermediate CA"
}
