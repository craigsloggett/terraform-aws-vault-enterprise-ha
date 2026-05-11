#!/bin/sh
# prepare-vault-storage.sh
#
# Waits for the EBS volumes for Vault Raft data and audit logs to appear as
# NVMe devices, formats them with XFS if needed, mounts them at their final
# paths, and writes /etc/fstab entries so the mounts survive reboots. Then
# sets ownership on the mount points so the vault user can read/write.
# Runs on every node before vault.service starts.

set -euf

# shellcheck source=/dev/null
. /var/lib/cloud/scripts/bootstrap.env
# shellcheck source=/dev/null
. /var/lib/cloud/scripts/common-functions.sh

readonly VAULT_DATA_DIR="/var/opt/vault"
readonly VAULT_LOG_DIR="/var/log/vault"
readonly VAULT_RAFT_DIR="${VAULT_DATA_DIR}/data"

get_ebs_nvme_device() (
  target_name="${1}"

  target_short="${target_name#/dev/}"

  # Temporarily disable noglob for the /dev/nvme* glob scan.
  set +f
  for nvme in /dev/nvme*n1; do
    [ -e "${nvme}" ] || continue

    attached="$(ebsnvme-id -b "${nvme}" 2>/dev/null)" || continue
    attached_short="${attached#/dev/}"

    if [ "${attached_short}" = "${target_short}" ]; then
      set -f
      printf '%s' "${nvme}"
      return 0
    fi
  done
  set -f

  return 1
)

wait_for_ebs_nvme_device() (
  device_attachment_name="${1}"

  log_info "Waiting for NVMe device for attachment ${device_attachment_name}"

  interval=5
  max_attempts=5
  attempt=0

  while [ "${attempt}" -lt "${max_attempts}" ]; do
    attempt=$((attempt + 1))
    if get_ebs_nvme_device "${device_attachment_name}" >/dev/null 2>&1; then
      return 0
    fi
    sleep "${interval}"
  done

  log_error "NVMe device for attachment ${device_attachment_name} did not appear after ${max_attempts} attempts"
  return 1
)

prepare_disk() (
  device="${1}"
  mount_point="${2}"
  fs_label="${3}"

  if [ "${#fs_label}" -gt 12 ]; then
    log_error "XFS labels must be 12 characters or fewer: ${fs_label}"
    return 1
  fi

  if ! blkid -p "${device}" >/dev/null 2>&1; then
    log_info "No filesystem on ${device}, formatting as xfs (label=${fs_label})"
    mkfs.xfs -L "${fs_label}" "${device}" >/dev/null
  else
    log_info "Filesystem already present on ${device}, skipping format"
  fi

  if ! mountpoint -q "${mount_point}"; then
    log_info "Mounting ${device} at ${mount_point}"
    mkdir -p "${mount_point}"
    mount -t xfs "${device}" "${mount_point}"
  else
    log_info "${mount_point} already mounted, skipping"
  fi

  uuid="$(blkid -s UUID -o value "${device}")"
  if ! grep -qE "^UUID=${uuid}[[:blank:]]" /etc/fstab; then
    printf 'UUID=%s  %s  xfs  defaults,nofail  0  2\n' \
      "${uuid}" "${mount_point}" \
      >>/etc/fstab
    log_info "Added fstab entry for UUID=${uuid}"
  fi
)

configure_vault_mount_directories() (
  # Mount-point ownership must be set after prepare_disk overlays the volume,
  # otherwise the settings apply to the underlying directory and are hidden
  # by the mount.
  log_info "Setting ownership and permissions on Vault mount directories"

  chown vault:vault "${VAULT_RAFT_DIR}"
  chmod 700 "${VAULT_RAFT_DIR}"

  chown vault:vault "${VAULT_LOG_DIR}"
  chmod 755 "${VAULT_LOG_DIR}"
)

main() {
  wait_for_ebs_nvme_device "${EBS_RAFT_DEVICE_NAME}"
  raft_device="$(get_ebs_nvme_device "${EBS_RAFT_DEVICE_NAME}")"
  prepare_disk "${raft_device}" "${VAULT_RAFT_DIR}" "vault-raft"

  wait_for_ebs_nvme_device "${EBS_AUDIT_DEVICE_NAME}"
  audit_device="$(get_ebs_nvme_device "${EBS_AUDIT_DEVICE_NAME}")"
  prepare_disk "${audit_device}" "${VAULT_LOG_DIR}" "vault-audit"

  configure_vault_mount_directories
}

main "${@}"
