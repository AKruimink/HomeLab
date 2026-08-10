#!/usr/bin/env bash

if [[ -n "${HOMELAB_PROXMOX_LXC_BUILD_LOADED:-}" ]]; then
  return 0
fi
HOMELAB_PROXMOX_LXC_BUILD_LOADED=1

lxc_apply_default_settings() {
  local default_hostname="$1"
  local default_cpu="$2"
  local default_ram="$3"
  local default_disk="$4"
  local default_os="$5"
  local default_version="$6"

  CTID="${CTID:-$(next_lxc_id)}"
  CT_HOSTNAME="${CT_HOSTNAME:-${var_hostname:-$default_hostname}}"
  CT_CORES="${CT_CORES:-${var_cpu:-$default_cpu}}"
  CT_MEMORY="${CT_MEMORY:-${var_ram:-$default_ram}}"
  CT_DISK="${CT_DISK:-${var_disk:-$default_disk}}"
  OS_ID="${OS_ID:-$default_os}"
  OS_VERSION="${OS_VERSION:-$default_version}"
  CT_BRIDGE="${CT_BRIDGE:-$(pve_first_bridge)}"
  CT_NETWORK_MODE="${CT_NETWORK_MODE:-dhcp}"
  CT_IPV4_CIDR="${CT_IPV4_CIDR:-}"
  CT_GATEWAY="${CT_GATEWAY:-}"
  CT_UNPRIVILEGED="${CT_UNPRIVILEGED:-1}"
  CT_ONBOOT="${CT_ONBOOT:-1}"
  CT_IPV6_METHOD="${CT_IPV6_METHOD:-auto}"
  CT_TAGS="${CT_TAGS:-${var_tags:-}}"
  CT_TEMPLATE_STORAGE="${CT_TEMPLATE_STORAGE:-$(pve_first_storage "vztmpl")}"
  CT_CONTAINER_STORAGE="${CT_CONTAINER_STORAGE:-$(pve_first_storage "rootdir")}"
}

lxc_prompt_advanced_settings() {
  local selection

  while true; do
    selection="$(prompt_input "CONTAINER ID" "Set Container ID" "${CTID:-$(next_lxc_id)}")" || return 1
    validate_integer "$selection" && break
    msg_warn "CTID must be a numeric value."
  done
  CTID="$selection"

  while true; do
    selection="$(prompt_input "HOSTNAME" "Set Hostname" "${CT_HOSTNAME:-semaphore}")" || return 1
    validate_hostname "$selection" && break
    msg_warn "Hostname must start with a letter or number and may contain hyphens."
  done
  CT_HOSTNAME="$selection"

  selection="$(prompt_menu "OPERATING SYSTEM" "Select Operating System" \
    "ubuntu-24.04" "Ubuntu 24.04 LTS" \
    "debian-12" "Debian 12")" || return 1
  OS_ID="${selection%-*}"
  OS_VERSION="${selection#*-}"

  while true; do
    selection="$(prompt_input "CPU CORES" "Set CPU Cores" "${CT_CORES:-2}")" || return 1
    validate_integer "$selection" && break
    msg_warn "CPU cores must be a positive integer."
  done
  CT_CORES="$selection"

  while true; do
    selection="$(prompt_input "RAM" "Set RAM in MiB" "${CT_MEMORY:-2048}")" || return 1
    validate_integer "$selection" && break
    msg_warn "RAM must be a positive integer in MiB."
  done
  CT_MEMORY="$selection"

  while true; do
    selection="$(prompt_input "DISK SIZE" "Set Disk Size in GiB" "${CT_DISK:-8}")" || return 1
    validate_integer "$selection" && break
    msg_warn "Disk size must be a positive integer in GiB."
  done
  CT_DISK="$selection"

  CT_BRIDGE="$(pve_pick_bridge "${CT_BRIDGE:-}")" || return 1

  selection="$(prompt_two_option_menu "IP ADDRESS" "Select IP Address Mode" \
    "dhcp" "Automatic DHCP address" \
    "static" "Manual static IPv4 address")" || return 1
  CT_NETWORK_MODE="$selection"

  if [[ "$CT_NETWORK_MODE" == "static" ]]; then
    CT_IPV4_CIDR="$(prompt_input "IP ADDRESS" "Set a Static IPv4 CIDR Address" "${CT_IPV4_CIDR:-}")" || return 1
    CT_GATEWAY="$(prompt_input "GATEWAY" "Set Gateway IP Address" "${CT_GATEWAY:-}")" || return 1
  else
    CT_IPV4_CIDR=""
    CT_GATEWAY=""
  fi

  selection="$(prompt_two_option_menu "CONTAINER TYPE" "Select Container Type" \
    "unprivileged" "Recommended for most applications" \
    "privileged" "Use only when the application requires it")" || return 1
  if [[ "$selection" == "unprivileged" ]]; then
    CT_UNPRIVILEGED="1"
  else
    CT_UNPRIVILEGED="0"
  fi

  if prompt_yes_no "START AT BOOT" "Start Container at boot?" "yes"; then
    CT_ONBOOT="1"
  else
    CT_ONBOOT="0"
  fi

  selection="$(prompt_two_option_menu "IPV6" "Select IPv6 Mode" \
    "auto" "Keep IPv6 enabled" \
    "disable" "Disable IPv6 in the container")" || return 1
  if [[ "$selection" == "auto" ]]; then
    CT_IPV6_METHOD="auto"
  else
    CT_IPV6_METHOD="disable"
  fi

  CT_TAGS="$(prompt_input "TAGS" "Optional tags (comma separated)" "${CT_TAGS:-}")" || return 1

  CT_TEMPLATE_STORAGE="$(pve_pick_storage "vztmpl" "TEMPLATE STORAGE" "Select Template Storage" "${CT_TEMPLATE_STORAGE:-}")" || return 1
  CT_CONTAINER_STORAGE="$(pve_pick_storage "rootdir" "CONTAINER STORAGE" "Select Container Storage" "${CT_CONTAINER_STORAGE:-}")" || return 1
}

