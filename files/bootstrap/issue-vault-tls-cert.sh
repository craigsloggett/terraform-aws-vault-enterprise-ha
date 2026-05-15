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

  vault_pki_role="vault-server"

  log_info "Authenticating via AWS IAM auth method"
  vault_token="$(
    vault login \
      -token-only \
      -no-store \
      -method=aws \
      role="${vault_pki_role}"
  )"
  export VAULT_TOKEN="${vault_token}"

  log_info "Requesting certificate from PKI engine"
  vault_pki_issue_response="$(
    vault write -format=json "${VAULT_PKI_MOUNT_PATH}/issue/${vault_pki_role}" - <<EOF
{
  "common_name": "${VAULT_FQDN}",
  "ttl": "${VAULT_PKI_SERVER_CERT_TTL}"
}
EOF
  )"

  tmp_vault_tls_cert_file="${TMPDIR_SESSION}/server.crt"
  tmp_vault_tls_key_file="${TMPDIR_SESSION}/server.key"

  {
    printf '%s' "${vault_pki_issue_response}" | jq -r '.data.certificate'
    printf '%s' "${vault_pki_issue_response}" | jq -r '.data.ca_chain[]'
  } >"${tmp_vault_tls_cert_file}"

  printf '%s' "${vault_pki_issue_response}" | jq -r '.data.private_key' >"${tmp_vault_tls_key_file}"

  # Staging to VAULT_TLS_DIR and using `mv` to perform an atomic swap (instead of a one-shot `install`).
  install -o vault -g vault -m 0640 -T "${tmp_vault_tls_cert_file}" "${VAULT_TLS_DIR}/server.crt.tmp"
  install -o vault -g vault -m 0640 -T "${tmp_vault_tls_key_file}" "${VAULT_TLS_DIR}/server.key.tmp"

  mv "${VAULT_TLS_DIR}/server.crt.tmp" "${VAULT_TLS_CERT_FILE}"
  mv "${VAULT_TLS_DIR}/server.key.tmp" "${VAULT_TLS_KEY_FILE}"

  log_info "Vault PKI TLS certificate and private key written to ${VAULT_TLS_CERT_FILE}"
)

reload_vault_listener() (
  log_info "Reloading Vault listener with Vault PKI issued certificate"

  systemctl kill --signal=SIGHUP --kill-whom=main vault.service
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
