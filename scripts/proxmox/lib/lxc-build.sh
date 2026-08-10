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
  local step=1
  local max_step=14
  local selection
  local selected_flags

  tput smcup 2>/dev/null || true
  trap 'tput rmcup 2>/dev/null || true' RETURN

  lxc_wizard_text() {
    local current_step="$1"
    local total_steps="$2"
    local message="$3"
    printf 'Step %s of %s\n\n%s' "$current_step" "$total_steps" "$message"
  }

  while ((step <= max_step)); do
    case "$step" in
    1)
      while true; do
        if ! selection="$(prompt_input "CONTAINER ID" "$(lxc_wizard_text 1 "$max_step" "Set Container ID")" "${CTID:-$(next_lxc_id)}")"; then
          return 1
        fi
        if validate_integer "$selection"; then
          CTID="$selection"
          ((step++))
          break
        fi
        show_dialog_message "INVALID CONTAINER ID" "Container ID must be a numeric value."
      done
      ;;
    2)
      while true; do
        if ! selection="$(prompt_input "HOSTNAME" "$(lxc_wizard_text 2 "$max_step" "Set Hostname")" "${CT_HOSTNAME:-semaphore}")"; then
          ((step--))
          break
        fi
        if validate_hostname "$selection"; then
          CT_HOSTNAME="$selection"
          ((step++))
          break
        fi
        show_dialog_message "INVALID HOSTNAME" "Hostname must start with a letter or number and may contain hyphens."
      done
      ;;
    3)
      if ! selection="$(prompt_radiolist "OPERATING SYSTEM" "$(lxc_wizard_text 3 "$max_step" "Select Operating System")" "${OS_ID}-${OS_VERSION}" \
        "ubuntu-24.04" "Ubuntu 24.04 LTS" \
        "debian-12" "Debian 12")"; then
        ((step--))
        continue
      fi
      OS_ID="${selection%-*}"
      OS_VERSION="${selection#*-}"
      ((step++))
      ;;
    4)
      while true; do
        if ! selection="$(prompt_input "CPU CORES" "$(lxc_wizard_text 4 "$max_step" "Set CPU Cores")" "${CT_CORES:-2}")"; then
          ((step--))
          break
        fi
        if validate_integer "$selection"; then
          CT_CORES="$selection"
          ((step++))
          break
        fi
        show_dialog_message "INVALID CPU VALUE" "CPU cores must be a positive integer."
      done
      ;;
    5)
      while true; do
        if ! selection="$(prompt_input "RAM" "$(lxc_wizard_text 5 "$max_step" "Set RAM in MiB")" "${CT_MEMORY:-2048}")"; then
          ((step--))
          break
        fi
        if validate_integer "$selection"; then
          CT_MEMORY="$selection"
          ((step++))
          break
        fi
        show_dialog_message "INVALID RAM VALUE" "RAM must be a positive integer in MiB."
      done
      ;;
    6)
      while true; do
        if ! selection="$(prompt_input "DISK SIZE" "$(lxc_wizard_text 6 "$max_step" "Set Disk Size in GiB")" "${CT_DISK:-4}")"; then
          ((step--))
          break
        fi
        if validate_integer "$selection"; then
          CT_DISK="$selection"
          ((step++))
          break
        fi
        show_dialog_message "INVALID DISK VALUE" "Disk size must be a positive integer in GiB."
      done
      ;;
    7)
      if ! selection="$(pve_pick_bridge "${CT_BRIDGE:-}" "NETWORK BRIDGE" "$(lxc_wizard_text 7 "$max_step" "Select the bridge for this container")")"; then
        ((step--))
        continue
      fi
      CT_BRIDGE="$selection"
      ((step++))
      ;;
    8)
      if ! selection="$(prompt_radiolist "IP ADDRESS" "$(lxc_wizard_text 8 "$max_step" "Select IPv4 address mode")" "${CT_NETWORK_MODE:-dhcp}" \
        "dhcp" "Automatic DHCP address" \
        "static" "Manual static IPv4 address")"; then
        ((step--))
        continue
      fi
      CT_NETWORK_MODE="$selection"
      if [[ "$CT_NETWORK_MODE" == "dhcp" ]]; then
        CT_IPV4_CIDR=""
        CT_GATEWAY=""
        step=11
      else
        ((step++))
      fi
      ;;
    9)
      while true; do
        if ! selection="$(prompt_input "STATIC IPV4" "$(lxc_wizard_text 9 "$max_step" "Set a static IPv4 CIDR address")" "${CT_IPV4_CIDR:-}")"; then
          ((step--))
          break
        fi
        if validate_ipv4_cidr "$selection"; then
          CT_IPV4_CIDR="$selection"
          ((step++))
          break
        fi
        show_dialog_message "INVALID IP ADDRESS" "Enter a valid IPv4 CIDR address such as 192.168.1.50/24."
      done
      ;;
    10)
      while true; do
        if ! selection="$(prompt_input "GATEWAY" "$(lxc_wizard_text 10 "$max_step" "Set the IPv4 gateway")" "${CT_GATEWAY:-}")"; then
          ((step--))
          break
        fi
        if validate_ipv4 "$selection"; then
          CT_GATEWAY="$selection"
          ((step++))
          break
        fi
        show_dialog_message "INVALID GATEWAY" "Enter a valid IPv4 gateway such as 192.168.1.1."
      done
      ;;
    11)
      selected_flags=""
      [[ "${CT_UNPRIVILEGED:-1}" == "1" ]] && selected_flags+="unprivileged "
      [[ "${CT_ONBOOT:-1}" == "1" ]] && selected_flags+="onboot "
      [[ "${CT_IPV6_METHOD:-auto}" != "disable" ]] && selected_flags+="ipv6 "
      if ! selection="$(prompt_checklist "CONTAINER OPTIONS" "$(lxc_wizard_text 11 "$max_step" $'Select container options.\nUse Space to toggle and Enter to confirm.')" "$selected_flags" \
        "unprivileged" "Recommended for most applications" \
        "onboot" "Start the container at boot" \
        "ipv6" "Keep IPv6 enabled")"; then
        if [[ "$CT_NETWORK_MODE" == "dhcp" ]]; then
          step=8
        else
          step=10
        fi
        continue
      fi
      CT_UNPRIVILEGED="0"
      CT_ONBOOT="0"
      CT_IPV6_METHOD="disable"
      while IFS= read -r selected_flag; do
        case "$selected_flag" in
        unprivileged) CT_UNPRIVILEGED="1" ;;
        onboot) CT_ONBOOT="1" ;;
        ipv6) CT_IPV6_METHOD="auto" ;;
        esac
      done <<<"$selection"
      ((step++))
      ;;
    12)
      if ! selection="$(prompt_input "TAGS" "$(lxc_wizard_text 12 "$max_step" "Optional tags (comma separated)")" "${CT_TAGS:-}")"; then
        ((step--))
        continue
      fi
      CT_TAGS="$selection"
      ((step++))
      ;;
    13)
      if ! selection="$(pve_pick_storage "vztmpl" "TEMPLATE STORAGE" "$(lxc_wizard_text 13 "$max_step" "Select template storage")" "${CT_TEMPLATE_STORAGE:-}")"; then
        ((step--))
        continue
      fi
      CT_TEMPLATE_STORAGE="$selection"
      ((step++))
      ;;
    14)
      if ! selection="$(pve_pick_storage "rootdir" "CONTAINER STORAGE" "$(lxc_wizard_text 14 "$max_step" "Select container storage")" "${CT_CONTAINER_STORAGE:-}")"; then
        ((step--))
        continue
      fi
      CT_CONTAINER_STORAGE="$selection"
      return 0
      ;;
    esac
  done
}

