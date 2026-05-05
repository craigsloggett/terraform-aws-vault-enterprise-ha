resource "aws_ssm_parameter" "tls_ca_bundle" {
  name        = var.vault_pki.ssm_parameter.tls_ca_bundle_name
  type        = "String"
  value       = "EMPTY"
  description = "Vault PKI Managed TLS CA Bundle"

  lifecycle {
    ignore_changes = [value]
  }
}
