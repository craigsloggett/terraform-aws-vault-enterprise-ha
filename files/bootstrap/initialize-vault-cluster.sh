#!/bin/sh
# initialize-vault-cluster.sh
#
# Initializes the Vault cluster on the bootstrap node. Runs vault operator
# init, publishes the root token and recovery keys to Secrets Manager, and
# marks cluster_state=Ready in SSM. Followers no-op. Runs after the local
# vault.service is up and listening.

set -euf

# shellcheck source=bootstrap.env.tftpl
. /var/lib/cloud/scripts/bootstrap.env
# shellcheck source=SCRIPTDIR/common-functions.sh
. /var/lib/cloud/scripts/common-functions.sh

initialize_cluster() (
  log_info "Initializing Vault cluster"

  if vault status -format=json 2>/dev/null | jq -e '.initialized == true' >/dev/null; then
    log_warn "Cluster already initialized, skipping"
    return 0
  fi

  # KMS auto-unseal is configured, so recovery-shares and recovery-threshold are used
  # in place of unseal-shares and unseal-threshold.
  init_output="$(
    vault operator init \
      -format=json \
      -recovery-shares=5 \
      -recovery-threshold=3
  )"

  root_token="$(printf '%s' "${init_output}" | jq -r '.root_token')"
  recovery_keys="$(printf '%s' "${init_output}" | jq -c '.recovery_keys_b64')"

  log_info "Storing bootstrap root token in Secrets Manager"
  put_secret "${ROOT_TOKEN_SECRET_ARN}" "${root_token}"

  log_info "Storing recovery keys in Secrets Manager"
  put_secret "${RECOVERY_KEYS_SECRET_ARN}" "${recovery_keys}"

  log_info "Writing cluster state: Ready"
  put_parameter "${BOOTSTRAP_VAULT_CLUSTER_STATE_SSM_PARAMETER_NAME}" "Ready"

  log_info "Cluster initialization complete"
)

main() {
  bootstrap_instance_id="$(fetch_parameter "${BOOTSTRAP_INSTANCE_ID_SSM_PARAMETER}")"

  if [ "${INSTANCE_ID}" != "${bootstrap_instance_id}" ]; then
    log_info "Not the bootstrap node, skipping cluster initialization"
    return 0
  fi

  export VAULT_ADDR="https://127.0.0.1:8200"
  export VAULT_TLS_SERVER_NAME="${VAULT_FQDN}"
  export VAULT_CACERT="/opt/vault/tls/ca.crt"

  initialize_cluster
}

main "${@}"
