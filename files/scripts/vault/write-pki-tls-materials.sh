# shellcheck shell=sh
# write-pki-tls-materials.sh — Write PKI-issued TLS materials and state.

get_pki_ca_cert() {
  ssm_pki_ca_cert_name="${1}"

  aws ssm get-parameter \
    --name "${ssm_pki_ca_cert_name}" \
    --query "Parameter.Value" \
    --output text
}

write_pki_ca_cert() {
  vault_tls_ca_file="${1}"
  vault_tls_dir="${2}"
  ssm_pki_ca_cert_name="${3}"

  pki_ca_cert="$(get_pki_ca_cert "${ssm_pki_ca_cert_name}")"

  log_info "Replacing bootstrap CA cert with PKI CA cert on disk"

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

write_pki_ca_cert_to_ssm() {
  ssm_pki_ca_cert_name="${1}"

  log_info "Publishing PKI CA cert to SSM"

  # Publish the new CA cert PEM to SSM so follower nodes can fetch it and
  # trust the new CA before attempting AWS auth. The CA cert is public
  # material, it is the trust anchor, not the signing key.
  ca_cert_pem="$(vault read -field=certificate pki/cert/ca)"
  aws ssm put-parameter \
    --name "${ssm_pki_ca_cert_name}" \
    --value "${ca_cert_pem}" \
    --overwrite

  log_info "PKI CA cert published to SSM"
}

write_pki_state_ready() {
  ssm_pki_state_name="${1}"

  log_info "Writing PKI state: ready"

  aws ssm put-parameter \
    --name "${ssm_pki_state_name}" \
    --value "ready" \
    --overwrite
}
