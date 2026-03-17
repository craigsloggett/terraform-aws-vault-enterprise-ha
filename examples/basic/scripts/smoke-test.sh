#!/usr/bin/env bash
# Usage: VAULT_TOKEN=$(jq -r '.root_token' vault-init.json) ./smoke-test.sh
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
export VAULT_TOKEN="${VAULT_TOKEN:?Set VAULT_TOKEN before running this script.}"

# Wait for Vault to be reachable through the tunnel.
echo "Waiting for Vault to be reachable..."
ATTEMPTS=0
MAX_ATTEMPTS=30
while ! curl -sf --cacert "${CA_CERT_FILE}" "${VAULT_ADDR}/v1/sys/health?sealedcode=200" >/dev/null 2>&1; do
  ATTEMPTS=$((ATTEMPTS + 1))
  if [ "${ATTEMPTS}" -ge "${MAX_ATTEMPTS}" ]; then
    echo "ERROR: Vault not reachable after ${MAX_ATTEMPTS} attempts."
    exit 1
  fi
  sleep 2
done

echo "Vault is reachable."
echo ""

# Cluster health.
echo "=== Vault Status ==="
vault status
echo ""

echo "=== Raft Peers ==="
vault operator raft list-peers
echo ""

# Secrets engine smoke test.
echo "=== Secrets Engine: KV ==="
vault secrets enable -path=kv-smoke -version=2 kv
vault kv put kv-smoke/test message="smoke test"
vault kv get kv-smoke/test
vault secrets disable kv-smoke
echo "KV smoke test passed."
echo ""

# Auth method smoke test.
echo "=== Auth Method: AppRole ==="
vault auth enable -path=approle-smoke approle
vault auth disable approle-smoke
echo "AppRole smoke test passed."
echo ""

# License check.
echo "=== License ==="
vault read -format=json sys/license/status | jq '{license_id: .data.autoloaded.license_id, expiration: .data.autoloaded.expiration_time}'
echo ""

echo "=== All smoke tests passed ==="
