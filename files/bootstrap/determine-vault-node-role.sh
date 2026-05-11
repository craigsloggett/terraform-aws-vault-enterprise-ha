#!/bin/sh
# determine-vault-node-role.sh
#
# Elects the bootstrap node by lowest EC2 instance ID and publishes the
# winner's instance ID to SSM. All nodes run this script; the winner writes
# the parameter and the rest wait for it to appear before continuing.

set -euf

# shellcheck source=/dev/null
. /var/lib/cloud/scripts/bootstrap.env
# shellcheck source=/dev/null
. /var/lib/cloud/scripts/common-functions.sh

list_cluster_instance_ids() (
  for attempt in 1 2 3 4 5; do
    if result="$(
      aws ec2 describe-instances \
        --filters \
        "Name=tag:${AUTO_JOIN_TAG_KEY},Values=${AUTO_JOIN_TAG_VALUE}" \
        "Name=instance-state-name,Values=running" \
        --query "Reservations[].Instances[].InstanceId" \
        --output text 2>/dev/null
    )"; then
      printf '%s' "${result}"
      return 0
    fi
    sleep 5
  done

  log_error "Failed to list cluster instances after ${attempt} attempts"
  return 1
)

is_lowest_id_node() (
  all_ids="$(list_cluster_instance_ids)"
  lowest_id="$(printf '%s' "${all_ids}" | tr '\t' '\n' | sort | head -1)"

  [ "${INSTANCE_ID}" = "${lowest_id}" ]
)

wait_for_bootstrap_election() (
  log_info "Waiting for bootstrap node election to complete"

  # 60 attempts x 5s = 5 minutes.
  max_attempts=60
  attempt=0
  while [ "${attempt}" -lt "${max_attempts}" ]; do
    attempt=$((attempt + 1))

    bootstrap_id="$(fetch_parameter "${BOOTSTRAP_NODE_ID_NAME}" 2>/dev/null)" || bootstrap_id=""
    if [ -n "${bootstrap_id}" ] && [ "${bootstrap_id}" != "Uninitialized" ]; then
      log_info "Bootstrap node is ${bootstrap_id}"
      return 0
    fi

    log_info "Bootstrap node not yet elected (attempt ${attempt}/${max_attempts}), waiting"
    sleep 5
  done

  log_error "Timed out after ${max_attempts} attempts waiting for bootstrap election"
  return 1
)

main() {
  cluster_state="$(fetch_parameter "${BOOTSTRAP_CLUSTER_STATE_NAME}" 2>/dev/null)" || cluster_state=""

  if [ "${cluster_state}" = "Ready" ]; then
    log_info "Cluster already initialized, skipping bootstrap election"
    return 0
  fi

  if is_lowest_id_node; then
    log_info "This node (${INSTANCE_ID}) won bootstrap election, publishing to SSM"
    put_parameter "${BOOTSTRAP_NODE_ID_NAME}" "${INSTANCE_ID}"
  else
    wait_for_bootstrap_election
  fi
}

main "${@}"
