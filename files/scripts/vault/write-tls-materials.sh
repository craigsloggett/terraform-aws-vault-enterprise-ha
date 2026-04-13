# shellcheck shell=sh
# write-tls-materials.sh — Write bootstrap TLS certificates to disk.

write_bootstrap_root_ca() {
  vault_tls_ca_file="${1}"

  ca_cert="$(get_bootstrap_root_ca)"

  log_info "Writing bootstrap root CA certificate"
  printf '%s\n' "${ca_cert}" >"${vault_tls_ca_file}"
  chown vault:vault "${vault_tls_ca_file}"
  chmod 0644 "${vault_tls_ca_file}"
}

write_bootstrap_tls_cert() {
  vault_tls_cert_file="${1}"

  server_cert="$(get_bootstrap_tls_cert)"

  log_info "Writing bootstrap TLS server certificate"
  printf '%s\n' "${server_cert}" >"${vault_tls_cert_file}"
  chown vault:vault "${vault_tls_cert_file}"
  chmod 0640 "${vault_tls_cert_file}"
}

write_bootstrap_tls_key() {
  vault_tls_key_file="${1}"

  server_key="$(get_bootstrap_tls_key)"

  log_info "Writing bootstrap TLS server key"
  printf '%s\n' "${server_key}" >"${vault_tls_key_file}"
  chown vault:vault "${vault_tls_key_file}"
  chmod 0640 "${vault_tls_key_file}"
}
