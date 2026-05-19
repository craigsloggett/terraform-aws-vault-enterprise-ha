#!/bin/sh
# configure-vault-aws-auth.sh
#
# Enables the Vault AWS IAM auth method and binds the vault-server role to
# the cluster IAM role on the bootstrap node. Followers later use this role
# to authenticate during PKI cert issuance. The vault-server policy is
# written later by configure-vault-pki.sh.Vault resolves policy names
# lazily at token issuance, so binding before policy creation is safe.

set -euf

# shellcheck source=bootstrap.env.tftpl
. /var/lib/cloud/scripts/bootstrap.env
# shellcheck source=SCRIPTDIR/common-functions.sh
. /var/lib/cloud/scripts/common-functions.sh

main() {
  bootstrap_instance_id="$(fetch_parameter "${BOOTSTRAP_INSTANCE_ID_SSM_PARAMETER}")"

  if [ "${INSTANCE_ID}" != "${bootstrap_instance_id}" ]; then
    log_info "Not the bootstrap node, skipping AWS auth configuration"
    return 0
  fi

  log_info "Configuring Vault AWS auth method"

  export VAULT_ADDR="https://127.0.0.1:8200"
  export VAULT_TLS_SERVER_NAME="${VAULT_FQDN}"
  export VAULT_CACERT="/opt/vault/tls/ca.crt"
  VAULT_TOKEN="$(fetch_secret "${ROOT_TOKEN_SECRET_ARN}")"
  export VAULT_TOKEN

  if ! vault auth list -format=json | jq -e '."aws/"' >/dev/null 2>&1; then
    vault auth enable -description="authenticates AWS resources via IAM identity" aws
  fi

  vault write auth/aws/role/vault-server - >/dev/null <<EOF
{
  "auth_type": "iam",
  "bound_iam_principal_arn": "${VAULT_IAM_ROLE_ARN}",
  "policies": "vault-server",
  "max_ttl": "${VAULT_AWS_AUTH_ROLE_MAX_TTL}",
  "ttl": "${VAULT_AWS_AUTH_ROLE_TTL}"
}
EOF
}

main "${@}"
