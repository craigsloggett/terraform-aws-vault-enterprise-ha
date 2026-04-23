#!/bin/sh
# wait-for-csr.sh — Terraform external data source program.
# Polls an SSM parameter until a PEM-encoded CSR appears.
#
# Input  (stdin JSON): {"parameter_name": "...", "timeout_sec": "...", "region": "..."}
# Output (stdout JSON): {"csr_pem": "<PEM>"}

log_info() {
  printf '[INFO] wait-for-csr: %s\n' "${1}" >&2
}

log_error() {
  printf '[ERROR] wait-for-csr: %s\n' "${1}" >&2
}

main() {
  set -ef

  input="$(cat)"
  parameter_name="$(printf '%s' "${input}" | jq -r '.parameter_name')"
  timeout_sec="$(printf '%s' "${input}" | jq -r '.timeout_sec')"
  region="$(printf '%s' "${input}" | jq -r '.region')"

  elapsed=0
  interval=5

  while [ "${elapsed}" -lt "${timeout_sec}" ]; do
    csr_pem="$(aws ssm get-parameter \
      --name "${parameter_name}" \
      --region "${region}" \
      --query "Parameter.Value" \
      --output text 2>/dev/null)" || csr_pem=""

    if [ -n "${csr_pem}" ] && printf '%s' "${csr_pem}" | grep -q "BEGIN CERTIFICATE REQUEST"; then
      jq -n --arg csr "${csr_pem}" '{"csr_pem": $csr}'
      return 0
    fi

    log_info "CSR not yet available at ${parameter_name} (${elapsed}s/${timeout_sec}s), waiting"
    sleep "${interval}"
    elapsed=$((elapsed + interval))
  done

  log_error "Timed out after ${timeout_sec}s waiting for CSR at ${parameter_name}"
  return 1
}

main "${@}"
