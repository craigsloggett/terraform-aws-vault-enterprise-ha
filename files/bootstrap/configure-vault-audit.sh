#!/bin/sh
# configure-vault-audit.sh
#
# Enables the Vault file audit device on the bootstrap node so all subsequent
# Vault configuration operations are recorded. Followers no-op. Runs after
# the cluster is initialized and before any auth methods or secrets engines
# are configured.

set -euf

# shellcheck source=/dev/null
. /var/lib/cloud/scripts/bootstrap.env
# shellcheck source=/dev/null
. /var/lib/cloud/scripts/common-functions.sh

readonly VAULT_AUDIT_LOG_FILE="/var/log/vault/vault_audit.log"

main() {
  bootstrap_id="$(fetch_parameter "${BOOTSTRAP_NODE_ID_NAME}")"

  if [ "${INSTANCE_ID}" != "${bootstrap_id}" ]; then
    log_info "Not the bootstrap node, skipping audit device configuration"
    return 0
  fi

  log_info "Configuring Vault file audit device"

  export VAULT_ADDR="https://127.0.0.1:8200"
  export VAULT_TLS_SERVER_NAME="${VAULT_FQDN}"
  export VAULT_CACERT="/opt/vault/tls/ca.crt"
  VAULT_TOKEN="$(fetch_secret "${ROOT_TOKEN_SECRET_ARN}")"
  export VAULT_TOKEN

  if ! vault audit list -format=json | jq -e '."file/"' >/dev/null 2>&1; then
    vault audit enable file file_path="${VAULT_AUDIT_LOG_FILE}"
  fi
}

main "${@}"
