resource "aws_ssm_parameter" "vault_pki_ca_chain" {
  name        = var.vault_pki.ssm_parameter.ca_chain_name
  type        = "String"
  value       = "EMPTY"
  description = "Vault PKI CA Chain PEM"

  lifecycle {
    ignore_changes = [value]
  }
}

resource "aws_ssm_parameter" "vault_pki_intermediate_ca_csr" {
  name        = var.vault_pki.ssm_parameter.intermediate_ca_csr_name
  type        = "String"
  value       = "Uninitialized"
  description = "Vault PKI Intermediate CA CSR"

  lifecycle {
    ignore_changes = [value]
  }
}
