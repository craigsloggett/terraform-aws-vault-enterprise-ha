#!/bin/sh
# issue-vault-tls-cert.sh
#
# Issues a PKI-signed TLS certificate and private key for this node from
# the Vault PKI engine, reloads the local Vault TLS listener with the new
# cert, and replaces the on-disk bootstrap CA with the PKI managed CA
# bundle. Runs on every node after configure-vault-pki.sh has finished and
# pki_state=Ready. Authenticates against the local Vault via AWS IAM since
# each runcmd entry runs in its own process and no VAULT_TOKEN is available
# from prior entries.

set -euf

# shellcheck source=/dev/null
. /var/lib/cloud/scripts/bootstrap.env
# shellcheck source=/dev/null
. /var/lib/cloud/scripts/common-functions.sh

readonly VAULT_TLS_DIR="/opt/vault/tls"
readonly VAULT_TLS_CA_FILE="${VAULT_TLS_DIR}/ca.crt"
readonly VAULT_TLS_CERT_FILE="${VAULT_TLS_DIR}/server.crt"
readonly VAULT_TLS_KEY_FILE="${VAULT_TLS_DIR}/server.key"

fetch_tls_ca_bundle() (
  fetch_parameter "${VAULT_PKI_INTERMEDIATE_CA_SSM_PARAMETER_NAME}"
)

issue_vault_pki_tls_certificate_and_key() (
  log_info "Issuing PKI TLS certificate and private key for this node"

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

write_vault_pki_ca_bundle() (
  log_info "Replacing bootstrap CA cert with PKI managed TLS CA bundle"

  pki_ca_bundle="$(fetch_tls_ca_bundle)"

  printf '%s\n' "${pki_ca_bundle}" >"${VAULT_TLS_CA_FILE}"
  chown vault:vault "${VAULT_TLS_CA_FILE}"
  chmod 0644 "${VAULT_TLS_CA_FILE}"
)

main() {
  export VAULT_ADDR="https://127.0.0.1:8200"
  export VAULT_TLS_SERVER_NAME="${VAULT_FQDN}"
  export VAULT_CACERT="${VAULT_TLS_CA_FILE}"

  issue_vault_pki_tls_certificate_and_key
  reload_vault_listener
  write_vault_pki_ca_bundle
}

main "${@}"
