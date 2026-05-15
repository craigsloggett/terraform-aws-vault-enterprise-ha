#!/bin/sh
# configure-vault-jwt-auth.sh
#
# Configures the Vault JWT auth method for HCP Terraform workspace identity
# on the bootstrap node. Writes the admin policy, enables and configures
# the JWT auth method, and binds the admin role. Skipped when no HCP
# Terraform organization name is set. Followers no-op. Runs before PKI
# configuration so pki_state=Ready signals that every bootstrap-only
# operation has completed and downstream HCP TF workflows can authenticate
# immediately after terraform apply.

set -euf

# shellcheck source=bootstrap.env.tftpl
. /var/lib/cloud/scripts/bootstrap.env
# shellcheck source=SCRIPTDIR/common-functions.sh
. /var/lib/cloud/scripts/common-functions.sh

readonly VAULT_POLICY_DIR="/etc/vault.d/policies"

TMPDIR_SESSION="$(mktemp -d)"
readonly TMPDIR_SESSION
trap 'rm -rf "${TMPDIR_SESSION}"' EXIT INT TERM HUP

enable_jwt_auth_method() (
  log_info "Enabling Vault JWT auth method"

  if ! vault auth list -format=json | jq -e ".\"${VAULT_AUTH_JWT_HCP_TERRAFORM_MOUNT_PATH}/\"" >/dev/null 2>&1; then
    vault auth enable -path="${VAULT_AUTH_JWT_HCP_TERRAFORM_MOUNT_PATH}" -description="authenticates HCP Terraform workspace runs via workload identity" jwt
  fi
)

write_jwt_auth_config() (
  # $@ is an optional extra argument: "oidc_discovery_ca_pem=@..."
  vault write "auth/${VAULT_AUTH_JWT_HCP_TERRAFORM_MOUNT_PATH}/config" \
    "oidc_discovery_url=https://${VAULT_AUTH_JWT_HCP_TERRAFORM_HOSTNAME}" \
    "bound_issuer=https://${VAULT_AUTH_JWT_HCP_TERRAFORM_HOSTNAME}" \
    "${@}" \
    >/dev/null
)

configure_jwt_auth_method() (
  log_info "Configuring JWT auth method for HCP Terraform"

  # Handle the case when HCP Terraform Enterprise (TFE) uses a custom
  # or self-signed CA certificate.
  if [ -n "${VAULT_AUTH_JWT_HCP_TERRAFORM_OIDC_DISCOVERY_CA_PEM:-}" ]; then
    oidc_discovery_ca_pem="${TMPDIR_SESSION}/jwt_oidc_discovery_ca.pem"
    printf '%s' "${VAULT_AUTH_JWT_HCP_TERRAFORM_OIDC_DISCOVERY_CA_PEM}" >"${oidc_discovery_ca_pem}"
    write_jwt_auth_config "oidc_discovery_ca_pem=@${oidc_discovery_ca_pem}"
  else
    write_jwt_auth_config
  fi
)

bind_admin_jwt_role() (
  log_info "Binding ${VAULT_AUTH_JWT_HCP_TERRAFORM_ROLE_NAME} JWT role"

  bound_claims="\"terraform_organization_name\": \"${VAULT_AUTH_JWT_HCP_TERRAFORM_ORGANIZATION_NAME}\""
  if [ -n "${VAULT_AUTH_JWT_HCP_TERRAFORM_WORKSPACE_ID}" ]; then
    bound_claims="${bound_claims}, \"terraform_workspace_id\": \"${VAULT_AUTH_JWT_HCP_TERRAFORM_WORKSPACE_ID}\""
    log_info "Scoping JWT role to workspace ${VAULT_AUTH_JWT_HCP_TERRAFORM_WORKSPACE_ID}"
  else
    log_info "Scoping JWT role to organization ${VAULT_AUTH_JWT_HCP_TERRAFORM_ORGANIZATION_NAME} (all workspaces)"
  fi

  vault write "auth/${VAULT_AUTH_JWT_HCP_TERRAFORM_MOUNT_PATH}/role/${VAULT_AUTH_JWT_HCP_TERRAFORM_ROLE_NAME}" - >/dev/null <<EOF
{
  "role_type": "jwt",
  "bound_audiences": "vault.workload.identity",
  "bound_claims_type": "string",
  "bound_claims": { ${bound_claims} },
  "user_claim": "sub",
  "policies": "admin",
  "token_type": "service",
  "ttl": "${VAULT_AUTH_JWT_ROLE_TTL}",
  "max_ttl": "${VAULT_AUTH_JWT_ROLE_MAX_TTL}"
}
EOF
)

main() {
  bootstrap_instance_id="$(fetch_parameter "${BOOTSTRAP_INSTANCE_ID_SSM_PARAMETER}")"

  if [ "${INSTANCE_ID}" != "${bootstrap_instance_id}" ]; then
    log_info "Not the bootstrap node, skipping JWT auth configuration"
    return 0
  fi

  if [ -z "${VAULT_AUTH_JWT_HCP_TERRAFORM_ORGANIZATION_NAME}" ]; then
    log_info "HCP Terraform organization name not set, skipping JWT auth configuration"
    return 0
  fi

  log_info "Configuring Vault JWT auth method for HCP Terraform"

  export VAULT_ADDR="https://127.0.0.1:8200"
  export VAULT_TLS_SERVER_NAME="${VAULT_FQDN}"
  export VAULT_CACERT="/opt/vault/tls/ca.crt"
  VAULT_TOKEN="$(fetch_secret "${ROOT_TOKEN_SECRET_ARN}")"
  export VAULT_TOKEN

  vault policy write admin "${VAULT_POLICY_DIR}/admin.hcl"

  enable_jwt_auth_method
  configure_jwt_auth_method
  bind_admin_jwt_role
}

main "${@}"
