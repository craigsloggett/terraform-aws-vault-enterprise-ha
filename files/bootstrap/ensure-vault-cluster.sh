#!/bin/sh
# ensure-vault-cluster.sh
#
# Ensures the Vault cluster is initialized and the local node is unsealed
# before the caller proceeds. Bootstrap node runs vault operator init and
# publishes the root token, recovery keys, and Ready state to SSM/Secrets
# Manager. Followers wait for cluster_state=Ready and then for the local
# vault.service to be unsealed by KMS auto-unseal.

set -euf

# shellcheck source=/dev/null
. /var/lib/cloud/scripts/bootstrap.env
# shellcheck source=/dev/null
. /var/lib/cloud/scripts/common_functions.sh

log_error() (
  printf '[ERROR] %s\n' "${1}" >&2
)

get_imds_token() (
  curl -s -X PUT \
    -H "X-aws-ec2-metadata-token-ttl-seconds: 3600" \
    "http://169.254.169.254/latest/api/token"
)

get_instance_id() (
  token="$(get_imds_token)"
  curl -s -H "X-aws-ec2-metadata-token: ${token}" \
    "http://169.254.169.254/latest/meta-data/instance-id"
)

initialize_cluster() (
  log_info "Initializing Vault cluster"

  if vault status -format=json 2>/dev/null | jq -e '.initialized == true' >/dev/null; then
    log_warn "Cluster already initialized, skipping"
    return 0
  fi

  log_info "Running vault operator init"
  # KMS auto-unseal is configured, so recovery shares/threshold are used
  # in place of unseal shares/threshold.
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
  put_parameter "${BOOTSTRAP_CLUSTER_STATE_NAME}" "Ready"

  log_info "Cluster initialization complete"
)

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

  bootstrap_id="$(fetch_parameter "${BOOTSTRAP_NODE_ID_NAME}")"
  instance_id="$(get_instance_id)"

  if [ "${instance_id}" = "${bootstrap_id}" ]; then
    initialize_cluster
  else
    wait_for_cluster_ready
    wait_for_vault_unsealed
  fi
}

main "${@}"
