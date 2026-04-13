resource "aws_secretsmanager_secret" "vault_license" {
  name_prefix = "${var.project_name}-vault-license-"
  description = "Vault Enterprise license"

  tags = merge(var.common_tags, { Name = "${var.project_name}-vault-license" })
}

resource "aws_secretsmanager_secret_version" "vault_license" {
  secret_id     = aws_secretsmanager_secret.vault_license.id
  secret_string = var.vault_license
}

resource "aws_secretsmanager_secret" "vault_recovery_keys" {
  name_prefix = "${var.project_name}-vault-recovery-keys-"
  description = "Vault recovery keys"

  tags = merge(var.common_tags, { Name = "${var.project_name}-vault-recovery-keys" })
}
