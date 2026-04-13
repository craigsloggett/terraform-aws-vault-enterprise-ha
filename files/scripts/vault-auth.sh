# shellcheck shell=sh
# vault-auth.sh — AWS auth method and audit device configuration.
#
# This function runs only on the bootstrap node after cluster init.

configure_aws_auth() {
  vault_iam_role_arn="${1}"
  vault_aws_auth_role_max_ttl="${2}"
  vault_aws_auth_role_ttl="${3}"
  vault_audit_log_file="${4}"
  ssm_pki_state_name="${5}"

  log_info "Configuring Vault AWS auth method"

  # Enable the AWS auth method if not already enabled.
  if ! vault auth list -format=json | jq -e '."aws/"' >/dev/null 2>&1; then
    vault auth enable aws
  fi

  # Write a policy granting nodes the ability to issue certs from the
  # vault-server PKI role. No broader permissions are needed.
  vault policy write vault-server - <<EOF
path "pki/issue/vault-server" {
  capabilities = ["create", "update"]
}
EOF

  # Bind the Vault instance IAM role to the vault-server policy.
  # Nodes authenticate by signing a GetCallerIdentity request with their
  # instance profile credentials, no shared secrets.
  vault write auth/aws/role/vault-server \
    auth_type=iam \
    bound_iam_principal_arn="${vault_iam_role_arn}" \
    policies=vault-server \
    max_ttl="${vault_aws_auth_role_max_ttl}" \
    ttl="${vault_aws_auth_role_ttl}"

  # Enable the file audit device. /var/log/vault is on a dedicated EBS volume
  # (see prepare_disk in main) to isolate audit log IO and growth from the
  # root filesystem.
  if ! vault audit list -format=json | jq -e '."file/"' >/dev/null 2>&1; then
    vault audit enable file file_path="${vault_audit_log_file}"
  fi

  log_info "Writing PKI state: ready"
  aws ssm put-parameter \
    --name "${ssm_pki_state_name}" \
    --value "ready" \
    --overwrite

  log_info "AWS auth method configured"
}
