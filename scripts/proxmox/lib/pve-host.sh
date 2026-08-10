#!/usr/bin/env bash

if [[ -n "${HOMELAB_PROXMOX_PVE_HOST_LOADED:-}" ]]; then
  return 0
fi
HOMELAB_PROXMOX_PVE_HOST_LOADED=1

pve_list_storages() {
  local content_type="$1"
  pvesm status -content "$content_type" | awk 'NR > 1 { print $1 }'
}

pve_pick_storage() {
  local content_type="$1"
  local title="$2"
  local prompt="$3"
  local current_value="${4:-}"
  local -a storages=()
  local -a storage_options=()
  local default_storage=""
  local storage

  mapfile -t storages < <(pve_list_storages "$content_type")
  ((${#storages[@]} > 0)) || die "No storage found that supports '${content_type}'."

  if ((${#storages[@]} == 1)); then
    printf '%s' "${storages[0]}"
    return 0
  fi

  default_storage="${current_value:-${storages[0]}}"
  for storage in "${storages[@]}"; do
    storage_options+=("$storage" "Storage supporting ${content_type}")
  done

  prompt_radiolist "$title" "$prompt" "$default_storage" "${storage_options[@]}"
}

pve_first_storage() {
  local content_type="$1"
  pve_list_storages "$content_type" | head -n1
}

pve_list_bridges() {
  ip -o link show | awk -F': ' '$2 ~ /^vmbr/ { print $2 }'
}

pve_first_bridge() {
  pve_list_bridges | head -n1
}

pve_pick_bridge() {
  local current_value="${1:-}"
  local title="${2:-NETWORK BRIDGE}"
  local prompt="${3:-Select the bridge for this container.}"
  local -a bridges=()
  local -a bridge_options=()
  local default_bridge=""
  local bridge

  mapfile -t bridges < <(pve_list_bridges)
  ((${#bridges[@]} > 0)) || die "No vmbr bridge interfaces were found on this Proxmox host."

  if ((${#bridges[@]} == 1)); then
    printf '%s' "${bridges[0]}"
    return 0
  fi

  default_bridge="${current_value:-${bridges[0]}}"
  for bridge in "${bridges[@]}"; do
    bridge_options+=("$bridge" "Proxmox bridge")
  done

  prompt_radiolist "$title" "$prompt" "$default_bridge" "${bridge_options[@]}"
}

ensure_guest_id_available() {
  local guest_id="$1"

  if pct status "$guest_id" >/dev/null 2>&1; then
    die "Guest ID ${guest_id} is already used by an LXC container."
  fi
  if qm status "$guest_id" >/dev/null 2>&1; then
    die "Guest ID ${guest_id} is already used by a virtual machine."
  fi
}

pve_lxc_template_prefix() {
  local os_id="$1"
  local os_version="$2"

  case "${os_id}-${os_version}" in
  ubuntu-24.04) printf '%s' "ubuntu-24.04-standard_" ;;
  debian-12) printf '%s' "debian-12-standard_" ;;
  *)
    die "Unsupported LXC template selection: ${os_id}-${os_version}."
    ;;
  esac
}

pve_ensure_lxc_template() {
  local template_storage="$1"
  local os_id="$2"
  local os_version="$3"
  local template_prefix
  local template_name

  template_prefix="$(pve_lxc_template_prefix "$os_id" "$os_version")"

  msg_info "Refreshing LXC template catalog"
  pveam update >/dev/null
  msg_ok "Refreshed LXC template catalog"

  template_name="$(pveam available -section system | awk -v prefix="$template_prefix" '$2 ~ ("^" prefix) { print $2 }' | tail -n1)"
  [[ -n "$template_name" ]] || die "Unable to find an upstream LXC template matching '${template_prefix}'."

  if ! pveam list "$template_storage" | awk '{ print $2 }' | grep -qx "$template_name"; then
    msg_info "Downloading template ${template_name} to ${template_storage}"
    pveam download "$template_storage" "$template_name" >/dev/null
    msg_ok "Downloaded template ${template_name}"
  fi

  printf '%s' "${template_storage}:vztmpl/${template_name}"
}

build_lxc_net0() {
  local bridge="$1"
  local network_mode="$2"
  local ipv4="$3"
  local gateway="$4"

  if [[ "$network_mode" == "dhcp" ]]; then
    printf '%s' "name=eth0,bridge=${bridge},ip=dhcp"
    return 0
  fi

  printf '%s' "name=eth0,bridge=${bridge},ip=${ipv4},gw=${gateway}"
}

ensure_pct_running() {
  local ctid="$1"
  if pct status "$ctid" | grep -q "status: running"; then
    return 0
  fi

  msg_info "Starting CT ${ctid}"
  pct start "$ctid" >/dev/null
  msg_ok "Started CT ${ctid}"
}

pct_push_file_from_content() {
  local ctid="$1"
  local content="$2"
  local remote_path="$3"
  local tmp_file

  tmp_file="$(mktemp)"
  printf '%s' "$content" >"$tmp_file"
  pct push "$ctid" "$tmp_file" "$remote_path" >/dev/null
  rm -f "$tmp_file"
}

pct_wait_for_network() {
  local ctid="$1"
  local retries="${2:-30}"
  local attempt

  for ((attempt = 1; attempt <= retries; attempt++)); do
    if pct exec "$ctid" -- bash -lc 'hostname -I | grep -q "[0-9A-Fa-f:.]"' >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done

  return 1
}

pct_primary_ip() {
  local ctid="$1"
  pct exec "$ctid" -- bash -lc 'hostname -I | awk "{print \$1}"' 2>/dev/null | tr -d '\r'
}
