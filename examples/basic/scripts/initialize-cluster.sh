#!/bin/sh
# Usage: ./initialize-cluster.sh

log() {
  printf '%b%s %b%s%b %s\n' \
    "${c1}" "${3:-->}" "${c3}${2:+$c2}" "$1" "${c3}" "$2" >&2
}

read_terraform_outputs() {
  log "Reading Terraform outputs."

  bastion_ip=$(terraform output -raw bastion_public_ip)
  vault_ip=$(terraform output -json vault_private_ips | jq -r '.[0]')
  vault_ca_cert=$(terraform output -raw vault_ca_cert)
  ami_name=$(terraform output -raw ec2_ami_name)

  case "${ami_name}" in
    *ubuntu*) ssh_user="ubuntu" ;;
    *debian*) ssh_user="admin" ;;
    *)
      log "ERROR: Unsupported AMI:" "${ami_name}"
      exit 1
      ;;
  esac

  log "  Bastion IP:" "${bastion_ip}"
  log "  Vault node:" "${vault_ip}"
  log "  SSH user:" "${ssh_user}"
}

setup_tunnel() {
  log "Opening SSH tunnel to ${vault_ip}:8200."

  ca_cert_file=$(mktemp)
  ssh_socket=$(mktemp -u)
  printf '%s\n' "${vault_ca_cert}" >"${ca_cert_file}"

  # shellcheck disable=SC2086
  ssh ${ssh_opts} -f -N -M -S "${ssh_socket}" \
    -L 8200:"${vault_ip}":8200 "${ssh_user}@${bastion_ip}"

  export VAULT_ADDR="https://127.0.0.1:8200"
  export VAULT_CACERT="${ca_cert_file}"
}

cleanup() {
  rm -f "${ca_cert_file}"
  ssh -S "${ssh_socket}" -O exit x 2>/dev/null
}

wait_for_vault() {
  log "Waiting for Vault to be reachable."

  attempts=0
  max_attempts=30
  while ! curl -sf --cacert "${ca_cert_file}" \
    "${VAULT_ADDR}/v1/sys/health?uninitcode=200&sealedcode=200" >/dev/null 2>&1; do
    attempts=$((attempts + 1))
    if [ "${attempts}" -ge "${max_attempts}" ]; then
      log "ERROR: Vault not reachable after ${max_attempts} attempts."
      exit 1
    fi
    sleep 2
  done

  log "Vault is reachable."
}

initialize_vault() {
  # Check if Vault is already initialized.
  if vault status -format=json 2>/dev/null | jq -e '.initialized == true' >/dev/null 2>&1; then
    log "Vault is already initialized."
    vault status
    return
  fi

  log "Initializing Vault cluster."

  init_file="vault-init.json"
  vault operator init -format=json >"${init_file}"
  cat "${init_file}"

  log "Initialization complete."
  log "IMPORTANT: The root token and recovery keys have been saved to ${init_file}." "" "!!"
  log "           Store this file securely and delete it from disk." "" "  "
}

configure_snapshots() {
  log "Configuring automated Raft snapshots."

  export VAULT_TOKEN
  VAULT_TOKEN=$(jq -r '.root_token' vault-init.json)

  # Fetch the snapshot config from the Vault node and apply it via the tunnel.
  # Accept the bastion host key if not already known.
  if ! ssh-keygen -F "${bastion_ip}" >/dev/null 2>&1; then
    ssh-keyscan -H "${bastion_ip}" >>~/.ssh/known_hosts 2>/dev/null
  fi

  # shellcheck disable=SC2086
  ssh ${ssh_opts} -J "${ssh_user}@${bastion_ip}" "${ssh_user}@${vault_ip}" \
    "sudo cat /etc/vault.d/snapshot.json" |
    vault write sys/storage/raft/snapshot-auto/config/hourly -

  log "  Automated snapshots configured."
}

wait_for_unseal() {
  # The tunnel targets a single node which may be a standby, not the leader.
  # The unsealed check is still valid; vault status at the end may show
  # HA Mode: standby rather than active, which is expected.
  log "Waiting for Vault to become active."

  attempts=0
  max_attempts=30
  while ! vault status -format=json 2>/dev/null | jq -e '.sealed == false' >/dev/null 2>&1; do
    attempts=$((attempts + 1))
    if [ "${attempts}" -ge "${max_attempts}" ]; then
      log "ERROR: Vault did not unseal within ${max_attempts} attempts."
      exit 1
    fi
    sleep 2
  done

  vault status
}

main() {
  set -ef

  ssh_opts="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o LogLevel=ERROR"

  # Colors are automatically disabled if output is not a terminal.
  ! [ -t 2 ] || {
    c1='\033[1;33m'
    c2='\033[1;34m'
    c3='\033[m'
  }

  read_terraform_outputs
  trap cleanup EXIT
  setup_tunnel
  wait_for_vault
  initialize_vault
  wait_for_unseal
  configure_snapshots
}

main "$@"
