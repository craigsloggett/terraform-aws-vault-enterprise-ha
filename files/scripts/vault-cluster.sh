# shellcheck shell=sh
# vault-cluster.sh — Cluster initialization, join, and Raft membership.

is_bootstrap_node() {
  instance_id="${1}"
  region="${2}"
  cluster_tag_key="${3}"
  cluster_tag_value="${4}"

  log_info "Performing bootstrap node election"

  # Fetch all running instance IDs in this cluster by tag.
  all_ids="$(aws ec2 describe-instances \
    --region "${region}" \
    --filters \
    "Name=tag:${cluster_tag_key},Values=${cluster_tag_value}" \
    "Name=instance-state-name,Values=running" \
    --query "Reservations[].Instances[].InstanceId" \
    --output text)"

  # The --output text format returns tab-separated values on one line.
  # tr converts tabs to newlines before sort.
  lowest_id="$(printf '%s' "${all_ids}" | tr '\t' '\n' | sort | head -1)"

  log_info "Own instance ID: ${instance_id} (lowest in cluster: ${lowest_id})"

  if [ "${instance_id}" = "${lowest_id}" ]; then
    log_info "This node is the bootstrap node"
    return 0
  fi

  log_info "This node is a follower"
  return 1
}

init_cluster() {
  vault_fqdn="${1}"
  vault_tls_ca_file="${2}"
  region="${3}"
  vault_bootstrap_root_token_secret_arn="${4}"
  vault_recovery_keys_secret_arn="${5}"
  ssm_cluster_state_name="${6}"

  log_info "Initializing Vault cluster"

  export VAULT_ADDR="https://127.0.0.1:8200"
  export VAULT_TLS_SERVER_NAME="${vault_fqdn}"
  export VAULT_CACERT="${vault_tls_ca_file}"

  # Idempotency guard: if the cluster is already initialized (e.g. this is a
  # replacement node that happens to have the lowest instance ID), skip init.
  initialized="$(vault status -format=json 2>/dev/null |
    jq -r '.initialized' 2>/dev/null)" || true
  if [ "${initialized}" = "true" ]; then
    log_info "Cluster is already initialized, skipping operator init"
    return 0
  fi

  log_info "Running vault operator init"
  # KMS auto-unseal is configured, so recovery shares/threshold are used
  # in place of unseal shares/threshold.
  init_output="$(vault operator init \
    -format=json \
    -recovery-shares=5 \
    -recovery-threshold=3)"

  root_token="$(printf '%s' "${init_output}" | jq -r '.root_token')"
  recovery_keys="$(printf '%s' "${init_output}" | jq -c '.recovery_keys_b64')"

  log_info "Storing bootstrap root token in Secrets Manager"
  aws secretsmanager put-secret-value \
    --region "${region}" \
    --secret-id "${vault_bootstrap_root_token_secret_arn}" \
    --secret-string "${root_token}"

  log_info "Storing recovery keys in Secrets Manager"
  aws secretsmanager put-secret-value \
    --region "${region}" \
    --secret-id "${vault_recovery_keys_secret_arn}" \
    --secret-string "${recovery_keys}"

  log_info "Writing cluster state: ready"
  aws ssm put-parameter \
    --region "${region}" \
    --name "${ssm_cluster_state_name}" \
    --value "ready" \
    --overwrite

  log_info "Cluster initialization complete"
}

join_cluster() {
  region="${1}"
  ssm_cluster_state_name="${2}"

  log_info "Waiting for cluster initialization to complete"

  for attempt in 1 2 3 4 5 6 7 8 9 10; do
    state="$(aws ssm get-parameter \
      --region "${region}" \
      --name "${ssm_cluster_state_name}" \
      --query "Parameter.Value" \
      --output text 2>/dev/null)" || true

    if [ "${state}" = "ready" ]; then
      return 0
    fi

    log_info "Cluster state is '${state}', retrying in 5 seconds (${attempt}/10)"
    sleep 5
  done

  log_error "Unable to join the Vault cluster after ${attempt} attempts, failing bootstrap"
  return 1
}
