# Resources used only during the initial Vault cluster bootstrap process.

# CA

resource "tls_private_key" "bootstrap_tls_ca_private_key" {
  algorithm   = "ECDSA"
  ecdsa_curve = "P384"
}

resource "tls_self_signed_cert" "bootstrap_tls_ca" {
  private_key_pem = tls_private_key.bootstrap_tls_ca_private_key.private_key_pem

  subject {
    common_name  = "${var.project_name} CA"
    organization = var.project_name
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
    organization = var.project_name
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

# Secrets Manager

resource "aws_secretsmanager_secret" "bootstrap_tls_ca" {
  name_prefix = "${var.project_name}-vault-bootstrap-tls-ca-"
  description = "Vault Bootstrap TLS CA"
}

resource "aws_secretsmanager_secret_version" "bootstrap_tls_ca" {
  secret_id     = aws_secretsmanager_secret.bootstrap_tls_ca.id
  secret_string = tls_self_signed_cert.bootstrap_tls_ca.cert_pem
}

resource "aws_secretsmanager_secret" "bootstrap_tls_cert" {
  name_prefix = "${var.project_name}-vault-bootstrap-tls-cert-"
  description = "Vault Bootstrap TLS Certificate"
}

resource "aws_secretsmanager_secret_version" "bootstrap_tls_cert" {
  secret_id     = aws_secretsmanager_secret.bootstrap_tls_cert.id
  secret_string = tls_locally_signed_cert.bootstrap_tls_cert.cert_pem
}

resource "aws_secretsmanager_secret" "bootstrap_tls_private_key" {
  name_prefix = "${var.project_name}-vault-bootstrap-tls-private-key-"
  description = "Vault Bootstrap TLS Private Key"
}

resource "aws_secretsmanager_secret_version" "bootstrap_tls_private_key" {
  secret_id     = aws_secretsmanager_secret.bootstrap_tls_private_key.id
  secret_string = tls_private_key.bootstrap_tls_private_key.private_key_pem
}

# Root Token

resource "aws_secretsmanager_secret" "vault_server_bootstrap_root_token" {
  name_prefix = "${var.project_name}-vault-bootstrap-root-token-"
  description = "Vault Bootstrap Root Token"
}

# Initialization Coordination SSM Parameters

resource "aws_ssm_parameter" "vault_cluster_state" {
  name        = "/${var.project_name}/vault/bootstrap/cluster/state"
  type        = "String"
  value       = "Uninitialized"
  description = "Bootstrap Initialization State Flag (Uninitialized | Ready)"

  lifecycle {
    ignore_changes = [value]
  }
}

resource "aws_ssm_parameter" "vault_pki_state" {
  name        = "/${var.project_name}/vault/bootstrap/pki/state"
  type        = "String"
  value       = "Uninitialized"
  description = "Bootstrap PKI State Flag (Uninitialized | Ready)"

  lifecycle {
    ignore_changes = [value]
  }
}

resource "aws_ssm_parameter" "vault_pki_intermediate_ca_csr" {
  name        = "/${var.project_name}/vault/bootstrap/pki/intermediate-csr"
  type        = "String"
  value       = "Uninitialized"
  description = "Bootstrap PKI Intermediate CA CSR"

  lifecycle {
    ignore_changes = [value]
  }
}
