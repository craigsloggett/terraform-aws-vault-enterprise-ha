resource "aws_kms_key" "vault" {
  description             = "Vault auto-unseal key"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = merge(var.common_tags, { Name = "${var.project_name}-vault-unseal" })
}

resource "aws_kms_alias" "vault" {
  name          = "alias/${var.project_name}-vault-unseal"
  target_key_id = aws_kms_key.vault.key_id
}
