#!/bin/sh
# configure-autopilot.sh
#
# Configures Raft Autopilot on the bootstrap node. Followers no-op based on
# the role published to SSM by determine-vault-node-role.sh.

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

fetch_secret() (
  for attempt in 1 2 3 4 5; do
    if result="$(aws secretsmanager get-secret-value \
      --secret-id "${1}" \
      --query SecretString --output text 2>/dev/null)"; then
      printf '%s' "${result}"
      return 0
    fi
    sleep 5
  done

  log_error "Failed to retrieve secret after ${attempt} attempts"
  return 1
)

main() {
  bootstrap_id="$(fetch_parameter "${BOOTSTRAP_NODE_ID_NAME}")"
  instance_id="$(get_instance_id)"

  if [ "${instance_id}" != "${bootstrap_id}" ]; then
    log_info "Not the bootstrap node, skipping autopilot configuration"
    return 0
  fi

  log_info "Configuring Raft Autopilot"

  export VAULT_ADDR="https://127.0.0.1:8200"
  export VAULT_TLS_SERVER_NAME="${VAULT_FQDN}"
  export VAULT_CACERT="/opt/vault/tls/ca.crt"
  VAULT_TOKEN="$(fetch_secret "${ROOT_TOKEN_SECRET_ARN}")"
  export VAULT_TOKEN

  vault operator raft autopilot set-config \
    -cleanup-dead-servers="${VAULT_AUTOPILOT_CLEANUP_DEAD_SERVERS}" \
    -dead-server-last-contact-threshold="${VAULT_AUTOPILOT_DEAD_SERVER_LAST_CONTACT_THRESHOLD}" \
    -min-quorum="${VAULT_AUTOPILOT_MIN_QUORUM}"
}

main "${@}"
