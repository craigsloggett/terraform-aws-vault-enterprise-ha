# shellcheck shell=sh
# time.sh — System time configuration.

configure_time() {
  log_info "Configuring system time"

  timedatectl set-timezone UTC
  log_info "Timezone set to UTC"

  systemctl enable --now chrony
  chronyc makestep
  log_info "Time synchronization complete"
}
