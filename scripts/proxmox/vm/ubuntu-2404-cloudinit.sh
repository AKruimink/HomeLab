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
bootstrap_source "lib/vm-build.sh"

main() {
  local mode

  require_root
  require_proxmox_host
  ensure_whiptail
  header_info "Ubuntu 24.04 Cloud-Init VM"

  vm_apply_default_settings "ubuntu-2404-base" "2" "4096" "20"

  mode="$(prompt_default_or_advanced)" || exit 0

  if [[ "$mode" == "advanced" ]]; then
    vm_prompt_advanced_settings || exit 0
  fi

  vm_confirm_settings || exit 0
  vm_create_ubuntu_cloudinit
  msg_ok "Ubuntu 24.04 cloud-init VM created successfully"
}

main "$@"
