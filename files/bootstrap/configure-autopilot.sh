#!/bin/sh
# configure-autopilot.sh
#
# Configures Raft Autopilot on the bootstrap node. Followers no-op based on
# the role published to SSM by determine-vault-node-role.sh.

set -euf

# shellcheck source=bootstrap.env.tftpl
. /var/lib/cloud/scripts/bootstrap.env
# shellcheck source=SCRIPTDIR/common-functions.sh
. /var/lib/cloud/scripts/common-functions.sh

main() {
  bootstrap_instance_id="$(fetch_parameter "${BOOTSTRAP_INSTANCE_ID_SSM_PARAMETER}")"

  if [ "${INSTANCE_ID}" != "${bootstrap_instance_id}" ]; then
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
