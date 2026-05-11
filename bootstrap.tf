# Resources used only during the initial Vault cluster bootstrap process.

# CA

resource "tls_private_key" "bootstrap_tls_ca_private_key" {
  algorithm   = "ECDSA"
  ecdsa_curve = "P384"
}

resource "tls_self_signed_cert" "bootstrap_tls_ca" {
  private_key_pem = tls_private_key.bootstrap_tls_ca_private_key.private_key_pem

  subject {
    common_name  = "Vault Bootstrap CA"
    organization = "HashiCorp Vault"
  }

  validity_period_hours = 24
  is_ca_certificate     = true

  allowed_uses = [
    "cert_signing",
    "crl_signing",
  ]
}

# Private Key

resource "tls_private_key" "bootstrap_tls_private_key" {
  algorithm   = "ECDSA"
  ecdsa_curve = "P384"
}

resource "tls_cert_request" "bootstrap_tls_cert_request" {
  private_key_pem = tls_private_key.bootstrap_tls_private_key.private_key_pem

  subject {
    common_name  = local.vault_fqdn
    organization = "HashiCorp Vault"
  }

  dns_names = [
    local.vault_fqdn,
    "localhost"
  ]

  ip_addresses = ["127.0.0.1"]
}

resource "tls_locally_signed_cert" "bootstrap_tls_cert" {
  cert_request_pem   = tls_cert_request.bootstrap_tls_cert_request.cert_request_pem
  ca_private_key_pem = tls_private_key.bootstrap_tls_ca_private_key.private_key_pem
  ca_cert_pem        = tls_self_signed_cert.bootstrap_tls_ca.cert_pem

  validity_period_hours = 24

  allowed_uses = [
    "digital_signature",
    "key_encipherment",
    "server_auth"
  ]
}

# Initialization Coordination SSM Parameters

resource "aws_ssm_parameter" "bootstrap_cluster_state" {
  name        = var.bootstrap.ssm_parameter.cluster_state_name
  type        = "String"
  value       = "Uninitialized"
  description = "Bootstrap Initialization State Flag"

  lifecycle {
    ignore_changes = [value]
  }
}

resource "aws_ssm_parameter" "bootstrap_pki_state" {
  name        = var.bootstrap.ssm_parameter.pki_state_name
  type        = "String"
  value       = "Uninitialized"
  description = "Bootstrap PKI State Flag"

  lifecycle {
    ignore_changes = [value]
  }
}

resource "aws_ssm_parameter" "bootstrap_node_id" {
  name        = var.bootstrap.ssm_parameter.node_id_name
  type        = "String"
  value       = "Uninitialized"
  description = "EC2 instance ID of the elected bootstrap node"

  lifecycle {
    ignore_changes = [value]
  }
}
