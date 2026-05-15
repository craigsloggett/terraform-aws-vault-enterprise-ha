#!/bin/sh
# configure-vault-pki.sh
#
# Bootstrap node: configures the Vault PKI secrets engine with an externally
# signed intermediate CA, creates the vault-server PKI role, writes the
# vault-server policy, publishes the PKI managed TLS CA bundle to SSM, and
# marks pki_state=Ready. Follower nodes wait for pki_state=Ready before
# returning. Runs on every node after the cluster is initialized.

set -euf

# shellcheck source=bootstrap.env.tftpl
. /var/lib/cloud/scripts/bootstrap.env
# shellcheck source=SCRIPTDIR/common-functions.sh
. /var/lib/cloud/scripts/common-functions.sh

readonly VAULT_POLICY_DIR="/etc/vault.d/policies"

TMPDIR_SESSION="$(mktemp -d)"
readonly TMPDIR_SESSION
trap 'rm -rf "${TMPDIR_SESSION}"' EXIT INT TERM HUP

enable_vault_pki_secrets_engine() (
  log_info "Enabling Vault PKI secrets engine"

  # Check if the secrets engine is already enabled before enabling it.
  if ! vault secrets list -format=json | jq -e --arg path "${VAULT_PKI_MOUNT_PATH}/" '.[$path]' >/dev/null 2>&1; then
    vault secrets enable -path="${VAULT_PKI_MOUNT_PATH}" -description="issues TLS leaf certificates for Vault cluster nodes" pki
  fi

  # Configure the Vault PKI max TTL value.
  vault secrets tune -max-lease-ttl="${VAULT_PKI_VAULT_MOUNT_MAX_TTL}" "${VAULT_PKI_MOUNT_PATH}" >/dev/null

  log_info "Vault PKI secrets engine enabled"
)

configure_vault_pki_urls() (
  log_info "Configuring Vault PKI URLs"

  vault write "${VAULT_PKI_MOUNT_PATH}/config/urls" - >/dev/null <<EOF
{
  "issuing_certificates": "https://${VAULT_FQDN}:8200/v1/${VAULT_PKI_MOUNT_PATH}/ca",
  "crl_distribution_points": "https://${VAULT_FQDN}:8200/v1/${VAULT_PKI_MOUNT_PATH}/crl",
  "ocsp_servers": "https://${VAULT_FQDN}:8200/v1/${VAULT_PKI_MOUNT_PATH}/ocsp"
}
EOF
)

generate_vault_pki_intermediate_ca() (
  log_info "Generating Vault PKI intermediate CA"
  intermediate_ca_response_file="$1"

  intermediate_ca_payload="$(
    jq -nc \
      --arg common_name "${VAULT_PKI_INTERMEDIATE_CA_COMMON_NAME}" \
      --arg country "${VAULT_PKI_INTERMEDIATE_CA_COUNTRY}" \
      --arg organization "${VAULT_PKI_INTERMEDIATE_CA_ORGANIZATION}" \
      --arg key_type "${VAULT_PKI_INTERMEDIATE_CA_KEY_TYPE}" \
      --argjson key_bits "${VAULT_PKI_INTERMEDIATE_CA_KEY_BITS}" \
      '{common_name: $common_name, country: $country, organization: $organization, key_type: $key_type, key_bits: $key_bits}'
  )"

  vault write -format=json "${VAULT_PKI_MOUNT_PATH}/intermediate/generate/internal" - >"${intermediate_ca_response_file}" <<EOF
${intermediate_ca_payload}
EOF
)

generate_vault_pki_intermediate_ca_csr() (
  log_info "Generating Vault PKI intermediate CA CSR"
  intermediate_ca_response_file="$1"

  jq -r '.data.csr' <"${intermediate_ca_response_file}"
)

publish_vault_pki_intermediate_ca_csr() (
  log_info "Publishing Vault PKI intermediate CA CSR to ${VAULT_PKI_INTERMEDIATE_CA_CSR_SSM_PARAMETER_NAME}"
  vault_pki_intermediate_ca_csr="${1}"

  put_parameter "${VAULT_PKI_INTERMEDIATE_CA_CSR_SSM_PARAMETER_NAME}" "${vault_pki_intermediate_ca_csr}"
)

wait_for_signed_vault_pki_intermediate_ca() (
  log_info "Waiting for signed Vault PKI intermediate CA"

  interval="${VAULT_PKI_SIGNED_INTERMEDIATE_POLL_INTERVAL_SECONDS}"
  max_attempts=$((VAULT_PKI_SIGNED_INTERMEDIATE_WAIT_TIMEOUT_SECONDS / interval))
  attempt=0

  while [ "${attempt}" -lt "${max_attempts}" ]; do
    attempt=$((attempt + 1))

    signed_vault_pki_intermediate_ca="$(fetch_secret_no_retry "${VAULT_PKI_SIGNED_INTERMEDIATE_CA_SECRET_ARN}")" || true
    if [ -n "${signed_vault_pki_intermediate_ca}" ]; then
      return 0
    fi

    sleep "${interval}"
  done

  log_error "Timed out after ${max_attempts} attempts"
  return 1
)

fetch_signed_vault_pki_intermediate_ca() (
  fetch_secret "${VAULT_PKI_SIGNED_INTERMEDIATE_CA_SECRET_ARN}"
)

