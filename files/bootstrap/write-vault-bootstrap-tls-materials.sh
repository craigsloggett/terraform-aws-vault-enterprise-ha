#!/bin/sh
# write-vault-bootstrap-tls-materials.sh
#
# cloud-init writes the bootstrap CA, server certificate, and private key to
# /opt/vault/tls before this runs. On a replacement node joining a cluster
# whose listeners already serve PKI-signed certificates, the bootstrap CA
# alone is not enough to trust outbound raft TLS to existing nodes. When
# both vault_cluster_state and vault_pki_state are Ready, this script appends
# the PKI CA bundle published to SSM by the bootstrap node so raft join
# succeeds.

set -euf

# shellcheck source=bootstrap.env.tftpl
. /var/lib/cloud/scripts/bootstrap.env
# shellcheck source=SCRIPTDIR/common-functions.sh
. /var/lib/cloud/scripts/common-functions.sh

readonly VAULT_TLS_CA_FILE="/opt/vault/tls/ca.crt"

main() {
  vault_cluster_state="$(fetch_parameter "${BOOTSTRAP_VAULT_CLUSTER_STATE_SSM_PARAMETER_NAME}" 2>/dev/null)" || vault_cluster_state=""
  vault_pki_state="$(fetch_parameter "${BOOTSTRAP_VAULT_PKI_STATE_SSM_PARAMETER_NAME}" 2>/dev/null)" || vault_pki_state=""

  case "${vault_cluster_state}:${vault_pki_state}" in
    Ready:Ready)
      log_info "Appending PKI CA bundle to bootstrap CA file"
      fetch_parameter "${VAULT_PKI_CA_CHAIN_SSM_PARAMETER_NAME}" >>"${VAULT_TLS_CA_FILE}"
      ;;
    Ready:*)
      log_info "Vault cluster Ready but PKI not Ready, keeping bootstrap CA only"
      ;;
    *:Ready)
      log_error "Corrupt SSM state: pki/state=Ready but cluster/state='${vault_cluster_state}'"
      return 1
      ;;
    *)
      log_info "Vault cluster not Ready, keeping bootstrap CA only"
      ;;
  esac
}

main "${@}"
