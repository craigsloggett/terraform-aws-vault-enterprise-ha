#!/bin/sh
# configure-snapshots.sh
#
# Configures automated Raft snapshots on the bootstrap node. Followers no-op
# based on the role published to SSM by determine-vault-node-role.sh.

set -euf

# shellcheck source=/dev/null
. /var/lib/cloud/scripts/bootstrap.env
# shellcheck source=/dev/null
. /var/lib/cloud/scripts/common-functions.sh

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

main() {
  bootstrap_id="$(fetch_parameter "${BOOTSTRAP_NODE_ID_NAME}")"
  instance_id="$(get_instance_id)"

  if [ "${instance_id}" != "${bootstrap_id}" ]; then
    log_info "Not the bootstrap node, skipping snapshot configuration"
    return 0
  fi

  log_info "Configuring automated Raft snapshots"

  export VAULT_ADDR="https://127.0.0.1:8200"
  export VAULT_TLS_SERVER_NAME="${VAULT_FQDN}"
  export VAULT_CACERT="/opt/vault/tls/ca.crt"
  VAULT_TOKEN="$(fetch_secret "${ROOT_TOKEN_SECRET_ARN}")"
  export VAULT_TOKEN

  vault write sys/storage/raft/snapshot-auto/config/hourly \
    @/etc/vault.d/snapshot.json \
    >/dev/null
}

main "${@}"
