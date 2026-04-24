#!/bin/sh
set -ef

: "${PARAMETER_NAME:?PARAMETER_NAME is required}"
: "${TIMEOUT_SEC:?TIMEOUT_SEC is required}"
: "${REGION:?REGION is required}"

interval=10
elapsed=0

while [ "${elapsed}" -lt "${TIMEOUT_SEC}" ]; do
  value="$(aws ssm get-parameter \
    --name "${PARAMETER_NAME}" \
    --region "${REGION}" \
    --query 'Parameter.Value' \
    --output text 2>/dev/null)" || value=""

  case "${value}" in
    "" | Uninitialized)
      printf 'Waiting for CSR at %s (%ss elapsed)...\n' "${PARAMETER_NAME}" "${elapsed}" >&2
      sleep "${interval}"
      elapsed=$((elapsed + interval))
      ;;
    *)
      printf 'CSR available at %s\n' "${PARAMETER_NAME}" >&2
      exit 0
      ;;
  esac
done

printf 'Timed out after %ss waiting for CSR at %s\n' "${TIMEOUT_SEC}" "${PARAMETER_NAME}" >&2
exit 1
