resource "aws_kms_key" "vault" {
  description             = "Vault Enterprise Auto-unseal Key"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = {
    Name = var.kms_key.name
  }
}

resource "aws_kms_alias" "vault" {
  name          = "alias/${var.project_name}-vault-unseal"
  target_key_id = aws_kms_key.vault.key_id
}
