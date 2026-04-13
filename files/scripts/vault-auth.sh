# shellcheck shell=sh
# vault-auth.sh — AWS auth method and audit device configuration.
#
# This function runs only on the bootstrap node after cluster init.

configure_aws_auth() {
  vault_token="${1}"
  vault_fqdn="${2}"
  vault_tls_ca_file="${3}"
  vault_iam_role_arn="${4}"
  vault_aws_auth_role_max_ttl="${5}"
  vault_aws_auth_role_ttl="${6}"
  vault_audit_log_file="${7}"
  region="${8}"
  ssm_pki_state_name="${9}"

  export VAULT_ADDR="https://127.0.0.1:8200"
  export VAULT_TLS_SERVER_NAME="${vault_fqdn}"
  export VAULT_CACERT="${vault_tls_ca_file}"
  export VAULT_TOKEN="${vault_token}"

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
    --region "${region}" \
    --name "${ssm_pki_state_name}" \
    --value "ready" \
    --overwrite

  log_info "AWS auth method configured"
}
