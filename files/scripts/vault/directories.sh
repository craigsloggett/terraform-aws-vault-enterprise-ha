# shellcheck shell=sh
# directories.sh — Vault directory tree configuration.

configure_vault_directories() {
  vault_home_dir="${1}"
  vault_data_dir="${2}"
  vault_config_dir="${3}"
  vault_log_dir="${4}"
  vault_libexec_dir="${5}"
  vault_tls_dir="${6}"
  vault_raft_dir="${7}"
  vault_agent_template_dir="${8}"

  log_info "Configuring Vault directory tree"

  mkdir -p "${vault_home_dir}"
  chown vault:vault "${vault_home_dir}"
  chmod 755 "${vault_home_dir}"

  mkdir -p "${vault_data_dir}"
  chown vault:vault "${vault_data_dir}"
  chmod 755 "${vault_data_dir}"

  mkdir -p "${vault_config_dir}"
  chown root:vault "${vault_config_dir}"
  chmod 755 "${vault_config_dir}"

  mkdir -p "${vault_log_dir}"
  chown vault:vault "${vault_log_dir}"
  chmod 755 "${vault_log_dir}"

  mkdir -p "${vault_libexec_dir}"
  chown root:root "${vault_libexec_dir}"
  chmod 755 "${vault_libexec_dir}"

  mkdir -p "${vault_tls_dir}"
  chown vault:vault "${vault_tls_dir}"
  chmod 755 "${vault_tls_dir}"

  mkdir -p "${vault_raft_dir}"
  chown vault:vault "${vault_raft_dir}"
  chmod 700 "${vault_raft_dir}"

  mkdir -p "${vault_agent_template_dir}"
  chown vault:vault "${vault_agent_template_dir}"
  chmod 755 "${vault_agent_template_dir}"
}