lxc_summary_text() {
  cat <<EOF
App:            ${APP_NAME}
CTID:           ${CTID}
Hostname:       ${CT_HOSTNAME}
OS:             ${OS_ID} ${OS_VERSION}
CPU:            ${CT_CORES} core(s)
Memory:         ${CT_MEMORY} MiB
Disk:           ${CT_DISK} GiB
Bridge:         ${CT_BRIDGE}
IPv4:           $( [[ "${CT_NETWORK_MODE}" == "dhcp" ]] && printf '%s' "DHCP" || printf '%s via %s' "${CT_IPV4_CIDR}" "${CT_GATEWAY}" )
IPv6:           ${CT_IPV6_METHOD}
Tags:           ${CT_TAGS:-none}
Unprivileged:   ${CT_UNPRIVILEGED}
On boot:        ${CT_ONBOOT}
Template store: ${CT_TEMPLATE_STORAGE}
Rootfs store:   ${CT_CONTAINER_STORAGE}
EOF
}

lxc_confirm_settings() {
  local summary
  summary="$(lxc_summary_text)"

  if command_exists whiptail; then
    whiptail --backtitle "$HOMELAB_WHIPTAIL_BACKTITLE" --title "CONFIRM SETTINGS" --yesno "$summary" 20 78
    return $?
  fi

  echo "$summary"
  prompt_yes_no "Confirm Container Settings" "Continue with these settings?" "yes"
}

lxc_create_container() {
  local app_slug="$1"
  local template_ref
  local net0
  local tags_option=()

  ensure_guest_id_available "$CTID"
  template_ref="$(pve_ensure_lxc_template "$CT_TEMPLATE_STORAGE" "$OS_ID" "$OS_VERSION")"
  net0="$(build_lxc_net0 "$CT_BRIDGE" "$CT_NETWORK_MODE" "$CT_IPV4_CIDR" "$CT_GATEWAY")"

  if [[ -n "${CT_TAGS:-}" ]]; then
    tags_option=(--tags "$CT_TAGS")
  fi

  msg_info "Creating CT ${CTID}"
  pct create "$CTID" "$template_ref" \
    --arch "$(dpkg --print-architecture)" \
    --hostname "$CT_HOSTNAME" \
    --cores "$CT_CORES" \
    --memory "$CT_MEMORY" \
    --rootfs "${CT_CONTAINER_STORAGE}:${CT_DISK}" \
    --net0 "$net0" \
    --unprivileged "$CT_UNPRIVILEGED" \
    --onboot "$CT_ONBOOT" \
    --features nesting=1 \
    "${tags_option[@]}" >/dev/null
  msg_ok "Created CT ${CTID}"

  msg_info "Starting CT ${CTID}"
  pct start "$CTID" >/dev/null
  msg_ok "Started CT ${CTID}"

  msg_info "Waiting for CT ${CTID} network"
  pct_wait_for_network "$CTID" || die "Container network did not become ready in time."
  msg_ok "CT ${CTID} network is ready"
}

lxc_sync_payload() {
  local ctid="$1"
  local app_slug="$2"
  local script_root="$3"
  local container_bundle
  local installer_script

  container_bundle="$(get_repo_file_content "$script_root" "lib/common.sh")"$'\n'"$(get_repo_file_content "$script_root" "lib/container-install.sh")"
  installer_script="$(get_repo_file_content "$script_root" "install/${app_slug}-install.sh")"

  pct exec "$ctid" -- bash -lc 'mkdir -p /opt/homelab-proxmox/lib /opt/homelab-proxmox/install'
  pct_push_file_from_content "$ctid" "$container_bundle" "/opt/homelab-proxmox/lib/container-functions.sh"
  pct_push_file_from_content "$ctid" "$installer_script" "/opt/homelab-proxmox/install/${app_slug}-install.sh"
  pct exec "$ctid" -- bash -lc "chmod 755 /opt/homelab-proxmox/install/${app_slug}-install.sh"
}

lxc_run_app_action() {
  local ctid="$1"
  local app_slug="$2"
  local action="$3"

  ensure_pct_running "$ctid"
  pct exec "$ctid" -- env \
    APP_ACTION="$action" \
    APP_NAME="$APP_NAME" \
    APP_SLUG="$app_slug" \
    IPV6_METHOD="${CT_IPV6_METHOD:-auto}" \
    bash -lc "export FUNCTIONS_FILE_PATH=\"\$(cat /opt/homelab-proxmox/lib/container-functions.sh)\"; bash /opt/homelab-proxmox/install/${app_slug}-install.sh"
}
