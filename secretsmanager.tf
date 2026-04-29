resource "aws_secretsmanager_secret" "vault_enterprise_license" {
  name_prefix = "${var.project_name}-vault-enterprise-license-"
  description = "Vault Enterprise License"
}

resource "aws_secretsmanager_secret_version" "vault_enterprise_license" {
  secret_id     = aws_secretsmanager_secret.vault_enterprise_license.id
  secret_string = var.vault_enterprise_license
}

resource "aws_secretsmanager_secret" "vault_pki_intermediate_ca_signed_csr" {
  name_prefix = "${var.project_name}-vault-pki-intermediate-ca-signed-csr-"
  description = "Vault Intermediate CA Signed CSR and Chain"
}

resource "aws_secretsmanager_secret" "vault_recovery_keys" {
  name_prefix = "${var.project_name}-vault-recovery-keys-"
  description = "Vault Recovery Keys"
}
