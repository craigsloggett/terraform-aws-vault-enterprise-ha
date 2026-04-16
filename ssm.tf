resource "aws_ssm_parameter" "vault_tls_ca_bundle" {
  name        = "/${var.project_name}/vault/tls/ca-bundle"
  type        = "String"
  value       = "EMPTY"
  description = "Vault PKI Managed TLS CA Bundle"

  lifecycle {
    ignore_changes = [value]
  }

  tags = merge(var.common_tags, { Name = "${var.project_name}-vault-tls-ca-bundle" })
}
