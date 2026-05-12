#!/bin/sh
# configure-vault-pki.sh
#
# Bootstrap node: configures the Vault PKI secrets engine with an externally
# signed intermediate CA, creates the vault-server PKI role, writes the
# vault-server policy, publishes the PKI managed TLS CA bundle to SSM, and
# marks pki_state=Ready. Follower nodes wait for pki_state=Ready before
# returning. Runs on every node after the cluster is initialized.

set -euf

# shellcheck source=/dev/null
. /var/lib/cloud/scripts/bootstrap.env
# shellcheck source=/dev/null
. /var/lib/cloud/scripts/common-functions.sh

readonly VAULT_POLICY_DIR="/etc/vault.d/policies"

TMPDIR_SESSION="$(mktemp -d)"
readonly TMPDIR_SESSION
trap 'rm -rf "${TMPDIR_SESSION}"' EXIT INT TERM HUP

configure_pki_vault_secrets_engine() (
  log_info "Enabling Vault PKI secrets engine"

  if ! vault secrets list -format=json | jq -e --arg path "${VAULT_PKI_MOUNT_PATH}/" '.[$path]' >/dev/null 2>&1; then
    vault secrets enable -path="${VAULT_PKI_MOUNT_PATH}" -description="issues TLS leaf certificates for Vault cluster nodes" pki
  fi

  vault secrets tune -max-lease-ttl="${VAULT_PKI_VAULT_MOUNT_MAX_TTL}" "${VAULT_PKI_MOUNT_PATH}" >/dev/null

  log_info "Vault PKI secrets engine enabled"
)

generate_pki_intermediate_csr() (
  log_info "Configuring intermediate URLs"

  vault write "${VAULT_PKI_MOUNT_PATH}/config/urls" - >/dev/null <<EOF
{
  "issuing_certificates": "https://${VAULT_FQDN}:8200/v1/${VAULT_PKI_MOUNT_PATH}/ca",
  "crl_distribution_points": "https://${VAULT_FQDN}:8200/v1/${VAULT_PKI_MOUNT_PATH}/crl",
  "ocsp_servers": "https://${VAULT_FQDN}:8200/v1/${VAULT_PKI_MOUNT_PATH}/ocsp"
}
EOF

  log_info "Generating intermediate CSR"
  csr_payload="$(
    jq -nc \
      --arg common_name "${VAULT_PKI_INTERMEDIATE_CA_COMMON_NAME}" \
      --arg country "${VAULT_PKI_INTERMEDIATE_CA_COUNTRY}" \
      --arg organization "${VAULT_PKI_INTERMEDIATE_CA_ORGANIZATION}" \
      --arg key_type "${VAULT_PKI_INTERMEDIATE_CA_KEY_TYPE}" \
      --argjson key_bits "${VAULT_PKI_INTERMEDIATE_CA_KEY_BITS}" \
      '{common_name: $common_name, country: $country, organization: $organization, key_type: $key_type, key_bits: $key_bits}'
  )"

  csr_response_file="${TMPDIR_SESSION}/intermediate_csr_response.json"
  vault write -format=json "${VAULT_PKI_MOUNT_PATH}/intermediate/generate/internal" - >"${csr_response_file}" <<EOF
${csr_payload}
EOF

  jq -r '.data.csr' <"${csr_response_file}"
)

publish_pki_intermediate_csr() (
  csr_pem="${1}"

  log_info "Publishing intermediate CSR to ${VAULT_PKI_INTERMEDIATE_CA_CSR_SSM_PARAMETER_NAME}"
  put_parameter "${VAULT_PKI_INTERMEDIATE_CA_CSR_SSM_PARAMETER_NAME}" "${csr_pem}"
)

wait_for_signed_pki_intermediate() (
  log_info "Waiting for the externally signed intermediate certificate"

  interval="${VAULT_PKI_SIGNED_INTERMEDIATE_POLL_INTERVAL_SECONDS}"
  max_attempts=$((VAULT_PKI_SIGNED_INTERMEDIATE_WAIT_TIMEOUT_SECONDS / interval))
  attempt=0

  while [ "${attempt}" -lt "${max_attempts}" ]; do
    attempt=$((attempt + 1))

    secret_value="$(aws secretsmanager get-secret-value \
      --secret-id "${VAULT_PKI_SIGNED_INTERMEDIATE_CA_SECRET_ARN}" \
      --query SecretString --output text 2>/dev/null)" || secret_value=""

    if [ -n "${secret_value}" ] && printf '%s' "${secret_value}" | jq -e '.certificate' >/dev/null 2>&1; then
      return 0
    fi

    sleep "${interval}"
  done

  log_error "Timed out after ${VAULT_PKI_SIGNED_INTERMEDIATE_WAIT_TIMEOUT_SECONDS}s waiting for signed intermediate at ${VAULT_PKI_SIGNED_INTERMEDIATE_CA_SECRET_ARN}"
  return 1
)

