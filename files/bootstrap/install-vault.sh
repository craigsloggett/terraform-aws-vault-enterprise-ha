#!/bin/sh
# install-vault.sh
#
# Downloads, GPG-verifies, SHA256-verifies, and installs the Vault Enterprise
# binary at /usr/bin/vault. Runs on every node before the cluster bootstrap.

set -euf

# shellcheck source=/dev/null
. /var/lib/cloud/scripts/bootstrap.env
# shellcheck source=/dev/null
. /var/lib/cloud/scripts/common-functions.sh

log_error() (
  printf '[ERROR] %s\n' "${1}" >&2
)

detect_system_architecture() (
  machine="$(uname -m)"
  case "${machine}" in
    x86_64) printf 'amd64' ;;
    aarch64) printf 'arm64' ;;
    *)
      log_error "Unsupported architecture: ${machine}"
      return 1
      ;;
  esac
)

download_and_verify_vault() (
  version="${1}"
  arch="${2}"
  tmp_dir="${3}"

  base_url="https://releases.hashicorp.com/vault/${version}"
  zip_file="vault_${version}_linux_${arch}.zip"
  sums_file="vault_${version}_SHA256SUMS"
  sig_file="vault_${version}_SHA256SUMS.sig"

  curl -fsSL -o "${tmp_dir}/${zip_file}" "${base_url}/${zip_file}"
  curl -fsSL -o "${tmp_dir}/${sums_file}" "${base_url}/${sums_file}"
  curl -fsSL -o "${tmp_dir}/${sig_file}" "${base_url}/${sig_file}"

  # GPG signature verification (isolated keyring to avoid polluting the system)
  export GNUPGHOME="${tmp_dir}/.gnupg"
  mkdir -p "${GNUPGHOME}"
  chmod 0700 "${GNUPGHOME}"

  curl -fsSL -o "${tmp_dir}/hashicorp.asc" \
    https://www.hashicorp.com/.well-known/pgp-key.txt
  gpg --quiet --import "${tmp_dir}/hashicorp.asc"
  printf '%s\n' "C874011F0AB405110D02105534365D9472D7468F:6:" | gpg --quiet --import-ownertrust

  log_info "Verifying GPG signature"
  gpg --quiet --verify "${tmp_dir}/${sig_file}" "${tmp_dir}/${sums_file}"

  log_info "Verifying SHA256 checksum"
  cd "${tmp_dir}" || return 1
  sha256sum -c --ignore-missing "${sums_file}"
  cd / || return 1
)

main() {
  tmp_dir="$(mktemp -d)" || return 1
  trap 'rm -rf "${tmp_dir}"' EXIT INT TERM HUP

  log_info "Installing Vault Enterprise ${VAULT_VERSION}"

  arch="$(detect_system_architecture)"
  download_and_verify_vault "${VAULT_VERSION}" "${arch}" "${tmp_dir}"

  unzip -o -q "${tmp_dir}/vault_${VAULT_VERSION}_linux_${arch}.zip" -d "${tmp_dir}"
  mv "${tmp_dir}/vault" /usr/bin/vault

  chown root:root /usr/bin/vault
  chmod 0755 /usr/bin/vault

  ln -sf /usr/bin/vault /usr/local/bin/vault

  log_info "Vault Enterprise ${VAULT_VERSION} installed"
}

main "${@}"