validate_signed_vault_pki_intermediate_ca() (
  log_info "Validating signed Vault PKI intermediate CA"
  signed_vault_pki_intermediate_ca="${1}"

  if printf '%s' "${signed_vault_pki_intermediate_ca}" | jq -e 'has("private_key")' >/dev/null 2>&1; then
    log_error "Signed Vault PKI intermediate CA contains a private_key field, aborting"
    return 1
  fi

  for field in signed_intermediate_ca_pem ca_chain_pem; do
    value="$(printf '%s' "${signed_vault_pki_intermediate_ca}" | jq -r --arg field "${field}" '.[$field] // empty')"
    if [ -z "${value}" ]; then
      log_error "${field} field is missing or empty in: ${VAULT_PKI_SIGNED_INTERMEDIATE_CA_SECRET_ARN}"
      return 1
    fi
  done
)

import_signed_vault_pki_intermediate_ca() (
  log_info "Importing signed Vault PKI intermediate CA"
  signed_vault_pki_intermediate_ca="${1}"

  intermediate_ca_set_signed_payload="$(
    printf '%s' "${signed_vault_pki_intermediate_ca}" | jq -c '{certificate: (.signed_intermediate_ca_pem + "\n" + .ca_chain_pem)}'
  )"

  intermediate_ca_set_signed_response_file="${TMPDIR_SESSION}/intermediate_ca_set_signed_response.json"

  vault write -format=json "${VAULT_PKI_MOUNT_PATH}/intermediate/set-signed" - >"${intermediate_ca_set_signed_response_file}" <<EOF
${intermediate_ca_set_signed_payload}
EOF

  imported_intermediate_ca_issuer_id="$(
    jq -r '.data.mapping | to_entries[] | select(.value != "") | .key' <"${intermediate_ca_set_signed_response_file}"
  )"

  vault write "${VAULT_PKI_MOUNT_PATH}/config/issuers" default="${imported_intermediate_ca_issuer_id}" >/dev/null

  log_info "Signed Vault PKI intermediate CA imported"
)

configure_vault_pki_role() (
  log_info "Configuring Vault PKI role"

  vault write "${VAULT_PKI_MOUNT_PATH}/roles/vault-server" - >/dev/null <<EOF
{
  "allowed_domains": "${VAULT_FQDN}",
  "allow_bare_domains": true,
  "allow_subdomains": false,
  "allow_localhost": false,
  "allow_ip_sans": false,
  "country": ["${VAULT_PKI_INTERMEDIATE_CA_COUNTRY}"],
  "organization": ["${VAULT_PKI_INTERMEDIATE_CA_ORGANIZATION}"],
  "ext_key_usage": ["serverAuth"],
  "key_type": "ec",
  "key_bits": 384,
  "max_ttl": "${VAULT_PKI_VAULT_SERVER_ROLE_MAX_TTL}",
  "not_before_duration": "0s"
}
EOF

  vault policy write vault-server "${VAULT_POLICY_DIR}/vault-server.hcl"

  log_info "Vault PKI role created"
)

publish_vault_pki_ca_chain() (
  log_info "Publishing Vault PKI CA chain to ${VAULT_PKI_CA_CHAIN_SSM_PARAMETER_NAME}"

  vault_pki_ca_chain="$(
    vault read -format=json "${VAULT_PKI_MOUNT_PATH}/issuer/default/json" |
      jq -r '[.data.ca_chain[] | rtrimstr("\n")] | join("\n")'
  )"

  put_parameter "${VAULT_PKI_CA_CHAIN_SSM_PARAMETER_NAME}" "${vault_pki_ca_chain}"
)

publish_vault_pki_state() (
  log_info "Publishing Vault PKI state to ${BOOTSTRAP_PKI_STATE_SSM_PARAMETER_NAME}"
  put_parameter "${BOOTSTRAP_PKI_STATE_SSM_PARAMETER_NAME}" "Ready"
)

wait_for_vault_pki_ready() (
  log_info "Waiting for the bootstrap node to finish PKI setup"

  interval=5
  max_attempts=60
  attempt=0

  while [ "${attempt}" -lt "${max_attempts}" ]; do
    attempt=$((attempt + 1))

    vault_pki_state="$(fetch_parameter "${BOOTSTRAP_PKI_STATE_SSM_PARAMETER_NAME}")" || true
    if [ "${vault_pki_state}" = "Ready" ]; then
      return 0
    fi

    sleep "${interval}"
  done

  log_error "Timed out after ${max_attempts} attempts"
  return 1
)

main() {
  export VAULT_ADDR="https://127.0.0.1:8200"
  export VAULT_TLS_SERVER_NAME="${VAULT_FQDN}"
  export VAULT_CACERT="/opt/vault/tls/ca.crt"

  bootstrap_id="$(fetch_parameter "${BOOTSTRAP_NODE_ID_SSM_PARAMETER_NAME}")"

  if [ "${INSTANCE_ID}" != "${bootstrap_id}" ]; then
    wait_for_vault_pki_ready
    return 0
  fi

  VAULT_TOKEN="$(fetch_secret "${ROOT_TOKEN_SECRET_ARN}")"
  export VAULT_TOKEN

  enable_vault_pki_secrets_engine
  configure_vault_pki_urls

  intermediate_ca_response_file="${TMPDIR_SESSION}/intermediate_ca_response.json"
  generate_vault_pki_intermediate_ca "${intermediate_ca_response_file}"

  publish_vault_pki_intermediate_ca_csr "$(
    generate_vault_pki_intermediate_ca_csr "${intermediate_ca_response_file}"
  )"

  wait_for_signed_vault_pki_intermediate_ca
  signed_vault_pki_intermediate_ca="$(fetch_signed_vault_pki_intermediate_ca)"
  validate_signed_vault_pki_intermediate_ca "${signed_vault_pki_intermediate_ca}"
  import_signed_vault_pki_intermediate_ca "${signed_vault_pki_intermediate_ca}"

  configure_vault_pki_role

  publish_vault_pki_ca_chain
  publish_vault_pki_state
}

main "${@}"
