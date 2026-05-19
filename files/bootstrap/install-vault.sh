#!/bin/sh
# install-vault.sh
#
# Downloads, GPG-verifies, SHA256-verifies, and installs the Vault Enterprise
# binary at /usr/local/bin/vault. Runs on every node before the cluster
# bootstrap.

set -euf

# shellcheck source=bootstrap.env.tftpl
. /var/lib/cloud/scripts/bootstrap.env
# shellcheck source=SCRIPTDIR/common-functions.sh
. /var/lib/cloud/scripts/common-functions.sh

TMPDIR_SESSION="$(mktemp -d)"
readonly TMPDIR_SESSION
trap 'rm -rf "${TMPDIR_SESSION}"' EXIT INT TERM HUP

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
  release_filename="${1}"

  sha256sums_filename="vault_${VAULT_VERSION}_SHA256SUMS"
  sha256sums_signature_filename="vault_${VAULT_VERSION}_SHA256SUMS.sig"

  log_info "Downloading Vault Enterprise ${VAULT_VERSION}"
  curl --fail --silent --show-error --location \
    --output "${TMPDIR_SESSION}/${release_filename}" \
    "https://releases.hashicorp.com/vault/${VAULT_VERSION}/${release_filename}"

  log_info "Downloading Vault Enterprise ${VAULT_VERSION} SHA256SUMS file"
  curl --fail --silent --show-error --location \
    --output "${TMPDIR_SESSION}/${sha256sums_filename}" \
    "https://releases.hashicorp.com/vault/${VAULT_VERSION}/${sha256sums_filename}"

  log_info "Downloading Vault Enterprise ${VAULT_VERSION} SHA256SUMS signature file"
  curl --fail --silent --show-error --location \
    --output "${TMPDIR_SESSION}/${sha256sums_signature_filename}" \
    "https://releases.hashicorp.com/vault/${VAULT_VERSION}/${sha256sums_signature_filename}"

  # GPG signature verification (isolated keyring to avoid polluting the system)
  export GNUPGHOME="${TMPDIR_SESSION}/.gnupg"
  mkdir -p "${GNUPGHOME}"
  chmod 0700 "${GNUPGHOME}"

  log_info "Trusting HashiCorp PGP key"
  curl --fail --silent --show-error --location --output "${TMPDIR_SESSION}/hashicorp.asc" \
    https://www.hashicorp.com/.well-known/pgp-key.txt
  gpg --quiet --import "${TMPDIR_SESSION}/hashicorp.asc"
  printf '%s\n' "C874011F0AB405110D02105534365D9472D7468F:6:" | gpg --quiet --import-ownertrust

  log_info "Verifying PGP signature"
  gpg --quiet --verify "${TMPDIR_SESSION}/${sha256sums_signature_filename}" "${TMPDIR_SESSION}/${sha256sums_filename}"

  log_info "Verifying downloaded artifact SHA256 checksums"
  cd "${TMPDIR_SESSION}" &&
    sha256sum --check --ignore-missing "${sha256sums_filename}"
)

main() {
  log_info "Installing Vault Enterprise ${VAULT_VERSION}"

  vault_release_filename="vault_${VAULT_VERSION}_linux_$(detect_system_architecture).zip"
  download_and_verify_vault "${vault_release_filename}"

  unzip -o -q "${TMPDIR_SESSION}/${vault_release_filename}" -d "${TMPDIR_SESSION}"
  install -o root -g root -m 0755 "${TMPDIR_SESSION}/vault" /usr/local/bin/vault

  log_info "Vault Enterprise ${VAULT_VERSION} installed"
}

main "${@}"
