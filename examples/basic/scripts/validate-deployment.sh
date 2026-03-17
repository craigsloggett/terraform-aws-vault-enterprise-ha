#!/usr/bin/env bash
# Usage: ./validate-deployment.sh us-east-1
set -euo pipefail

REGION="${1:?Usage: $0 <region>}"

echo "=== Reading Terraform outputs ==="
BASTION_IP=$(terraform output -raw bastion_public_ip)
VAULT_URL=$(terraform output -raw vault_url)
VAULT_IPS=$(terraform output -json vault_private_ips | jq -r '.[]')

echo "Bastion IP:  ${BASTION_IP}"
echo "Vault URL:   ${VAULT_URL}"
echo "Vault nodes: $(echo "${VAULT_IPS}" | tr '\n' ' ')"
echo ""

echo "=== Phase 1: Infrastructure checks ==="

echo "Checking NLB target group health..."
TG_ARN=$(terraform output -raw vault_target_group_arn)
aws elbv2 describe-target-health \
  --region "${REGION}" \
  --target-group-arn "${TG_ARN}" \
  --query 'TargetHealthDescriptions[].{Target:Target.Id,Health:TargetHealth.State,Reason:TargetHealth.Reason}' \
  --output table
echo ""

echo "=== Phase 2: Node validation (via bastion) ==="
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o BatchMode=yes -o LogLevel=ERROR"

for ip in ${VAULT_IPS}; do
  echo "--- Checking vault node ${ip} ---"

  # shellcheck disable=SC2029,SC2086
  ssh ${SSH_OPTS} -o "ProxyCommand ssh ${SSH_OPTS} -W %h:%p ubuntu@${BASTION_IP}" "ubuntu@${ip}" bash -s <<'REMOTE'
    echo "Cloud-init status: $(cloud-init status 2>/dev/null || echo 'unknown')"

    echo -n "EBS volume mounted: "
    if mountpoint -q /opt/vault/data; then echo "yes"; else echo "NO"; fi

    echo -n "Vault binary: "
    if command -v vault >/dev/null 2>&1; then vault version; else echo "NOT FOUND"; fi

    echo -n "TLS CA cert: "
    if sudo test -f /opt/vault/tls/ca.crt; then echo "present"; else echo "MISSING"; fi

    echo -n "TLS server cert: "
    if sudo test -f /opt/vault/tls/server.crt; then echo "present"; else echo "MISSING"; fi

    echo -n "TLS server key: "
    if sudo test -f /opt/vault/tls/server.key; then echo "present"; else echo "MISSING"; fi

    echo -n "Vault config: "
    if [ -f /etc/vault.d/vault.hcl ]; then echo "present"; else echo "MISSING"; fi

    echo -n "Vault license: "
    if [ -f /opt/vault/vault.hclic ]; then echo "present"; else echo "MISSING"; fi

    echo -n "Vault service enabled: "
    if systemctl is-enabled vault >/dev/null 2>&1; then echo "yes"; else echo "NO"; fi

    echo -n "Vault service running: "
    if systemctl is-active vault >/dev/null 2>&1; then echo "yes"; else echo "no"; fi
REMOTE
  echo ""
done

echo "=== Validation complete ==="
echo ""
echo "Next steps to bring up the cluster:"
echo "  1. SSH to each node via: ssh -J ubuntu@${BASTION_IP} ubuntu@<vault-ip>"
echo "  2. Start Vault:          sudo systemctl start vault"
echo "  3. Initialize (one node): export VAULT_CACERT=/opt/vault/tls/ca.crt"
echo "                            vault operator init"
echo "  4. Other nodes will auto-join via Raft and auto-unseal via KMS"
