#!/bin/sh
# write-vault-license.sh
#
# Fetches the Vault Enterprise license from Secrets Manager and writes it
# to /opt/vault/vault.hclic. Runs on every node before vault.service starts.

set -euf

# shellcheck source=/dev/null
. /var/lib/cloud/scripts/bootstrap.env
# shellcheck source=/dev/null
. /var/lib/cloud/scripts/common-functions.sh

main() {
  log_info "Writing the Vault license"

  vault_license="$(fetch_secret "${LICENSE_SECRET_ARN}")"
  printf '%s\n' "${vault_license}" >/opt/vault/vault.hclic
  chown vault:vault /opt/vault/vault.hclic
  chmod 0640 /opt/vault/vault.hclic
}

main "${@}"
