# shellcheck shell=sh
# common-functions.sh
#
# Shared shell helpers for the bootstrap scripts. Sourced (not executed) by
# scripts in /var/lib/cloud/scripts/. No shebang since this file is never
# run directly.

log_info() (
  printf '[INFO]  %s\n' "${1}" >&2
)

log_warn() (
  printf '[WARN]  %s\n' "${1}" >&2
)

log_error() (
  printf '[ERROR] %s\n' "${1}" >&2
)

fetch_parameter() (
  aws ssm get-parameter \
    --name "${1}" \
    --query "Parameter.Value" \
    --output text
)

put_parameter() (
  aws ssm put-parameter \
    --name "${1}" \
    --value "${2}" \
    --type String \
    --overwrite \
    >/dev/null
)

fetch_secret() (
  for attempt in 1 2 3 4 5; do
    if result="$(aws secretsmanager get-secret-value \
      --secret-id "${1}" \
      --query SecretString --output text 2>/dev/null)"; then
      printf '%s' "${result}"
      return 0
    fi
    sleep 5
  done

  log_error "Failed to retrieve secret after ${attempt} attempts"
  return 1
)

put_secret() (
  aws secretsmanager put-secret-value \
    --secret-id "${1}" \
    --secret-string "${2}" \
    >/dev/null
)
