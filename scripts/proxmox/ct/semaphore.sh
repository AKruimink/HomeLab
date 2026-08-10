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

create_flow() {
  local mode
  local ip_address

  lxc_apply_default_settings "semaphore" "2" "2048" "4" "ubuntu" "24.04"

  mode="$(prompt_default_or_advanced)" || exit 0
  if [[ "$mode" == "advanced" ]]; then
    lxc_prompt_advanced_settings || exit 0
  fi

  lxc_confirm_settings || exit 0
  lxc_create_container "$APP_SLUG"
  lxc_sync_payload "$CTID" "$APP_SLUG" "$SCRIPT_ROOT"
  lxc_run_app_action "$CTID" "$APP_SLUG" "install"

  ip_address="$(pct_primary_ip "$CTID")"
  msg_ok "Completed successfully"
  echo -e "${INFO}${YW}Access ${APP_NAME} at:${CL}"
  echo -e "${TAB3}${BGN}http://${ip_address}:3000${CL}"
  echo -e "${INFO}${YW}Update inside the container:${CL}"
  echo -e "${TAB3}${BL}semaphore-update${CL}"
}

main() {
  require_root
  require_proxmox_host
  ensure_whiptail
  header_info "$APP_NAME"
  create_flow
}

main "$@"
