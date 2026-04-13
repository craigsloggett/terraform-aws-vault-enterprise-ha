# shellcheck shell=sh
# system-setup.sh — OS-level preparation: networking, packages, time.

wait_for_network() {
  for attempt in 1 2 3 4 5; do
    if ping -c 1 -W 1 8.8.8.8 >/dev/null 2>&1; then
      return 0
    fi
    sleep 5
  done

  log_error "Network was not available after ${attempt} attempts, failing bootstrap"
  return 1
}

prepare_system() {
  log_info "Preparing system packages"

  export DEBIAN_FRONTEND=noninteractive

  apt-get -yq update >/dev/null
  apt-get -yq install \
    awscli gnupg jq unzip nvme-cli amazon-ec2-utils chrony >/dev/null
}

configure_time() {
  log_info "Configuring system time"

  timedatectl set-timezone UTC
  log_info "Timezone set to UTC"

  systemctl enable --now chrony
  chronyc makestep
  log_info "Time synchronization complete"
}
