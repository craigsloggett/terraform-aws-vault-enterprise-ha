pid_file = "/run/vault/agent.pid"

vault {
  address         = "https://127.0.0.1:8200"
  ca_cert         = "${VAULT_TLS_CA_FILE}"
  tls_server_name = "${VAULT_FQDN}"
}

auto_auth {
  method "aws" {
    mount_path = "auth/aws"
    config = {
      type = "iam"
      role = "vault-server"
    }
  }
}

template {
  source      = "${VAULT_AGENT_SERVER_TLS_TEMPLATE_FILE}"
  destination = "${VAULT_TLS_CERT_FILE}.new"
  perms       = "0640"
  command     = "${VAULT_AGENT_SERVER_TLS_RELOAD_FILE}"
}