lxc_summary_text() {
  local ipv4_value="DHCP"
  local ipv6_value="Disabled"
  local type_value="Privileged"
  local onboot_value="No"

  if [[ "${CT_NETWORK_MODE}" != "dhcp" ]]; then
    ipv4_value="${CT_IPV4_CIDR} via ${CT_GATEWAY}"
  fi
  if [[ "${CT_IPV6_METHOD}" == "auto" ]]; then
    ipv6_value="Auto"
  fi
  if [[ "${CT_UNPRIVILEGED}" == "1" ]]; then
    type_value="Unprivileged"
  fi
  if [[ "${CT_ONBOOT}" == "1" ]]; then
    onboot_value="Yes"
  fi

  cat <<EOF
App:              ${APP_NAME}
CTID:             ${CTID}
Hostname:         ${CT_HOSTNAME}
OS:               ${OS_ID} ${OS_VERSION}
CPU:              ${CT_CORES} core(s)
Memory:           ${CT_MEMORY} MiB
Disk:             ${CT_DISK} GiB
Bridge:           ${CT_BRIDGE}
IPv4:             ${ipv4_value}
IPv6:             ${ipv6_value}
Type:             ${type_value}
Start at boot:    ${onboot_value}
Tags:             ${CT_TAGS:-none}
Template storage: ${CT_TEMPLATE_STORAGE}
Container store:  ${CT_CONTAINER_STORAGE}
EOF
}

lxc_confirm_settings() {
  local summary
  summary="$(lxc_summary_text)"

  if command_exists whiptail; then
    run_whiptail_confirm whiptail --backtitle "$HOMELAB_WHIPTAIL_BACKTITLE" --title "CONFIRM SETTINGS" --yesno "$summary" 20 78
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