fetch_signed_pki_intermediate() (
  fetch_secret "${VAULT_PKI_SIGNED_INTERMEDIATE_CA_SECRET_ARN}"
)

import_signed_pki_intermediate() (
  signed_json="${1}"

  log_info "Importing externally signed intermediate certificate"

  if printf '%s' "${signed_json}" | jq -e '.private_key // empty' >/dev/null 2>&1; then
    log_error "Signed intermediate payload contains a private_key field, aborting"
    return 1
  fi

  signed_cert="$(printf '%s' "${signed_json}" | jq -r '.certificate // empty')"
  ca_chain="$(printf '%s' "${signed_json}" | jq -r '.ca_chain // empty')"

  if [ -z "${signed_cert}" ]; then
    log_error "Signed intermediate payload is missing the certificate field"
    return 1
  fi

  if [ -z "${ca_chain}" ]; then
    log_error "Signed intermediate payload is missing the ca_chain field"
    return 1
  fi

  set_signed_payload="$(
    jq -nc \
      --arg signed_cert "${signed_cert}" \
      --arg ca_chain "${ca_chain}" \
      '{certificate: ($signed_cert + "\n" + $ca_chain)}'
  )"

  set_signed_response_file="${TMPDIR_SESSION}/intermediate_set_signed_response.json"
  vault write -format=json "${VAULT_PKI_MOUNT_PATH}/intermediate/set-signed" - >"${set_signed_response_file}" <<EOF
${set_signed_payload}
EOF

  imported_issuer_id="$(
    jq -r '.data.mapping | to_entries[] | select(.value != "") | .key' <"${set_signed_response_file}"
  )"

  vault write "${VAULT_PKI_MOUNT_PATH}/config/issuers" default="${imported_issuer_id}" >/dev/null

  log_info "Intermediate CA signed and imported"
)

configure_vault_server_pki_role() (
  log_info "Creating vault-server PKI role"

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

  log_info "vault-server PKI role created"
)

publish_tls_ca_bundle() (
  log_info "Publishing PKI managed TLS CA bundle to SSM"

  ca_bundle_response_file="${TMPDIR_SESSION}/issuer_default_response.json"
  vault read -format=json "${VAULT_PKI_MOUNT_PATH}/issuer/default/json" >"${ca_bundle_response_file}"
  tls_ca_bundle="$(jq -r '.data.ca_chain[]' <"${ca_bundle_response_file}")"

  put_parameter "${VAULT_PKI_INTERMEDIATE_CA_SSM_PARAMETER_NAME}" "${tls_ca_bundle}"
)

mark_pki_ready() (
  log_info "Writing PKI state: Ready"
  put_parameter "${BOOTSTRAP_PKI_STATE_NAME}" "Ready"
)

wait_for_pki_ready() (
  log_info "Waiting for the bootstrap node to finish PKI setup"

  # 60 attempts x 10s = 10 minutes.
  max_attempts=60
  attempt=0
  while [ "${attempt}" -lt "${max_attempts}" ]; do
    attempt=$((attempt + 1))

    state="$(fetch_parameter "${BOOTSTRAP_PKI_STATE_NAME}")" || true
    if [ "${state}" = "Ready" ]; then
      log_info "PKI is ready, proceeding"
      return 0
    fi

    log_info "PKI is not ready (attempt ${attempt}/${max_attempts}), waiting"
    sleep 5
  done

  log_error "PKI was not ready after ${max_attempts} attempts, failing bootstrap"
  return 1
)

bootstrap_node_main() {
  VAULT_TOKEN="$(fetch_secret "${ROOT_TOKEN_SECRET_ARN}")"
  export VAULT_TOKEN

  configure_pki_vault_secrets_engine

  intermediate_csr="$(generate_pki_intermediate_csr)"
  publish_pki_intermediate_csr "${intermediate_csr}"

  wait_for_signed_pki_intermediate
  signed_intermediate="$(fetch_signed_pki_intermediate)"
  import_signed_pki_intermediate "${signed_intermediate}"

  configure_vault_server_pki_role
  vault policy write vault-server "${VAULT_POLICY_DIR}/vault-server.hcl"

  publish_tls_ca_bundle
  mark_pki_ready
}

main() {
  export VAULT_ADDR="https://127.0.0.1:8200"
  export VAULT_TLS_SERVER_NAME="${VAULT_FQDN}"
  export VAULT_CACERT="/opt/vault/tls/ca.crt"

  bootstrap_id="$(fetch_parameter "${BOOTSTRAP_NODE_ID_NAME}")"

  if [ "${INSTANCE_ID}" != "${bootstrap_id}" ]; then
    wait_for_pki_ready
    return 0
  fi

  bootstrap_node_main
}

main "${@}"
