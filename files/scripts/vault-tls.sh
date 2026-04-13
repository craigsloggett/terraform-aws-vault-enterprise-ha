# shellcheck shell=sh
# vault-tls.sh — Per-node TLS certificate issuance and rotation.

wait_for_pki_ready() {
  region="${1}"
  ssm_pki_state_name="${2}"

  log_info "Waiting for PKI bootstrap to complete"

  for attempt in 1 2 3 4 5 6 7 8 9 10; do
    state="$(aws ssm get-parameter \
      --region "${region}" \
      --name "${ssm_pki_state_name}" \
      --query "Parameter.Value" \
      --output text 2>/dev/null)" || true

    if [ "${state}" = "ready" ]; then
      log_info "PKI bootstrap is ready, proceeding"
      return 0
    fi

    log_info "PKI state is '${state}', retrying in 5 seconds (${attempt}/10)"
    sleep 5
  done

  log_error "Vault PKI was not ready after ${attempt} attempts, failing bootstrap"
  return 1
}

issue_node_cert() {
  vault_token="${1}"
  vault_fqdn="${2}"
  vault_tls_ca_file="${3}"
  region="${4}"
  vault_tls_dir="${5}"
  vault_tls_cert_file="${6}"
  vault_tls_key_file="${7}"
  vault_pki_server_cert_ttl="${8}"
  ssm_pki_ca_cert_name="${9}"

  log_info "Issuing PKI-signed TLS certificate for this node"

  export VAULT_ADDR="https://127.0.0.1:8200"
  export VAULT_TLS_SERVER_NAME="${vault_fqdn}"
  export VAULT_CACERT="${vault_tls_ca_file}"

  # Follower nodes need to fetch the new CA cert from SSM and authenticate
  # via the AWS IAM auth method. The bootstrap node already has a token.
  if [ -n "${vault_token}" ]; then
    export VAULT_TOKEN="${vault_token}"
  else
    log_info "Fetching new PKI CA cert from SSM"
    new_ca_cert="$(aws ssm get-parameter \
      --region "${region}" \
      --name "${ssm_pki_ca_cert_name}" \
      --query "Parameter.Value" \
      --output text)"

    # Write the new PKI CA cert to disk for use by clients connecting
    # to this node after the TLS swap in replace_node_tls(). It is not
    # used for Vault API calls here, this node's listener is still
    # presenting the bootstrap cert until the SIGHUP, so VAULT_CACERT
    # must continue to point at the bootstrap CA.
    new_ca_cert_file="${vault_tls_dir}/pki-ca.crt"
    printf '%s\n' "${new_ca_cert}" >"${new_ca_cert_file}"
    chown vault:vault "${new_ca_cert_file}"
    chmod 0644 "${new_ca_cert_file}"

    log_info "Authenticating via AWS IAM auth method"
    vault_token="$(vault login \
      -format=json \
      -method=aws \
      role=vault-server |
      jq -r '.auth.client_token')"
    export VAULT_TOKEN="${vault_token}"
  fi

  log_info "Requesting certificate from PKI engine"
  cert_json="$(vault write -format=json pki/issue/vault-server \
    common_name="${vault_fqdn}" \
    ttl="${vault_pki_server_cert_ttl}")"

  tmp_cert="${vault_tls_dir}/server.crt.tmp"
  tmp_key="${vault_tls_dir}/server.key.tmp"

  printf '%s\n' "$(printf '%s' "${cert_json}" | jq -r '.data.certificate')" \
    >"${tmp_cert}"
  printf '%s\n' "$(printf '%s' "${cert_json}" | jq -r '.data.private_key')" \
    >"${tmp_key}"

  chown vault:vault "${tmp_cert}" "${tmp_key}"
  chmod 0640 "${tmp_cert}" "${tmp_key}"

  # Atomic move to final paths (vault.hcl already references these).
  mv "${tmp_cert}" "${vault_tls_cert_file}"
  mv "${tmp_key}" "${vault_tls_key_file}"

  log_info "PKI-signed certificate written to ${vault_tls_cert_file}"
}

replace_node_tls() {
  log_info "Reloading Vault TLS listener with PKI-signed certificate"

  systemctl kill -s HUP vault

  log_info "Vault TLS listener reloaded"
}

cleanup_bootstrap_tls() {
  region="${1}"
  vault_tls_ca_file="${2}"
  vault_tls_dir="${3}"
  ssm_pki_ca_cert_name="${4}"

  log_info "Replacing bootstrap CA cert with PKI CA cert on disk"

  # Fetch the PKI CA cert from SSM. This was written by configure_pki_engine()
  # on the bootstrap node and is available to all nodes without a Vault token.
  pki_ca_cert="$(aws ssm get-parameter \
    --region "${region}" \
    --name "${ssm_pki_ca_cert_name}" \
    --query "Parameter.Value" \
    --output text)"

  # Overwrite the bootstrap CA cert at vault_tls_ca_file. vault.hcl references this
  # path for leader_ca_cert_file in the retry_join block, it must now trust
  # the PKI CA, not the bootstrap CA.
  printf '%s\n' "${pki_ca_cert}" >"${vault_tls_ca_file}"
  chown vault:vault "${vault_tls_ca_file}"
  chmod 0644 "${vault_tls_ca_file}"

  log_info "Bootstrap CA cert replaced with PKI CA cert at ${vault_tls_ca_file}"

  # Remove the temporary PKI CA cert file written by the follower path in
  # issue_node_cert(), if present.
  pki_ca_tmp="${vault_tls_dir}/pki-ca.crt"
  if [ -f "${pki_ca_tmp}" ]; then
    rm -f "${pki_ca_tmp}"
    log_info "Removed temporary PKI CA cert file ${pki_ca_tmp}"
  fi
}
