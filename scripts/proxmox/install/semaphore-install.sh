#!/usr/bin/env bash
set -euo pipefail

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
formatting
icons

APP_NAME="${APP_NAME:-Semaphore}"
APP_SLUG="${APP_SLUG:-semaphore}"
SEMAPHORE_ADMIN_LOGIN="${SEMAPHORE_ADMIN_LOGIN:-admin}"
SEMAPHORE_ADMIN_NAME="${SEMAPHORE_ADMIN_NAME:-Administrator}"
SEMAPHORE_ADMIN_EMAIL="${SEMAPHORE_ADMIN_EMAIL:-admin@homelab.local}"
SEMAPHORE_ADMIN_PASSWORD="${SEMAPHORE_ADMIN_PASSWORD:-}"

SEMAPHORE_HOME="/opt/semaphore"
SEMAPHORE_CONFIG="${SEMAPHORE_HOME}/config.json"
SEMAPHORE_DB="${SEMAPHORE_HOME}/database.sqlite"
SEMAPHORE_SERVICE="/etc/systemd/system/semaphore.service"
SEMAPHORE_CREDS="/root/semaphore.creds"

install_dependencies() {
  run_with_progress "Installing Semaphore dependencies" apt-get install -y git ansible
  msg_ok "Installed Semaphore dependencies"
}

install_semaphore_release() {
  msg_info "Installing latest Semaphore release"
  install_github_deb_release "semaphoreui/semaphore" "semaphore_.*_linux_$(arch_resolve)\\.deb$"
  msg_ok "Installed latest Semaphore release"
}

configure_semaphore_files() {
  local sem_hash
  local sem_encryption
  local sem_key

  msg_info "Configuring Semaphore"
  mkdir -p "${SEMAPHORE_HOME}/tmp"
  if [[ -f "${SEMAPHORE_CONFIG}" ]]; then
    msg_ok "Keeping existing Semaphore config"
    return 0
  fi

  sem_hash="$(generate_secret 32)"
  sem_encryption="$(generate_secret 32)"
  sem_key="$(generate_secret 32)"

  cat <<EOF >"${SEMAPHORE_CONFIG}"
{
  "sqlite": {
    "host": "${SEMAPHORE_DB}"
  },
  "dialect": "sqlite",
  "tmp_path": "${SEMAPHORE_HOME}/tmp",
  "cookie_hash": "${sem_hash}",
  "cookie_encryption": "${sem_encryption}",
  "access_key_encryption": "${sem_key}"
}
EOF
  msg_ok "Configured Semaphore"
}

migrate_from_boltdb_if_needed() {
  if [[ ! -f "${SEMAPHORE_HOME}/semaphore_db.bolt" ]]; then
    return 0
  fi

  msg_info "Migrating existing BoltDB data to SQLite"
  if ! grep -q '"dialect": "sqlite"' "${SEMAPHORE_CONFIG}"; then
    sed -i \
      -e 's|"bolt": {|"sqlite": {|' \
      -e 's|/semaphore_db.bolt"|/database.sqlite"|' \
      -e '/semaphore_db.bolt/d' \
      -e '/"dialect"/d' \
      -e '/^  },$/a\  "dialect": "sqlite",' \
      "${SEMAPHORE_CONFIG}"
  fi
  semaphore migrate --from-boltdb "${SEMAPHORE_HOME}/semaphore_db.bolt" --config "${SEMAPHORE_CONFIG}" >/dev/null
  rm -f "${SEMAPHORE_HOME}/semaphore_db.bolt"
  msg_ok "Migrated existing BoltDB data"
}

create_admin_user_if_needed() {
  local admin_password

  if [[ -f "${SEMAPHORE_DB}" ]]; then
    return 0
  fi

  admin_password="${SEMAPHORE_ADMIN_PASSWORD:-$(generate_secret 16)}"
  msg_info "Creating initial Semaphore admin user"
  run_with_progress "Creating initial Semaphore admin user" semaphore user add \
    --admin \
    --login "${SEMAPHORE_ADMIN_LOGIN}" \
    --email "${SEMAPHORE_ADMIN_EMAIL}" \
    --name "${SEMAPHORE_ADMIN_NAME}" \
    --password "${admin_password}" \
    --config "${SEMAPHORE_CONFIG}"
  cat <<EOF >"${SEMAPHORE_CREDS}"
Username: ${SEMAPHORE_ADMIN_LOGIN}
Display Name: ${SEMAPHORE_ADMIN_NAME}
Email: ${SEMAPHORE_ADMIN_EMAIL}
Password: ${admin_password}
EOF
  chmod 600 "${SEMAPHORE_CREDS}"
  msg_ok "Created initial Semaphore admin user"
}

write_semaphore_service() {
  msg_info "Creating Semaphore systemd service"
  cat <<EOF >"${SEMAPHORE_SERVICE}"
[Unit]
Description=Semaphore UI
Documentation=https://docs.semaphoreui.com/
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/semaphore server --config ${SEMAPHORE_CONFIG}
Restart=always
RestartSec=10s

[Install]
WantedBy=multi-user.target
EOF
  run_with_progress "Reloading systemd and starting Semaphore" bash -lc 'systemctl daemon-reload && systemctl enable -q --now semaphore'
  msg_ok "Created Semaphore systemd service"
}

install_update_command() {
  create_update_wrapper "semaphore-update" "/opt/homelab-proxmox/install/semaphore-install.sh"
}

run_install() {
  setting_up_container
  network_check
  update_os
  install_dependencies
  install_semaphore_release
  configure_semaphore_files
  migrate_from_boltdb_if_needed
  create_admin_user_if_needed
  write_semaphore_service
  write_app_marker
  install_update_command

  APP_URL="http://$(get_primary_ip):3000"
  APP_UPDATE_HINT="semaphore-update"
  motd_ssh
  customize
  cleanup_lxc
}

run_update() {
  setting_up_container
  network_check
  update_os
  install_dependencies

  if systemctl is-active --quiet semaphore; then
    msg_info "Stopping Semaphore"
    run_with_progress "Stopping Semaphore" systemctl stop semaphore
    msg_ok "Stopped Semaphore"
  fi

  install_semaphore_release
  configure_semaphore_files
  migrate_from_boltdb_if_needed
  write_semaphore_service
  write_app_marker
  install_update_command

  APP_URL="http://$(get_primary_ip):3000"
  APP_UPDATE_HINT="semaphore-update"
  motd_ssh
  customize
  cleanup_lxc
}

case "${APP_ACTION:-install}" in
install)
  run_install
  ;;
update)
  run_update
  ;;
*)
  die "Unsupported APP_ACTION '${APP_ACTION}'."
  ;;
esac
