# shellcheck shell=sh
# logging.sh — Structured log helpers for cloud-init scripts.

log_info() {
  printf '[INFO]  %s\n' "${1}"
}

log_warn() {
  printf '[WARN]  %s\n' "${1}" >&2
}

log_error() {
  printf '[ERROR] %s\n' "${1}" >&2
}
