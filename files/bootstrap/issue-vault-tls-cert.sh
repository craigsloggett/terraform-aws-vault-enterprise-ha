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

  # Fetch the new CA bundle from SSM and authenticate against the local
  # Vault via the AWS IAM auth method. The bootstrap CA at VAULT_CACERT
  # stays in place until the listener reloads.
  new_ca_cert="$(fetch_tls_ca_bundle)"

  new_ca_cert_file="${VAULT_TLS_DIR}/pki-ca.crt"
  printf '%s\n' "${new_ca_cert}" >"${new_ca_cert_file}"
  chown vault:vault "${new_ca_cert_file}"
  chmod 0644 "${new_ca_cert_file}"

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
  cert_json="$(
    vault write -format=json "${VAULT_PKI_MOUNT_PATH}/issue/vault-server" - <<EOF
{
  "common_name": "${VAULT_FQDN}",
  "ttl": "${VAULT_PKI_SERVER_CERT_TTL}"
}
EOF
  )"

  tmp_cert="${VAULT_TLS_DIR}/server.crt.tmp"
  tmp_key="${VAULT_TLS_DIR}/server.key.tmp"

  {
    printf '%s' "${cert_json}" | jq -r '.data.certificate'
    printf '%s' "${cert_json}" | jq -r '.data.ca_chain[]'
  } >"${tmp_cert}"
  printf '%s' "${cert_json}" | jq -r '.data.private_key' >"${tmp_key}"

  chown vault:vault "${tmp_cert}" "${tmp_key}"
  chmod 0640 "${tmp_cert}" "${tmp_key}"

  mv "${tmp_cert}" "${VAULT_TLS_CERT_FILE}"
  mv "${tmp_key}" "${VAULT_TLS_KEY_FILE}"

  log_info "PKI TLS certificate written to ${VAULT_TLS_CERT_FILE}"
  log_info "PKI TLS private key written to ${VAULT_TLS_KEY_FILE}"
)

reload_vault_listener() (
  log_info "Reloading Vault TLS listener with PKI-signed certificate"

  systemctl kill --signal=SIGHUP --kill-whom=main vault.service

  log_info "Vault TLS listener reloaded"
)

write_vault_pki_ca_bundle() (
  cluster_tls_ca_bundle="$(fetch_tls_ca_bundle)"

  log_info "Replacing bootstrap CA cert with PKI managed TLS CA bundle"

  printf '%s\n' "${cluster_tls_ca_bundle}" >"${VAULT_TLS_CA_FILE}"
  chown vault:vault "${VAULT_TLS_CA_FILE}"
  chmod 0644 "${VAULT_TLS_CA_FILE}"

  temporary_cluster_ca_file="${VAULT_TLS_DIR}/pki-ca.crt"
  if [ -f "${temporary_cluster_ca_file}" ]; then
    rm -f "${temporary_cluster_ca_file}"
    log_info "Removed temporary PKI CA cert file ${temporary_cluster_ca_file}"
  fi
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
