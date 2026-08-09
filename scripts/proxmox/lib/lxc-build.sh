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
  HOSTNAME="${HOSTNAME:-$default_hostname}"
  CPU="${CPU:-$default_cpu}"
  RAM="${RAM:-$default_ram}"
  DISK="${DISK:-$default_disk}"
  OS_ID="${OS_ID:-$default_os}"
  OS_VERSION="${OS_VERSION:-$default_version}"
  BRIDGE="${BRIDGE:-$(pve_first_bridge)}"
  USE_DHCP="${USE_DHCP:-yes}"
  IPV4_CIDR="${IPV4_CIDR:-}"
  GATEWAY="${GATEWAY:-}"
  UNPRIVILEGED="${UNPRIVILEGED:-1}"
  ONBOOT="${ONBOOT:-1}"
  IPV6_METHOD="${IPV6_METHOD:-auto}"
  TEMPLATE_STORAGE="${TEMPLATE_STORAGE:-$(pve_first_storage "vztmpl")}"
  CONTAINER_STORAGE="${CONTAINER_STORAGE:-$(pve_first_storage "rootdir")}"
}

lxc_prompt_advanced_settings() {
  local selection

  while true; do
    selection="$(prompt_input "Container ID" "Choose a numeric CTID." "${CTID:-$(next_lxc_id)}")" || return 1
    validate_integer "$selection" && break
    msg_warn "CTID must be a numeric value."
  done
  CTID="$selection"

  while true; do
    selection="$(prompt_input "Hostname" "Enter the container hostname." "${HOSTNAME:-semaphore}")" || return 1
    validate_hostname "$selection" && break
    msg_warn "Hostname must start with a letter or number and may contain hyphens."
  done
  HOSTNAME="$selection"

  selection="$(prompt_menu "Operating System" "Select the LXC operating system." \
    "ubuntu-24.04" "Ubuntu 24.04 LTS" \
    "debian-12" "Debian 12")" || return 1
  OS_ID="${selection%-*}"
  OS_VERSION="${selection#*-}"

  while true; do
    selection="$(prompt_input "CPU Cores" "Set the number of vCPU cores." "${CPU:-2}")" || return 1
    validate_integer "$selection" && break
    msg_warn "CPU cores must be a positive integer."
  done
  CPU="$selection"

  while true; do
    selection="$(prompt_input "Memory" "Set the RAM size in MiB." "${RAM:-2048}")" || return 1
    validate_integer "$selection" && break
    msg_warn "RAM must be a positive integer in MiB."
  done
  RAM="$selection"

  while true; do
    selection="$(prompt_input "Disk" "Set the root disk size in GiB." "${DISK:-8}")" || return 1
    validate_integer "$selection" && break
    msg_warn "Disk size must be a positive integer in GiB."
  done
  DISK="$selection"

  BRIDGE="$(pve_pick_bridge "${BRIDGE:-}")" || return 1

  if prompt_yes_no "IPv4" "Use DHCP for IPv4?" "yes"; then
    USE_DHCP="yes"
    IPV4_CIDR=""
    GATEWAY=""
  else
    USE_DHCP="no"
    IPV4_CIDR="$(prompt_input "IPv4 Address" "Enter the static IPv4 CIDR (example: 192.168.1.50/24)." "${IPV4_CIDR:-}")" || return 1
    GATEWAY="$(prompt_input "Gateway" "Enter the IPv4 gateway (example: 192.168.1.1)." "${GATEWAY:-}")" || return 1
  fi

  if prompt_yes_no "Container Privileges" "Create this as an unprivileged container?" "yes"; then
    UNPRIVILEGED="1"
  else
    UNPRIVILEGED="0"
  fi

  if prompt_yes_no "Boot Behavior" "Start this container automatically on node boot?" "yes"; then
    ONBOOT="1"
  else
    ONBOOT="0"
  fi

  if prompt_yes_no "IPv6" "Leave IPv6 enabled inside the container?" "yes"; then
    IPV6_METHOD="auto"
  else
    IPV6_METHOD="disable"
  fi

  TEMPLATE_STORAGE="$(pve_pick_storage "vztmpl" "Template Storage" "Select where the LXC template should live." "${TEMPLATE_STORAGE:-}")" || return 1
  CONTAINER_STORAGE="$(pve_pick_storage "rootdir" "Container Storage" "Select where the container root filesystem should live." "${CONTAINER_STORAGE:-}")" || return 1
}

lxc_summary_text() {
  cat <<EOF
App:            ${APP_NAME}
CTID:           ${CTID}
Hostname:       ${HOSTNAME}
OS:             ${OS_ID} ${OS_VERSION}
CPU:            ${CPU} core(s)
Memory:         ${RAM} MiB
Disk:           ${DISK} GiB
Bridge:         ${BRIDGE}
IPv4:           $( [[ "${USE_DHCP}" == "yes" ]] && printf '%s' "DHCP" || printf '%s via %s' "${IPV4_CIDR}" "${GATEWAY}" )
IPv6:           ${IPV6_METHOD}
Unprivileged:   ${UNPRIVILEGED}
On boot:        ${ONBOOT}
Template store: ${TEMPLATE_STORAGE}
Rootfs store:   ${CONTAINER_STORAGE}
EOF
}

lxc_confirm_settings() {
  local summary
  summary="$(lxc_summary_text)"

  if command_exists whiptail; then
    whiptail --backtitle "HomeLab Proxmox Scripts" --title "Confirm Container Settings" --yesno "$summary" 20 78
    return $?
  fi

  echo "$summary"
  prompt_yes_no "Confirm Container Settings" "Continue with these settings?" "yes"
}

lxc_create_container() {
  local app_slug="$1"
  local template_ref
  local net0

  ensure_guest_id_available "$CTID"
  template_ref="$(pve_ensure_lxc_template "$TEMPLATE_STORAGE" "$OS_ID" "$OS_VERSION")"
  net0="$(build_lxc_net0 "$BRIDGE" "$USE_DHCP" "$IPV4_CIDR" "$GATEWAY")"

  msg_info "Creating CT ${CTID}"
  pct create "$CTID" "$template_ref" \
    --arch "$(dpkg --print-architecture)" \
    --hostname "$HOSTNAME" \
    --cores "$CPU" \
    --memory "$RAM" \
    --rootfs "${CONTAINER_STORAGE}:${DISK}" \
    --net0 "$net0" \
    --unprivileged "$UNPRIVILEGED" \
    --onboot "$ONBOOT" \
    --features nesting=1 \
    --tags "homelab;${app_slug}" >/dev/null
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
    IPV6_METHOD="${IPV6_METHOD:-auto}" \
    bash -lc "export FUNCTIONS_FILE_PATH=\"\$(cat /opt/homelab-proxmox/lib/container-functions.sh)\"; bash /opt/homelab-proxmox/install/${app_slug}-install.sh"
}

lxc_update_existing_app() {
  local app_slug="$1"
  local script_root="$2"
  local target_ctid

  while true; do
    target_ctid="$(prompt_input "Semaphore CTID" "Enter the CTID of the existing ${APP_NAME} container." "${CTID:-}")" || return 1
    validate_integer "$target_ctid" && break
    msg_warn "CTID must be a numeric value."
  done

  pct status "$target_ctid" >/dev/null 2>&1 || die "CT ${target_ctid} does not exist."
  CTID="$target_ctid"
  lxc_sync_payload "$CTID" "$app_slug" "$script_root"
  lxc_run_app_action "$CTID" "$app_slug" "update"
}
