# shellcheck shell=sh
# user.sh — Vault system user configuration.

create_vault_user() {
  vault_home_dir="${1}"

  log_info "Creating vault system user"

  if ! getent group vault >/dev/null 2>&1; then
    groupadd --system vault
  fi

  if ! id vault >/dev/null 2>&1; then
    useradd --system -g vault -d "${vault_home_dir}" -s /bin/false vault
  fi
}
