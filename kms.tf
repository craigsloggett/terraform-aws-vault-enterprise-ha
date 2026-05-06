resource "aws_kms_key" "auto_unseal" {
  description             = "Vault Enterprise Auto-unseal Key"
  deletion_window_in_days = var.kms_key.deletion_window_in_days
  enable_key_rotation     = var.kms_key.enable_key_rotation

  tags = {
    Name = var.kms_key.name
  }
}

resource "aws_kms_alias" "auto_unseal" {
  name          = "alias/${var.kms_key.alias}"
  target_key_id = aws_kms_key.auto_unseal.key_id
}
