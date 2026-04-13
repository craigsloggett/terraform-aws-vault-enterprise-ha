# shellcheck shell=sh
# cli.sh — Vault CLI environment configuration.

write_vault_cli_config() {
  vault_fqdn="${1}"
  vault_tls_ca_file="${2}"

  log_info "Writing Vault CLI environment to /etc/profile.d/99-vault-cli-config.sh"

  cat >/etc/profile.d/99-vault-cli-config.sh <<EOF
export VAULT_ADDR="https://127.0.0.1:8200"
export VAULT_TLS_SERVER_NAME="${vault_fqdn}"
export VAULT_CACERT="${vault_tls_ca_file}"
EOF
}
