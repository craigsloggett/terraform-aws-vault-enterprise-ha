#!/bin/sh
# wait-for-vault-cluster.sh
#
# Waits for the Vault cluster to be initialized (cluster_state=Ready in SSM)
# and for the local vault.service to be unsealed by KMS auto-unseal. Runs
# on every node after initialize-vault-cluster.sh. The bootstrap node passes
# through quickly since it just published Ready and KMS auto-unseal completes
# during operator init.

set -euf

# shellcheck source=/dev/null
. /var/lib/cloud/scripts/bootstrap.env
# shellcheck source=/dev/null
. /var/lib/cloud/scripts/common-functions.sh

wait_for_cluster_ready() (
  log_info "Waiting for the Vault cluster to be initialized"

  # 60 attempts x 5s = 5 minutes.
  max_attempts=60
  attempt=0
  while [ "${attempt}" -lt "${max_attempts}" ]; do
    attempt=$((attempt + 1))

    state="$(fetch_parameter "${BOOTSTRAP_CLUSTER_STATE_NAME}")" || true
    if [ "${state}" = "Ready" ]; then
      log_info "Cluster is ready, proceeding"
      return 0
    fi

    log_info "Cluster is not initialized (attempt ${attempt}/${max_attempts}), waiting"
    sleep 5
  done

  log_error "Unable to join the Vault cluster after ${max_attempts} attempts"
  return 1
)

wait_for_vault_unsealed() (
  log_info "Waiting for the local Vault node to be unsealed"

  # 60 attempts x 10s = 10 minutes.
  max_attempts=60
  attempt=0
  while [ "${attempt}" -lt "${max_attempts}" ]; do
    attempt=$((attempt + 1))

    vault_status_exit_code=0
    vault_status_err="$(vault status -format=json 2>&1 >/dev/null)" ||
      vault_status_exit_code="$?"

    case "${vault_status_exit_code}" in
      0)
        log_info "Cluster is unsealed, proceeding"
        return 0
        ;;
      2)
        : # Sealed, keep waiting
        ;;
      *)
        log_warn "Vault returned an error when querying status:"
        log_warn "${vault_status_err}"
        ;;
    esac

    log_info "Cluster is not unsealed (attempt ${attempt}/${max_attempts}), waiting"
    sleep 5
  done

  log_error "Vault did not unseal after ${max_attempts} attempts"
  return 1
)

main() {
  export VAULT_ADDR="https://127.0.0.1:8200"
  export VAULT_TLS_SERVER_NAME="${VAULT_FQDN}"
  export VAULT_CACERT="/opt/vault/tls/ca.crt"

  wait_for_cluster_ready
  wait_for_vault_unsealed
}

main "${@}"
