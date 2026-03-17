#!/usr/bin/env bash
# Usage: ./initialize-cluster.sh
set -euo pipefail

echo "=== Reading Terraform outputs ==="
BASTION_IP=$(terraform output -raw bastion_public_ip)
VAULT_IP=$(terraform output -json vault_private_ips | jq -r '.[0]')
VAULT_CA_CERT=$(terraform output -raw vault_ca_cert)

echo "Bastion IP: ${BASTION_IP}"
echo "Vault node: ${VAULT_IP}"
echo ""

SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o LogLevel=ERROR"

# Write CA cert to a temporary file for the Vault CLI.
CA_CERT_FILE=$(mktemp)
SSH_SOCKET=$(mktemp -u)
cleanup() {
  rm -f "${CA_CERT_FILE}"
  ssh -S "${SSH_SOCKET}" -O exit x 2>/dev/null
}
trap cleanup EXIT
printf '%s\n' "${VAULT_CA_CERT}" >"${CA_CERT_FILE}"

# Open an SSH tunnel to the first Vault node through the bastion.
echo "=== Opening SSH tunnel to ${VAULT_IP}:8200 ==="
# shellcheck disable=SC2086
ssh ${SSH_OPTS} -f -N -M -S "${SSH_SOCKET}" -L 8200:"${VAULT_IP}":8200 "ubuntu@${BASTION_IP}"

export VAULT_ADDR="https://127.0.0.1:8200"
export VAULT_CACERT="${CA_CERT_FILE}"

# Wait for Vault to be reachable through the tunnel.
echo "Waiting for Vault to be reachable..."
ATTEMPTS=0
MAX_ATTEMPTS=30
while ! curl -sf --cacert "${CA_CERT_FILE}" "${VAULT_ADDR}/v1/sys/health?uninitcode=200&sealedcode=200" >/dev/null 2>&1; do
  ATTEMPTS=$((ATTEMPTS + 1))
  if [ "${ATTEMPTS}" -ge "${MAX_ATTEMPTS}" ]; then
    echo "ERROR: Vault not reachable after ${MAX_ATTEMPTS} attempts."
    exit 1
  fi
  sleep 2
done

echo "Vault is reachable."
echo ""

# Check if Vault is already initialized.
if vault status -format=json 2>/dev/null | jq -e '.initialized == true' >/dev/null 2>&1; then
  echo "Vault is already initialized."
  vault status
  exit 0
fi

# Initialize the cluster.
echo "=== Initializing Vault cluster ==="
INIT_FILE="vault-init.json"
vault operator init -format=json | tee "${INIT_FILE}"

echo ""
echo "=== Initialization complete ==="
echo ""
echo "IMPORTANT: The root token and recovery keys have been saved to ${INIT_FILE}."
echo "           Store this file securely and delete it from disk."
echo ""

# Wait for Vault to become active after initialization.
echo "Waiting for Vault to become active..."
ATTEMPTS=0
MAX_ATTEMPTS=30
while ! vault status -format=json 2>/dev/null | jq -e '.sealed == false' >/dev/null 2>&1; do
  ATTEMPTS=$((ATTEMPTS + 1))
  if [ "${ATTEMPTS}" -ge "${MAX_ATTEMPTS}" ]; then
    echo "WARNING: Vault did not unseal within ${MAX_ATTEMPTS} attempts."
    exit 1
  fi
  sleep 2
done

echo ""
vault status
