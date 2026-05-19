#!/bin/sh
# configure-snapshots.sh
#
# Configures automated Raft snapshots on the bootstrap node. Followers no-op
# based on the role published to SSM by determine-vault-node-role.sh.

set -euf

# shellcheck source=bootstrap.env.tftpl
. /var/lib/cloud/scripts/bootstrap.env
# shellcheck source=SCRIPTDIR/common-functions.sh
. /var/lib/cloud/scripts/common-functions.sh

main() {
  bootstrap_instance_id="$(fetch_parameter "${BOOTSTRAP_INSTANCE_ID_SSM_PARAMETER}")"

  if [ "${INSTANCE_ID}" != "${bootstrap_instance_id}" ]; then
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
