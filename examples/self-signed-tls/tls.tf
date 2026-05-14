# TLS Signing Orchestration

## Root CA

resource "tls_private_key" "root_ca" {
  algorithm   = "ECDSA"
  ecdsa_curve = "P384"
}

resource "tls_self_signed_cert" "root_ca" {
  private_key_pem = tls_private_key.root_ca.private_key_pem

  subject {
    common_name  = "Vault Root CA"
    country      = "US"
    organization = "HashiCorp Demos"
  }

  validity_period_hours = 87600
  is_ca_certificate     = true

  allowed_uses = [
    "cert_signing",
    "crl_signing",
  ]
}

## Intermediate CA Signing

data "aws_region" "this" {}

resource "terraform_data" "wait_for_csr" {
  input = module.vault.vault_pki_intermediate_ca_csr_ssm_parameter_name

  provisioner "local-exec" {
    command = "${path.module}/files/wait-for-csr.sh"
    environment = {
      PARAMETER_NAME = self.input
      TIMEOUT_SEC    = "1800"
      REGION         = data.aws_region.this.region
    }
  }
}

data "aws_ssm_parameter" "vault_pki_intermediate_ca_csr" {
  name = module.vault.vault_pki_intermediate_ca_csr_ssm_parameter_name

  depends_on = [terraform_data.wait_for_csr]
}

resource "tls_locally_signed_cert" "vault_pki_signed_intermediate_ca" {
  cert_request_pem   = data.aws_ssm_parameter.vault_pki_intermediate_ca_csr.value
  ca_private_key_pem = tls_private_key.root_ca.private_key_pem
  ca_cert_pem        = tls_self_signed_cert.root_ca.cert_pem

  validity_period_hours = 26280
  is_ca_certificate     = true

  allowed_uses = [
    "cert_signing",
    "crl_signing",
  ]
}

resource "aws_secretsmanager_secret_version" "vault_pki_signed_intermediate_ca" {
  secret_id = module.vault.vault_pki_signed_intermediate_ca_secret_arn
  secret_string = jsonencode({
    signed_intermediate_pem = tls_locally_signed_cert.vault_pki_signed_intermediate_ca.cert_pem
    ca_chain_pem            = tls_self_signed_cert.root_ca.cert_pem
  })
}
