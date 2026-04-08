# CA

resource "tls_private_key" "ca" {
  algorithm = "ED25519"
}

resource "tls_self_signed_cert" "ca" {
  private_key_pem = tls_private_key.ca.private_key_pem

  subject {
    common_name  = "${var.project_name} CA"
    organization = var.project_name
  }

  validity_period_hours = 8760
  is_ca_certificate     = true

  allowed_uses = [
    "cert_signing",
    "crl_signing",
  ]
}

# Server

resource "tls_private_key" "server" {
  algorithm = "ED25519"
}

resource "tls_cert_request" "server" {
  private_key_pem = tls_private_key.server.private_key_pem

  subject {
    common_name  = local.vault_fqdn
    organization = var.project_name
  }

  dns_names = [
    local.vault_fqdn,
    "*.${var.route53_zone.name}",
    "localhost",
  ]

  ip_addresses = ["127.0.0.1"]
}

resource "tls_locally_signed_cert" "server" {
  cert_request_pem   = tls_cert_request.server.cert_request_pem
  ca_private_key_pem = tls_private_key.ca.private_key_pem
  ca_cert_pem        = tls_self_signed_cert.ca.cert_pem

  validity_period_hours = 8760

  allowed_uses = [
    "digital_signature",
    "key_encipherment",
    "server_auth",
    "client_auth",
  ]
}

# Secrets Manager

resource "aws_secretsmanager_secret" "vault_ca_cert" {
  name_prefix = "${var.project_name}-vault-ca-cert-"
  description = "Vault CA certificate"

  tags = merge(var.common_tags, { Name = "${var.project_name}-vault-ca-cert" })
}

resource "aws_secretsmanager_secret_version" "vault_ca_cert" {
  secret_id     = aws_secretsmanager_secret.vault_ca_cert.id
  secret_string = tls_self_signed_cert.ca.cert_pem
}

resource "aws_secretsmanager_secret" "vault_server_cert" {
  name_prefix = "${var.project_name}-vault-server-cert-"
  description = "Vault server certificate"

  tags = merge(var.common_tags, { Name = "${var.project_name}-vault-server-cert" })
}

resource "aws_secretsmanager_secret_version" "vault_server_cert" {
  secret_id     = aws_secretsmanager_secret.vault_server_cert.id
  secret_string = tls_locally_signed_cert.server.cert_pem
}

resource "aws_secretsmanager_secret" "vault_server_key" {
  name_prefix = "${var.project_name}-vault-server-key-"
  description = "Vault server private key"

  tags = merge(var.common_tags, { Name = "${var.project_name}-vault-server-key" })
}

resource "aws_secretsmanager_secret_version" "vault_server_key" {
  secret_id     = aws_secretsmanager_secret.vault_server_key.id
  secret_string = tls_private_key.server.private_key_pem
}

resource "aws_secretsmanager_secret_policy" "vault_server_key" {
  secret_arn = aws_secretsmanager_secret.vault_server_key.arn
  policy     = data.aws_iam_policy_document.vault_server_key.json
}

data "aws_iam_policy_document" "vault_server_key" {
  statement {
    sid    = "AllowVaultInstanceRole"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.vault.arn]
    }

    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.vault_server_key.arn]
  }
}

resource "aws_secretsmanager_secret" "vault_license" {
  name_prefix = "${var.project_name}-vault-license-"
  description = "Vault Enterprise license"

  tags = merge(var.common_tags, { Name = "${var.project_name}-vault-license" })
}

resource "aws_secretsmanager_secret_version" "vault_license" {
  secret_id     = aws_secretsmanager_secret.vault_license.id
  secret_string = var.vault_license
}
