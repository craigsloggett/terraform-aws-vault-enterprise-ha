resource "aws_secretsmanager_secret" "vault_enterprise_license" {
  name_prefix = "${var.project_name}-vault-enterprise-license-"
  description = "Vault Enterprise License"

  tags = merge(var.common_tags, { Name = "${var.project_name}-vault-enterprise-license" })
}

resource "aws_secretsmanager_secret_version" "vault_enterprise_license" {
  secret_id     = aws_secretsmanager_secret.vault_enterprise_license.id
  secret_string = var.vault_enterprise_license
}

resource "aws_secretsmanager_secret" "vault_pki_intermediate_ca_signed_csr" {
  name_prefix = "${var.project_name}-vault-pki-intermediate-ca-signed-csr-"
  description = "Signed Vault Intermediate CA Certificate and Chain"

  tags = merge(var.common_tags, { Name = "${var.project_name}-vault-pki-intermediate-ca-signed-csr" })
}

resource "aws_secretsmanager_secret" "vault_recovery_keys" {
  name_prefix = "${var.project_name}-vault-recovery-keys-"
  description = "Vault Recovery Keys"

  tags = merge(var.common_tags, { Name = "${var.project_name}-vault-recovery-keys" })
}
