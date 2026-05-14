#!/bin/sh
# issue-vault-tls-cert.sh
#
# Issues a Vault PKI managed TLS certificate and private key for this node,
# reloads the local Vault TLS listener, replaces the on-disk Bootstrap CA with
# the signed Vault PKI intermediate CA, and then updates the system trust
# store.

set -euf

# shellcheck source=bootstrap.env.tftpl
. /var/lib/cloud/scripts/bootstrap.env
# shellcheck source=SCRIPTDIR/common-functions.sh
. /var/lib/cloud/scripts/common-functions.sh

readonly VAULT_TLS_DIR="/opt/vault/tls"
readonly VAULT_TLS_CA_FILE="${VAULT_TLS_DIR}/ca.crt"
readonly VAULT_TLS_CERT_FILE="${VAULT_TLS_DIR}/server.crt"
readonly VAULT_TLS_KEY_FILE="${VAULT_TLS_DIR}/server.key"

TMPDIR_SESSION="$(mktemp -d)"
readonly TMPDIR_SESSION
trap 'rm -rf "${TMPDIR_SESSION}"' EXIT INT TERM HUP

issue_vault_pki_tls_certificate_and_key() (
  log_info "Issuing Vault PKI TLS certificate and private key"

  export VAULT_ADDR="https://127.0.0.1:8200"
  export VAULT_TLS_SERVER_NAME="${VAULT_FQDN}"
  export VAULT_CACERT="${VAULT_TLS_CA_FILE}"

  log_info "Authenticating via AWS IAM auth method"
  vault_token="$(
    vault login \
      -format=json \
      -method=aws \
      role=vault-server |
      jq -r '.auth.client_token'
  )"
  export VAULT_TOKEN="${vault_token}"

  log_info "Requesting certificate from PKI engine"
  pki_issue_response="$(
    vault write -format=json "${VAULT_PKI_MOUNT_PATH}/issue/vault-server" - <<EOF
{
  "common_name": "${VAULT_FQDN}",
  "ttl": "${VAULT_PKI_SERVER_CERT_TTL}"
}
EOF
  )"

  vault_tls_cert_tmp_file="${VAULT_TLS_DIR}/server.crt.tmp"
  vault_tls_key_tmp_file="${VAULT_TLS_DIR}/server.key.tmp"

  {
    printf '%s' "${pki_issue_response}" | jq -r '.data.certificate'
    printf '%s' "${pki_issue_response}" | jq -r '.data.ca_chain[]'
  } >"${vault_tls_cert_tmp_file}"
  printf '%s' "${pki_issue_response}" | jq -r '.data.private_key' >"${vault_tls_key_tmp_file}"

  chown vault:vault "${vault_tls_cert_tmp_file}" "${vault_tls_key_tmp_file}"
  chmod 0640 "${vault_tls_cert_tmp_file}" "${vault_tls_key_tmp_file}"

  mv "${vault_tls_cert_tmp_file}" "${VAULT_TLS_CERT_FILE}"
  mv "${vault_tls_key_tmp_file}" "${VAULT_TLS_KEY_FILE}"

  log_info "PKI TLS certificate written to ${VAULT_TLS_CERT_FILE}"
  log_info "PKI TLS private key written to ${VAULT_TLS_KEY_FILE}"
)

reload_vault_listener() (
  log_info "Reloading Vault TLS listener with PKI-signed certificate"

  systemctl kill --signal=SIGHUP --kill-whom=main vault.service

  log_info "Vault TLS listener reloaded"
)

install_vault_pki_ca_chain() (
  log_info "Installing Vault PKI CA chain to /opt/vault/tls/ca.crt, replacing the Bootstrap CA"

  fetch_parameter "${VAULT_PKI_CA_CHAIN_SSM_PARAMETER_NAME}" >"${TMPDIR_SESSION}/vault-pki-ca-chain.pem"
  install -o vault -g vault -m 0644 "${TMPDIR_SESSION}/vault-pki-ca-chain.pem" "${VAULT_TLS_CA_FILE}"
)

trust_vault_pki_ca_chain() (
  log_info "Trusting Vault PKI CA chain"

  install -o root -g root -m 0644 "${VAULT_TLS_CA_FILE}" /usr/local/share/ca-certificates/vault-pki-ca-chain.crt
  update-ca-certificates >/dev/null
)

main() {
  issue_vault_pki_tls_certificate_and_key
  reload_vault_listener
  install_vault_pki_ca_chain
  trust_vault_pki_ca_chain
}

main "${@}"
