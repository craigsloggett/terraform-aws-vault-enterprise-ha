#!/bin/sh
# determine-vault-node-role.sh
#
# Elects the bootstrap node by lowest EC2 instance ID and publishes the
# winner's instance ID to SSM. All nodes run this script; the winner writes
# the parameter and the rest wait for it to appear before continuing.

set -euf

# shellcheck source=bootstrap.env.tftpl
. /var/lib/cloud/scripts/bootstrap.env
# shellcheck source=SCRIPTDIR/common-functions.sh
. /var/lib/cloud/scripts/common-functions.sh

fetch_cluster_instance_ids() (
  fetch_instance_ids_with_tag "${AUTO_JOIN_TAG_KEY}" "${AUTO_JOIN_TAG_VALUE}"
)

is_bootstrap_node() (
  cluster_instance_ids="${1}"

  lowest_id="$(printf '%s' "${cluster_instance_ids}" | tr '\t' '\n' | sort | head -1)"

  [ "${INSTANCE_ID}" = "${lowest_id}" ]
)

wait_for_bootstrap_election() (
  log_info "Waiting for bootstrap node election to complete"

  interval=5
  max_attempts=60
  attempt=0

  while [ "${attempt}" -lt "${max_attempts}" ]; do
    attempt=$((attempt + 1))

    bootstrap_instance_id="$(fetch_parameter "${BOOTSTRAP_INSTANCE_ID_SSM_PARAMETER}" 2>/dev/null)" || true

    if [ -n "${bootstrap_instance_id}" ] && [ "${bootstrap_instance_id}" != "Uninitialized" ]; then
      log_info "Bootstrap node is ${bootstrap_instance_id}"
      return 0
    fi

    sleep "${interval}"
  done

  log_error "Timed out after ${max_attempts} attempts"
  return 1
)

main() {
  cluster_state="$(fetch_parameter "${BOOTSTRAP_VAULT_CLUSTER_STATE_SSM_PARAMETER_NAME}" 2>/dev/null)" || cluster_state=""

  if [ "${cluster_state}" = "Ready" ]; then
    log_info "Cluster already initialized, skipping bootstrap election"
    return 0
  fi

  cluster_instance_ids="$(fetch_cluster_instance_ids)"

  if is_bootstrap_node "${cluster_instance_ids}"; then
    log_info "This node (${INSTANCE_ID}) won bootstrap election, publishing to SSM"
    put_parameter "${BOOTSTRAP_INSTANCE_ID_SSM_PARAMETER}" "${INSTANCE_ID}"
  else
    wait_for_bootstrap_election
  fi
}

main "${@}"
