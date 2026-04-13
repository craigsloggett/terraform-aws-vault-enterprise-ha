# shellcheck shell=sh
# ebs.sh — EBS volume resolution and filesystem preparation.

# Note: resolve_ebs_nvme_device temporarily disables noglob (set +f)
# for the /dev/nvme* glob scan and re-enables it (set -f) before returning.

resolve_ebs_nvme_device() {
  target_name="${1}"

  target_short="${target_name#/dev/}"

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
}

prepare_disk() {
  device_attachment_name="${1}"
  mount_point="${2}"
  fs_label="${3}"

  if ! command -v ebsnvme-id >/dev/null 2>&1; then
    log_error "ebsnvme-id not found, ensure amazon-ec2-utils is installed in the AMI"
    return 1
  fi

  for attempt in 1 2 3 4 5; do
    device="$(resolve_ebs_nvme_device "${device_attachment_name}")" && break
    sleep 5
  done

  if [ -z "${device}" ]; then
    log_error "NVMe device was not found after ${attempt} attempts, failing bootstrap"
    return 1
  fi

  if ! blkid -p "${device}" >/dev/null 2>&1; then
    log_info "No filesystem on ${device}, formatting as xfs (label=${fs_label})"
    mkfs.xfs -L "${fs_label}" "${device}"
  else
    log_info "Filesystem already present on ${device}, skipping format"
  fi

  log_info "Mounting ${device} at ${mount_point}"
  mkdir -p "${mount_point}"
  mount -t xfs "${device}" "${mount_point}"

  uuid="$(blkid -s UUID -o value "${device}")"
  if ! grep -q "${uuid}" /etc/fstab; then
    printf 'UUID=%s  %s  xfs  defaults,nofail  0  2\n' \
      "${uuid}" "${mount_point}" \
      >>/etc/fstab
    log_info "Added fstab entry for UUID=${uuid}"
  fi
}
