#!/bin/sh
# start-vault.sh
#
# Starts the local Vault systemd unit and waits for the local API to begin
# responding. Runs on every node after the Vault binary, license, TLS
# materials, and configuration files are in place.

set -euf

# shellcheck source=SCRIPTDIR/common-functions.sh
. /var/lib/cloud/scripts/common-functions.sh

start_vault() (
  log_info "Starting Vault"

  systemctl daemon-reload
  systemctl enable --now vault
)

wait_for_vault_api() (
  log_info "Waiting for the Vault API to be ready"

  for attempt in 1 2 3 4 5 6 7 8 9 10; do
    status="$(
      curl -sk -o /dev/null -w '%{http_code}' \
        "https://127.0.0.1:8200/v1/sys/health" 2>/dev/null
    )" || true

    if [ "${status}" != "000" ]; then
      return 0
    fi
    sleep 5
  done

  log_error "Vault API did not respond after ${attempt} attempts"
  return 1
)

main() {
  start_vault
  wait_for_vault_api
}

main "${@}"
