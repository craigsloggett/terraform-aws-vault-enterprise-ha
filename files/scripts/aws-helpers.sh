# shellcheck shell=sh disable=SC2154
# aws-helpers.sh — AWS API helper functions.
#
# Requires globals: imds_endpoint, imds_token_ttl

# ---------------------------------------------------------------------------
# EC2 Metadata Helpers (IMDSv2)
# ---------------------------------------------------------------------------

imds_token() {
  curl -s -X PUT \
    -H "X-aws-ec2-metadata-token-ttl-seconds: ${imds_token_ttl}" \
    "${imds_endpoint}/latest/api/token"
}

imds_get() {
  path="${1}"
  token="${2}"
  curl -s -H "X-aws-ec2-metadata-token: ${token}" \
    "${imds_endpoint}/latest/meta-data/${path}"
}

get_private_ip() {
  token="$(imds_token)"
  imds_get "local-ipv4" "${token}"
}

get_instance_id() {
  token="$(imds_token)"
  imds_get "instance-id" "${token}"
}

get_availability_zone() {
  token="$(imds_token)"
  imds_get "placement/availability-zone" "${token}"
}

# ---------------------------------------------------------------------------
# Secrets Manager
# ---------------------------------------------------------------------------

fetch_secret() {
  region="${1}"
  secret_arn="${2}"

  for attempt in 1 2 3 4 5; do
    if result=$(aws secretsmanager get-secret-value \
      --region "${region}" \
      --secret-id "${secret_arn}" \
      --query SecretString --output text 2>/dev/null); then
      printf '%s' "${result}"
      return 0
    fi
    sleep 5
  done

  log_error "Failed to retrieve secret after ${attempt} attempts, failing bootstrap"
  return 1
}

# ---------------------------------------------------------------------------
# EBS Volume Helpers
# ---------------------------------------------------------------------------

# Note: resolve_ebs_nvme_device temporarily disables noglob (set +f)
# for the /dev/nvme* glob scan and re-enables it (set -f) before returning.

resolve_ebs_nvme_device() {
  target_name="${1}"

  # Strip leading /dev/ from target for comparison, ebsnvme-id returns
  # the short form (e.g. "sdf") on some versions and the full path on others.
  target_short="${target_name#/dev/}"

  # Globbing is disabled by set -f; re-enable for the device scan.
  set +f
  for nvme in /dev/nvme*n1; do
    [ -e "${nvme}" ] || continue

    # ebsnvme-id -b prints the block device name the volume was attached as.
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

  log_info "Resolving EBS volume attached as ${device_attachment_name}"

  if ! command -v ebsnvme-id >/dev/null 2>&1; then
    log_error "ebsnvme-id not found, ensure amazon-ec2-utils is installed in the AMI"
    return 1
  fi

  device=""

  for attempt in 1 2 3 4 5; do
    device="$(resolve_ebs_nvme_device "${device_attachment_name}")" && break

    log_info "NVMe device not yet available, retrying in 5 seconds (${attempt}/5)"
    sleep 5
  done

  if [ -z "${device}" ]; then
    log_error "NVMe device was not found after ${attempt} attempts, failing bootstrap"
    return 1
  fi

  log_info "Matched ${device_attachment_name} -> ${device}"

  # Format only if the device has no existing filesystem
  if ! blkid -p "${device}" >/dev/null 2>&1; then
    log_info "No filesystem on ${device}, formatting as xfs (label=${fs_label})"
    mkfs.xfs -L "${fs_label}" "${device}"
  else
    log_info "Filesystem already present on ${device}, skipping format"
  fi

  # Mount
  mkdir -p "${mount_point}"
  mount -t xfs "${device}" "${mount_point}"
  log_info "Mounted ${device} at ${mount_point}"

  # Persist in fstab (use UUID for stability across reboots)
  uuid="$(blkid -s UUID -o value "${device}")"
  if ! grep -q "${uuid}" /etc/fstab; then
    printf 'UUID=%s  %s  xfs  defaults,nofail  0  2\n' \
      "${uuid}" "${mount_point}" \
      >>/etc/fstab
    log_info "Added fstab entry for UUID=${uuid} (${fs_label})"
  fi
}
