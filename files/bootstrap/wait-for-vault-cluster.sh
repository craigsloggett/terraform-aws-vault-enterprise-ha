#!/bin/sh
# wait-for-vault-cluster.sh
#
# Waits for the Vault cluster to be initialized (cluster_state=Ready in SSM)
# and for the local vault.service to be unsealed by KMS auto-unseal. Runs
# on every node after initialize-vault-cluster.sh. The bootstrap node passes
# through quickly since it just published Ready and KMS auto-unseal completes
# during operator init.

set -euf

# shellcheck source=bootstrap.env.tftpl
. /var/lib/cloud/scripts/bootstrap.env
# shellcheck source=SCRIPTDIR/common-functions.sh
. /var/lib/cloud/scripts/common-functions.sh

wait_for_vault_cluster_ready() (
  log_info "Waiting for the Vault cluster to be initialized"

  interval=5
  max_attempts=60
  attempt=0

  while [ "${attempt}" -lt "${max_attempts}" ]; do
    attempt=$((attempt + 1))

    vault_cluster_state="$(fetch_parameter "${BOOTSTRAP_VAULT_CLUSTER_STATE_SSM_PARAMETER_NAME}")" || true
    if [ "${vault_cluster_state}" = "Ready" ]; then
      return 0
    fi

    sleep "${interval}"
  done

  log_error "Unable to join the Vault cluster after ${max_attempts} attempts"
  return 1
)

wait_for_vault_unseal() (
  log_info "Waiting for the local Vault node to be unsealed"

  interval=5
  max_attempts=60
  attempt=0

  while [ "${attempt}" -lt "${max_attempts}" ]; do
    attempt=$((attempt + 1))

    vault_status_exit_code=0
    vault_status_err="$(vault status -format=json 2>&1 >/dev/null)" || vault_status_exit_code="$?"

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

    sleep "${interval}"
  done

  log_error "Vault did not unseal after ${max_attempts} attempts"
  return 1
)

wait_for_raft_replication() (
  log_info "Waiting for the local node to catch up on Raft replication"

  interval=5
  max_attempts=60
  attempt=0

  while [ "${attempt}" -lt "${max_attempts}" ]; do
    attempt=$((attempt + 1))

    vault_leader_response="$(vault read -format=json sys/leader 2>/dev/null)" || true

    if [ -n "${vault_leader_response}" ]; then
      committed="$(printf '%s' "${vault_leader_response}" | jq -r '.data.raft_committed_index // empty')"
      applied="$(printf '%s' "${vault_leader_response}" | jq -r '.data.raft_applied_index // empty')"

      if [ -n "${committed}" ] && [ -n "${applied}" ] &&
        [ "${committed}" -gt 0 ] && [ "${applied}" -ge "${committed}" ]; then
        log_info "Raft caught up (applied=${applied} committed=${committed})"
        return 0
      fi
    fi

    sleep "${interval}"
  done

  log_error "Raft did not catch up after ${max_attempts} attempts"
  return 1
)

main() {
  export VAULT_ADDR="https://127.0.0.1:8200"
  export VAULT_TLS_SERVER_NAME="${VAULT_FQDN}"
  export VAULT_CACERT="/opt/vault/tls/ca.crt"

  wait_for_vault_cluster_ready
  wait_for_vault_unseal
  wait_for_raft_replication
}

main "${@}"
