resource "aws_secretsmanager_secret" "license" {
  name_prefix = var.vault.secretsmanager_secret.license_name_prefix
  description = "Vault Enterprise License"
}

resource "aws_secretsmanager_secret_version" "license" {
  secret_id     = aws_secretsmanager_secret.license.id
  secret_string = var.vault_enterprise_license
}
