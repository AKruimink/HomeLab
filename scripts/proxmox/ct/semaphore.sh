#!/usr/bin/env bash
set -euo pipefail

SELF_PATH="${BASH_SOURCE[0]:-}"
SCRIPT_ROOT=""

bootstrap_source() {
  local relative_path="$1"
  local base_url="${HOMELAB_PROXMOX_BASE:-https://raw.githubusercontent.com/AKruimink/HomeLab/main/scripts/proxmox}"
  local local_path=""

  if [[ -n "$SCRIPT_ROOT" ]]; then
    local_path="${SCRIPT_ROOT}/${relative_path}"
    if [[ -f "$local_path" ]]; then
      # shellcheck disable=SC1090
      source "$local_path"
      return 0
    fi
  fi

  source /dev/stdin <<<"$(curl -fsSL "${base_url}/${relative_path}")"
}

if [[ -n "$SELF_PATH" && -f "$SELF_PATH" ]]; then
  SCRIPT_ROOT="$(cd "$(dirname "$SELF_PATH")/.." && pwd)"
fi

bootstrap_source "lib/common.sh"
bootstrap_source "lib/pve-host.sh"
bootstrap_source "lib/lxc-build.sh"

APP_NAME="Semaphore"
APP_SLUG="semaphore"
var_tags="${var_tags:-}"

prompt_semaphore_admin_settings() {
  local password_confirmation

  while true; do
    SEMAPHORE_ADMIN_LOGIN="$(prompt_input "SEMAPHORE LOGIN" "Set the initial Semaphore login name" "${SEMAPHORE_ADMIN_LOGIN:-admin}")" || return 1
    validate_nonempty "$SEMAPHORE_ADMIN_LOGIN" && break
    show_dialog_message "INVALID LOGIN" "The Semaphore login name cannot be empty."
  done

  while true; do
    SEMAPHORE_ADMIN_NAME="$(prompt_input "SEMAPHORE DISPLAY NAME" "Set the initial Semaphore display name" "${SEMAPHORE_ADMIN_NAME:-Administrator}")" || return 1
    validate_nonempty "$SEMAPHORE_ADMIN_NAME" && break
    show_dialog_message "INVALID DISPLAY NAME" "The Semaphore display name cannot be empty."
  done

  while true; do
    SEMAPHORE_ADMIN_EMAIL="$(prompt_input "SEMAPHORE EMAIL" "Set the initial Semaphore email address" "${SEMAPHORE_ADMIN_EMAIL:-admin@homelab.local}")" || return 1
    validate_email "$SEMAPHORE_ADMIN_EMAIL" && break
    show_dialog_message "INVALID EMAIL" "Enter a valid email address for the initial Semaphore admin."
  done

  while true; do
    SEMAPHORE_ADMIN_PASSWORD="$(prompt_password "SEMAPHORE PASSWORD" "Set the initial Semaphore admin password.\n\nLeave blank to generate a random password automatically.")" || return 1
    if [[ -z "${SEMAPHORE_ADMIN_PASSWORD}" ]]; then
      SEMAPHORE_ADMIN_PASSWORD="$(generate_secret 16)"
      SEMAPHORE_ADMIN_PASSWORD_GENERATED="1"
      break
    fi

    password_confirmation="$(prompt_password "CONFIRM PASSWORD" "Re-enter the initial Semaphore admin password")" || return 1
    if [[ "$SEMAPHORE_ADMIN_PASSWORD" == "$password_confirmation" ]]; then
      SEMAPHORE_ADMIN_PASSWORD_GENERATED="0"
      break
    fi
    show_dialog_message "PASSWORD MISMATCH" "The passwords did not match. Please try again."
  done
}

create_flow() {
  local admin_credentials
  local mode
  local ip_address

  lxc_apply_default_settings "semaphore" "2" "2048" "4" "ubuntu" "24.04"

  mode="$(prompt_install_mode "$APP_NAME")" || exit 0
  if [[ "$mode" == "exit" ]]; then
    exit 0
  fi
  if [[ "$mode" == "default" ]]; then
    msg_info "Using default settings for ${APP_NAME}"
  fi
  if [[ "$mode" == "advanced" ]]; then
    lxc_prompt_advanced_settings || exit 0
  fi
  prompt_semaphore_admin_settings || exit 0
  APP_INSTALL_ENV=(
    "SEMAPHORE_ADMIN_LOGIN=${SEMAPHORE_ADMIN_LOGIN}"
    "SEMAPHORE_ADMIN_NAME=${SEMAPHORE_ADMIN_NAME}"
    "SEMAPHORE_ADMIN_EMAIL=${SEMAPHORE_ADMIN_EMAIL}"
    "SEMAPHORE_ADMIN_PASSWORD=${SEMAPHORE_ADMIN_PASSWORD}"
  )

  lxc_confirm_settings || exit 0
  lxc_create_container "$APP_SLUG"
  lxc_sync_payload "$CTID" "$APP_SLUG" "$SCRIPT_ROOT"
  lxc_run_app_action "$CTID" "$APP_SLUG" "install"

  ip_address="$(pct_primary_ip "$CTID")"
  admin_credentials="$(pct exec "$CTID" -- cat /root/semaphore.creds 2>/dev/null || true)"
  msg_ok "Completed successfully"
  cat <<EOF

${BL}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${CL}
${BOLD}${GN}  ${APP_NAME} deployment details${CL}
${BL}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${CL}

${INFO}${YW}Semaphore URL:${CL}
${TAB3}${BGN}http://${ip_address}:3000${CL}
$(if [[ -n "$admin_credentials" ]]; then printf '\n%s%s%s\n%s\n' "$INFO" "$YW" "Initial admin credentials:${CL}" "$admin_credentials"; fi)${INFO}${YW}Update inside the container:${CL}
${TAB3}${BL}semaphore-update${CL}

EOF
}

main() {
  require_root
  require_proxmox_host
  ensure_whiptail
  header_info "$APP_NAME"
  create_flow
}

main "$@"
