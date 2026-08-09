#!/usr/bin/env bash

set -Eeuo pipefail

SHARED_RAW_URL="https://raw.githubusercontent.com/AKruimink/HomeLab/main/scripts/shared/proxmox-ui.sh"
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)

if [[ -n "$SCRIPT_DIR" && -f "$SCRIPT_DIR/../shared/proxmox-ui.sh" ]]; then
  # shellcheck disable=SC1091
  source "$SCRIPT_DIR/../shared/proxmox-ui.sh"
else
  source <(curl -fsSL "$SHARED_RAW_URL")
fi

DEFAULT_HOSTNAME="semaphore"
DEFAULT_CORES=2
DEFAULT_MEMORY=2048
DEFAULT_SWAP=512
DEFAULT_DISK=8
DEFAULT_BRIDGE="vmbr0"
DEFAULT_TEMPLATE_STORAGE="local"
DEFAULT_CONTAINER_STORAGE="local-lvm"
DEFAULT_START_ON_BOOT=1
DEFAULT_UNPRIVILEGED=1
DEFAULT_SEMAPHORE_PORT=3000
DEFAULT_UBUNTU_VERSION="24.04"

CTID=""
HOSTNAME="$DEFAULT_HOSTNAME"
CORES="$DEFAULT_CORES"
MEMORY="$DEFAULT_MEMORY"
SWAP="$DEFAULT_SWAP"
DISK="$DEFAULT_DISK"
BRIDGE="$DEFAULT_BRIDGE"
VLAN_TAG=""
IP_CONFIG="dhcp"
IP_ADDRESS=""
GATEWAY=""
TEMPLATE_STORAGE="$DEFAULT_TEMPLATE_STORAGE"
CONTAINER_STORAGE="$DEFAULT_CONTAINER_STORAGE"
TEMPLATE_NAME=""
UBUNTU_VERSION="$DEFAULT_UBUNTU_VERSION"
START_ON_BOOT="$DEFAULT_START_ON_BOOT"
UNPRIVILEGED="$DEFAULT_UNPRIVILEGED"
ROOT_PASSWORD=""
SEMAPHORE_ADMIN_LOGIN="admin"
SEMAPHORE_ADMIN_NAME="Administrator"
SEMAPHORE_ADMIN_EMAIL="admin@homelab.local"
SEMAPHORE_ADMIN_PASSWORD=""
INSTALL_MODE="default"

log_info() {
  printf '[INFO] %s\n' "$1"
}

log_warn() {
  printf '[WARN] %s\n' "$1"
}

log_error() {
  printf '[ERROR] %s\n' "$1" >&2
}

fail() {
  log_error "$1"
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"
}

generate_password() {
  openssl rand -base64 18 | tr -dc 'A-Za-z0-9' | head -c 16
}

ensure_root() {
  [[ ${EUID:-$(id -u)} -eq 0 ]] || fail "Run this script as root on a Proxmox host"
}

ensure_proxmox_host() {
  require_command pct
  require_command pveam
  require_command pvesh
  require_command ip
  require_command openssl
  ui_require_whiptail
  command -v pveversion >/dev/null 2>&1 || fail "This script must run on a Proxmox VE host"
}

next_container_id() {
  pvesh get /cluster/nextid
}

validate_integer() {
  [[ "$1" =~ ^[0-9]+$ ]]
}

validate_container_id() {
  validate_integer "$1" || return 1
  ! pct status "$1" >/dev/null 2>&1
}

validate_hostname() {
  [[ "$1" =~ ^[a-z0-9]([a-z0-9.-]{0,251}[a-z0-9])?$ ]]
}

validate_optional_vlan() {
  [[ -z "$1" || "$1" =~ ^[0-9]+$ ]]
}

validate_ip_cidr() {
  [[ "$1" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}/[0-9]{1,2}$ ]]
}

reset_defaults() {
  CTID=$(next_container_id)
  HOSTNAME="$DEFAULT_HOSTNAME"
  CORES="$DEFAULT_CORES"
  MEMORY="$DEFAULT_MEMORY"
  SWAP="$DEFAULT_SWAP"
  DISK="$DEFAULT_DISK"
  BRIDGE="$DEFAULT_BRIDGE"
  VLAN_TAG=""
  IP_CONFIG="dhcp"
  IP_ADDRESS=""
  GATEWAY=""
  TEMPLATE_STORAGE="$DEFAULT_TEMPLATE_STORAGE"
  CONTAINER_STORAGE="$DEFAULT_CONTAINER_STORAGE"
  TEMPLATE_NAME=""
  UBUNTU_VERSION="$DEFAULT_UBUNTU_VERSION"
  START_ON_BOOT="$DEFAULT_START_ON_BOOT"
  UNPRIVILEGED="$DEFAULT_UNPRIVILEGED"
  ROOT_PASSWORD=""
  SEMAPHORE_ADMIN_LOGIN="admin"
  SEMAPHORE_ADMIN_NAME="Administrator"
  SEMAPHORE_ADMIN_EMAIL="admin@homelab.local"
  SEMAPHORE_ADMIN_PASSWORD=""
}

show_intro_menu() {
  local choice

  choice=$(ui_menu \
    "HomeLab Options" \
    "\nChoose an option:\n Use TAB or Arrow keys to navigate, ENTER to select.\n" \
    18 64 4 \
    "default" "Default Install" \
    "advanced" "Advanced Install" \
    "exit" "Exit Script") || exit 0

  case "$choice" in
    default)
      INSTALL_MODE="default"
      ;;
    advanced)
      INSTALL_MODE="advanced"
      ;;
    *)
      exit 0
      ;;
  esac
}

select_ubuntu_version() {
  local selected_version

  selected_version=$(ui_radiolist "UBUNTU VERSION" "\nChoose the Ubuntu template version:" 14 58 3 \
    "24.04" "Ubuntu 24.04 LTS" $([[ "$UBUNTU_VERSION" == "24.04" ]] && printf 'ON' || printf 'OFF') \
    "22.04" "Ubuntu 22.04 LTS" $([[ "$UBUNTU_VERSION" == "22.04" ]] && printf 'ON' || printf 'OFF') \
    "25.04" "Ubuntu 25.04" $([[ "$UBUNTU_VERSION" == "25.04" ]] && printf 'ON' || printf 'OFF')) || exit 0

  UBUNTU_VERSION="$selected_version"
  TEMPLATE_NAME=""
}

run_default_wizard() {
  local step=1
  local result=""

  while (( step <= 5 )); do
    case "$step" in
      1)
        if result=$(ui_password "ROOT PASSWORD" "\nSet Root Password for the container root user.\n\nLeave blank for automatic login (no password)." "Next" "Exit" 12 76); then
          ROOT_PASSWORD="$result"
          ((step++))
        else
          exit 0
        fi
        ;;
      2)
        if result=$(ui_input "SEMAPHORE LOGIN" "\nSet the initial Semaphore admin login." "$SEMAPHORE_ADMIN_LOGIN" "Next" "Back"); then
          [[ -n "$result" ]] || {
            ui_msg "SEMAPHORE LOGIN" "Semaphore admin login cannot be empty." 9 60
            continue
          }
          SEMAPHORE_ADMIN_LOGIN="$result"
          ((step++))
        else
          ((step--))
        fi
        ;;
      3)
        if result=$(ui_input "SEMAPHORE NAME" "\nSet the initial Semaphore admin display name." "$SEMAPHORE_ADMIN_NAME" "Next" "Back"); then
          [[ -n "$result" ]] || {
            ui_msg "SEMAPHORE NAME" "Semaphore admin name cannot be empty." 9 60
            continue
          }
          SEMAPHORE_ADMIN_NAME="$result"
          ((step++))
        else
          ((step--))
        fi
        ;;
      4)
        if result=$(ui_input "SEMAPHORE EMAIL" "\nSet the initial Semaphore admin email address." "$SEMAPHORE_ADMIN_EMAIL" "Next" "Back"); then
          [[ -n "$result" ]] || {
            ui_msg "SEMAPHORE EMAIL" "Semaphore admin email cannot be empty." 9 60
            continue
          }
          SEMAPHORE_ADMIN_EMAIL="$result"
          ((step++))
        else
          ((step--))
        fi
        ;;
      5)
        if result=$(ui_password "SEMAPHORE PASSWORD" "\nSet the initial Semaphore admin password.\n\nLeave blank to auto-generate one and show it at the end." "Next" "Back" 12 76); then
          SEMAPHORE_ADMIN_PASSWORD="$result"
          ((step++))
        else
          ((step--))
        fi
        ;;
    esac
  done
}

run_advanced_wizard() {
  local step=1
  local result=""
  local selected_ip_mode=""
  local ct_type_default_on="ON"
  local ct_type_default_off="OFF"

  while (( step <= 20 )); do
    case "$step" in
      1)
        [[ "$UNPRIVILEGED" == "0" ]] && {
          ct_type_default_on="OFF"
          ct_type_default_off="ON"
        }
        if result=$(ui_radiolist "CONTAINER TYPE" "\nChoose container type:\n\nUse SPACE to select, ENTER to confirm." 14 58 2 \
          "1" "Unprivileged (recommended)" "$ct_type_default_on" \
          "0" "Privileged" "$ct_type_default_off"); then
          UNPRIVILEGED="$result"
          ((step++))
        else
          exit 0
        fi
        ;;
      2)
        if result=$(ui_password "ROOT PASSWORD" "\nSet Root Password (needed for root SSH access)\n\nLeave blank for automatic login (no password)" "Next" "Back" 12 76); then
          ROOT_PASSWORD="$result"
          ((step++))
        else
          ((step--))
        fi
        ;;
      3)
        if result=$(ui_input "CONTAINER ID" "\nSet Container ID" "$CTID" "Next" "Back"); then
          if ! validate_container_id "$result"; then
            ui_msg "CONTAINER ID" "Container ID '$result' is invalid or already in use." 10 62
            continue
          fi
          CTID="$result"
          ((step++))
        else
          ((step--))
        fi
        ;;
      4)
        if result=$(ui_input "HOSTNAME" "\nSet Hostname (or FQDN), e.g. host.example.com" "$HOSTNAME" "Next" "Back"); then
          if [[ -z "$result" ]]; then
            ui_msg "HOSTNAME" "Hostname cannot be empty." 9 58
            continue
          fi
          if ! validate_hostname "$result"; then
            ui_msg "HOSTNAME" "Invalid hostname. Use lowercase letters, digits, dots, and hyphens." 10 66
            continue
          fi
          HOSTNAME="$result"
          ((step++))
        else
          ((step--))
        fi
        ;;
      5)
        if result=$(ui_input "DISK SIZE" "\nSet Disk Size in GB" "$DISK" "Next" "Back"); then
          validate_integer "$result" || {
            ui_msg "DISK SIZE" "Disk size must be a whole number." 9 58
            continue
          }
          DISK="$result"
          ((step++))
        else
          ((step--))
        fi
        ;;
      6)
        if result=$(ui_input "CPU CORES" "\nSet CPU Cores" "$CORES" "Next" "Back"); then
          validate_integer "$result" || {
            ui_msg "CPU CORES" "CPU cores must be a whole number." 9 58
            continue
          }
          CORES="$result"
          ((step++))
        else
          ((step--))
        fi
        ;;
      7)
        if result=$(ui_input "MEMORY" "\nSet Memory in MiB" "$MEMORY" "Next" "Back"); then
          validate_integer "$result" || {
            ui_msg "MEMORY" "Memory must be a whole number." 9 58
            continue
          }
          MEMORY="$result"
          ((step++))
        else
          ((step--))
        fi
        ;;
      8)
        if result=$(ui_input "SWAP" "\nSet Swap in MiB" "$SWAP" "Next" "Back"); then
          validate_integer "$result" || {
            ui_msg "SWAP" "Swap must be a whole number." 9 58
            continue
          }
          SWAP="$result"
          ((step++))
        else
          ((step--))
        fi
        ;;
      9)
        if result=$(ui_input "BRIDGE" "\nSet network bridge" "$BRIDGE" "Next" "Back"); then
          [[ -n "$result" ]] || {
            ui_msg "BRIDGE" "Bridge cannot be empty." 9 58
            continue
          }
          BRIDGE="$result"
          ((step++))
        else
          ((step--))
        fi
        ;;
      10)
        if result=$(ui_input "VLAN TAG" "\nSet VLAN tag or leave blank for none" "$VLAN_TAG" "Next" "Back"); then
          validate_optional_vlan "$result" || {
            ui_msg "VLAN TAG" "VLAN tag must be blank or numeric." 9 58
            continue
          }
          VLAN_TAG="$result"
          ((step++))
        else
          ((step--))
        fi
        ;;
      11)
        if selected_ip_mode=$(ui_radiolist "IPV4 CONFIG" "\nChoose network mode:" 14 58 2 \
          "dhcp" "DHCP" $([[ "$IP_CONFIG" == "dhcp" ]] && printf 'ON' || printf 'OFF') \
          "static" "Static" $([[ "$IP_CONFIG" == "static" ]] && printf 'ON' || printf 'OFF')); then
          IP_CONFIG="$selected_ip_mode"
          if [[ "$IP_CONFIG" == "dhcp" ]]; then
            IP_ADDRESS=""
            GATEWAY=""
          fi
          ((step++))
        else
          ((step--))
        fi
        ;;
      12)
        if [[ "$IP_CONFIG" == "dhcp" ]]; then
          ((step++))
          continue
        fi
        if result=$(ui_input "STATIC IPV4" "\nSet static IPv4 in CIDR format, e.g. 192.168.1.20/24" "$IP_ADDRESS" "Next" "Back"); then
          validate_ip_cidr "$result" || {
            ui_msg "STATIC IPV4" "IPv4 address must be in CIDR format." 9 62
            continue
          }
          IP_ADDRESS="$result"
          ((step++))
        else
          ((step--))
        fi
        ;;
      13)
        if [[ "$IP_CONFIG" == "dhcp" ]]; then
          ((step++))
          continue
        fi
        if result=$(ui_input "GATEWAY" "\nSet IPv4 gateway" "$GATEWAY" "Next" "Back"); then
          [[ -n "$result" ]] || {
            ui_msg "GATEWAY" "Gateway cannot be empty for static networking." 9 62
            continue
          }
          GATEWAY="$result"
          ((step++))
        else
          ((step--))
        fi
        ;;
      14)
        if ui_yesno "START ON BOOT" "\nStart container when the Proxmox host boots?" 11 60 "Yes" "No"; then
          START_ON_BOOT=1
        else
          START_ON_BOOT=0
        fi
        ((step++))
        ;;
      15)
        if result=$(ui_input "TEMPLATE STORAGE" "\nSet template storage name" "$TEMPLATE_STORAGE" "Next" "Back"); then
          [[ -n "$result" ]] || {
            ui_msg "TEMPLATE STORAGE" "Template storage cannot be empty." 9 62
            continue
          }
          TEMPLATE_STORAGE="$result"
          ((step++))
        else
          ((step--))
        fi
        ;;
      16)
        if result=$(ui_input "CONTAINER STORAGE" "\nSet container storage name" "$CONTAINER_STORAGE" "Next" "Back"); then
          [[ -n "$result" ]] || {
            ui_msg "CONTAINER STORAGE" "Container storage cannot be empty." 9 62
            continue
          }
          CONTAINER_STORAGE="$result"
          ((step++))
        else
          ((step--))
        fi
        ;;
      17)
        if result=$(ui_input "SEMAPHORE LOGIN" "\nSet the initial Semaphore admin login." "$SEMAPHORE_ADMIN_LOGIN" "Next" "Back"); then
          [[ -n "$result" ]] || {
            ui_msg "SEMAPHORE LOGIN" "Semaphore admin login cannot be empty." 9 62
            continue
          }
          SEMAPHORE_ADMIN_LOGIN="$result"
          ((step++))
        else
          ((step--))
        fi
        ;;
      18)
        if result=$(ui_input "SEMAPHORE NAME" "\nSet the initial Semaphore admin display name." "$SEMAPHORE_ADMIN_NAME" "Next" "Back"); then
          [[ -n "$result" ]] || {
            ui_msg "SEMAPHORE NAME" "Semaphore admin name cannot be empty." 9 62
            continue
          }
          SEMAPHORE_ADMIN_NAME="$result"
          ((step++))
        else
          ((step--))
        fi
        ;;
      19)
        if result=$(ui_input "SEMAPHORE EMAIL" "\nSet the initial Semaphore admin email address." "$SEMAPHORE_ADMIN_EMAIL" "Next" "Back"); then
          [[ -n "$result" ]] || {
            ui_msg "SEMAPHORE EMAIL" "Semaphore admin email cannot be empty." 9 62
            continue
          }
          SEMAPHORE_ADMIN_EMAIL="$result"
          ((step++))
        else
          ((step--))
        fi
        ;;
      20)
        if result=$(ui_password "SEMAPHORE PASSWORD" "\nSet the initial Semaphore admin password.\n\nLeave blank to auto-generate one and show it at the end." "Next" "Back" 12 76); then
          SEMAPHORE_ADMIN_PASSWORD="$result"
          ((step++))
        else
          ((step--))
        fi
        ;;
    esac
  done
}

build_net0() {
  local ip_value="dhcp"
  local net0

  if [[ "$IP_CONFIG" == "static" ]]; then
    ip_value="$IP_ADDRESS"
  fi

  net0="name=eth0,bridge=${BRIDGE},ip=${ip_value}"

  if [[ -n "$VLAN_TAG" ]]; then
    net0+=";tag=${VLAN_TAG}"
  fi

  if [[ "$IP_CONFIG" == "static" && -n "$GATEWAY" ]]; then
    net0+=";gw=${GATEWAY}"
  fi

  printf '%s\n' "$net0" | tr ';' ','
}

print_summary_text() {
  local root_display="(automatic login, no password)"
  local semaphore_password_display="(auto-generate)"
  local ip_display="DHCP"

  [[ -n "$ROOT_PASSWORD" ]] && root_display="(set)"
  [[ -n "$SEMAPHORE_ADMIN_PASSWORD" ]] && semaphore_password_display="(set)"
  [[ "$IP_CONFIG" == "static" ]] && ip_display="$IP_ADDRESS via $GATEWAY"

  cat <<EOF
Container Type:         $( [[ "$UNPRIVILEGED" == "1" ]] && printf 'Unprivileged' || printf 'Privileged' )
Container ID:           $CTID
Hostname:               $HOSTNAME

Resources:
  Disk:                 ${DISK} GB
  CPU:                  $CORES cores
  Memory:               ${MEMORY} MiB
  Swap:                 ${SWAP} MiB

Network:
  Bridge:               $BRIDGE
  VLAN:                 ${VLAN_TAG:-none}
  IPv4:                 $ip_display

Storage:
  Template storage:     $TEMPLATE_STORAGE
  Container storage:    $CONTAINER_STORAGE
  Template:             $TEMPLATE_NAME

Boot:
  Start on boot:        $( [[ "$START_ON_BOOT" == "1" ]] && printf 'yes' || printf 'no' )

Credentials:
  Root password:        $root_display
  Semaphore login:      $SEMAPHORE_ADMIN_LOGIN
  Semaphore name:       $SEMAPHORE_ADMIN_NAME
  Semaphore email:      $SEMAPHORE_ADMIN_EMAIL
  Semaphore password:   $semaphore_password_display
EOF
}

confirm_summary() {
  local summary
  summary=$(print_summary_text)

  if ui_yesno "CONFIRM SETTINGS" "$summary\n\nCreate Semaphore LXC with these settings?" 28 78 "Create LXC" "Do-Over"; then
    return 0
  fi

  return 1
}

validate_settings() {
  validate_container_id "$CTID" || fail "Container ID $CTID is invalid or already in use"
  validate_integer "$CORES" || fail 'CPU cores must be numeric'
  validate_integer "$MEMORY" || fail 'Memory must be numeric'
  validate_integer "$SWAP" || fail 'Swap must be numeric'
  validate_integer "$DISK" || fail 'Disk size must be numeric'
  validate_integer "$START_ON_BOOT" || fail 'Start on boot must be 1 or 0'
  validate_integer "$UNPRIVILEGED" || fail 'Unprivileged flag must be 1 or 0'
  validate_optional_vlan "$VLAN_TAG" || fail 'VLAN tag must be blank or numeric'
  [[ -n "$HOSTNAME" ]] || fail 'Hostname cannot be empty'
  [[ -n "$SEMAPHORE_ADMIN_LOGIN" ]] || fail 'Semaphore admin login cannot be empty'
  [[ -n "$SEMAPHORE_ADMIN_NAME" ]] || fail 'Semaphore admin name cannot be empty'
  [[ -n "$SEMAPHORE_ADMIN_EMAIL" ]] || fail 'Semaphore admin email cannot be empty'
  if [[ "$IP_CONFIG" == "static" ]]; then
    validate_ip_cidr "$IP_ADDRESS" || fail 'Static IPv4 must be in CIDR notation'
    [[ -n "$GATEWAY" ]] || fail 'Gateway cannot be empty for static IPv4'
  fi
}

template_exists() {
  pveam list "$TEMPLATE_STORAGE" | awk '{print $2}' | grep -Fx "$TEMPLATE_NAME" >/dev/null 2>&1
}

resolve_template_name() {
  local template_prefix
  local available_template

  pveam update >/dev/null 2>&1 || true
  template_prefix="ubuntu-${UBUNTU_VERSION}-standard_${UBUNTU_VERSION}-"
  available_template=$(pveam available --section system 2>/dev/null \
    | awk -v prefix="$template_prefix" '$2 ~ "^" prefix && $2 ~ /_amd64\.tar\.zst$/ {print $2}' \
    | sort -V \
    | tail -n1)

  if [[ -z "$available_template" ]]; then
    available_template=$(pveam available --section system 2>/dev/null \
      | awk -v prefix="$template_prefix" '$2 ~ "^" prefix && $2 ~ /_amd64\.tar\.zst$/ {print $2}' \
      | sort -V \
      | tail -n1)
  fi

  [[ -n "$available_template" ]] || fail "No Ubuntu ${UBUNTU_VERSION} template is available. Run 'pveam update' on the Proxmox host and try again."
  TEMPLATE_NAME="$available_template"
}

ensure_template() {
  resolve_template_name

  if template_exists; then
    log_info "Using cached template $TEMPLATE_NAME from storage $TEMPLATE_STORAGE"
    return
  fi

  log_info "Downloading template $TEMPLATE_NAME to storage $TEMPLATE_STORAGE"
  if ! pveam download "$TEMPLATE_STORAGE" "$TEMPLATE_NAME"; then
    log_info "Refreshing Proxmox template index and retrying"
    pveam update >/dev/null 2>&1 || true
    resolve_template_name
    pveam download "$TEMPLATE_STORAGE" "$TEMPLATE_NAME"
  fi
}

install_semaphore_binary() {
  local arch
  local asset_url
  local temp_deb

  arch=$(dpkg --print-architecture)
  asset_url=$(curl -fsSL https://api.github.com/repos/semaphoreui/semaphore/releases/latest \
    | grep -oE 'https://[^"[:space:]]+\.deb' \
    | grep -E "linux_${arch}\.deb|_${arch}\.deb" \
    | head -n1)

  [[ -n "$asset_url" ]] || fail "Could not find a Semaphore .deb for architecture '$arch'"

  temp_deb=$(mktemp --suffix=.deb)
  log_info "Downloading Semaphore package"
  curl -fL "$asset_url" -o "$temp_deb"
  log_info "Installing Semaphore package"
  dpkg -i "$temp_deb" || apt-get -f install -y
  rm -f "$temp_deb"
}

finalize_generated_values() {
  if [[ -z "$SEMAPHORE_ADMIN_PASSWORD" ]]; then
    SEMAPHORE_ADMIN_PASSWORD=$(generate_password)
  fi
}

create_container() {
  local net0
  local pct_args

  net0=$(build_net0)
  pct_args=(
    create "$CTID" "${TEMPLATE_STORAGE}:vztmpl/${TEMPLATE_NAME}"
    -arch amd64
    -hostname "$HOSTNAME"
    -cores "$CORES"
    -memory "$MEMORY"
    -swap "$SWAP"
    -rootfs "${CONTAINER_STORAGE}:${DISK}"
    -net0 "$net0"
    -onboot "$START_ON_BOOT"
    -unprivileged "$UNPRIVILEGED"
    -features nesting=1,keyctl=1
  )

  if [[ -n "$ROOT_PASSWORD" ]]; then
    pct_args+=(-password "$ROOT_PASSWORD")
  fi

  log_info "Creating LXC container $CTID"
  pct "${pct_args[@]}"
}

start_container() {
  log_info "Starting LXC container $CTID"
  pct start "$CTID"
}

wait_for_container_network() {
  local attempts=30
  local ip_value=''

  log_info 'Waiting for container network'
  while (( attempts > 0 )); do
    ip_value=$(pct exec "$CTID" -- bash -lc "hostname -I 2>/dev/null | awk '{print \$1}'") || true
    if [[ -n "${ip_value// /}" ]]; then
      return 0
    fi
    attempts=$((attempts - 1))
    sleep 2
  done

  log_warn 'Container network did not report an address during the wait window'
  return 0
}

install_semaphore_stack() {
  local escaped_login escaped_name escaped_email escaped_password root_password_display

  escaped_login=$(printf '%q' "$SEMAPHORE_ADMIN_LOGIN")
  escaped_name=$(printf '%q' "$SEMAPHORE_ADMIN_NAME")
  escaped_email=$(printf '%q' "$SEMAPHORE_ADMIN_EMAIL")
  escaped_password=$(printf '%q' "$SEMAPHORE_ADMIN_PASSWORD")
  root_password_display=${ROOT_PASSWORD:-automatic-login-no-password}

  log_info "Installing Semaphore, SQLite, and Ansible inside container $CTID"
  pct exec "$CTID" -- bash -lc "export DEBIAN_FRONTEND=noninteractive
set -Eeuo pipefail
apt-get update
apt-get install -y curl gpg sqlite3 ansible
$(declare -f install_semaphore_binary)
install_semaphore_binary
install -d -m 0755 /opt/semaphore/tmp
COOKIE_HASH=\$(openssl rand -base64 32)
COOKIE_ENCRYPTION=\$(openssl rand -base64 32)
ACCESS_KEY_ENCRYPTION=\$(openssl rand -base64 32)
cat >/opt/semaphore/config.json <<'EOF'
{
  \"sqlite\": {
    \"host\": \"/opt/semaphore/database.sqlite\"
  },
  \"dialect\": \"sqlite\",
  \"port\": ${DEFAULT_SEMAPHORE_PORT},
  \"interface\": \"0.0.0.0\",
  \"tmp_path\": \"/opt/semaphore/tmp\",
  \"cookie_hash\": \"\${COOKIE_HASH}\",
  \"cookie_encryption\": \"\${COOKIE_ENCRYPTION}\",
  \"access_key_encryption\": \"\${ACCESS_KEY_ENCRYPTION}\"
}
EOF
if ! semaphore user list --config /opt/semaphore/config.json >/dev/null 2>&1; then
  semaphore user add --admin --login ${escaped_login} --name ${escaped_name} --email ${escaped_email} --password ${escaped_password} --config /opt/semaphore/config.json
fi
cat >/etc/systemd/system/semaphore.service <<'EOF'
[Unit]
Description=Semaphore UI
Documentation=https://docs.semaphoreui.com/
Wants=network-online.target
After=network-online.target

[Service]
ExecStart=/usr/bin/semaphore server --config /opt/semaphore/config.json
Restart=always
RestartSec=10s

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now semaphore
cat >/root/semaphore-bootstrap.creds <<EOF
Linux root user: root
Linux root password: ${root_password_display}
Semaphore URL: http://\$(hostname -I | awk '{print \$1}'):${DEFAULT_SEMAPHORE_PORT}
Semaphore login: ${SEMAPHORE_ADMIN_LOGIN}
Semaphore email: ${SEMAPHORE_ADMIN_EMAIL}
Semaphore password: ${SEMAPHORE_ADMIN_PASSWORD}
EOF
chmod 600 /root/semaphore-bootstrap.creds"
}

container_ip() {
  pct exec "$CTID" -- bash -lc "hostname -I 2>/dev/null | awk '{print \$1}'" 2>/dev/null || true
}

print_completion() {
  local ip_value
  local root_password_display="(automatic login, no password)"

  ip_value=$(container_ip)
  [[ -n "$ROOT_PASSWORD" ]] && root_password_display="$ROOT_PASSWORD"

  cat <<EOF

Semaphore bootstrap completed.

Container ID:          $CTID
Hostname:              $HOSTNAME
Container IP:          ${ip_value:-unknown}
Semaphore URL:         http://${ip_value:-<container-ip>}:${DEFAULT_SEMAPHORE_PORT}
Linux root user:       root
Linux root password:   $root_password_display
Semaphore login:       $SEMAPHORE_ADMIN_LOGIN
Semaphore email:       $SEMAPHORE_ADMIN_EMAIL
Semaphore password:    $SEMAPHORE_ADMIN_PASSWORD

Credentials are also stored inside the container at /root/semaphore-bootstrap.creds.

Next steps:
1. Log in to Semaphore.
2. Connect this repository.
3. Add Ansible and OpenTofu task templates.

EOF
}

main() {
  ensure_root
  ensure_proxmox_host

  while true; do
    reset_defaults
    show_intro_menu
    select_ubuntu_version

    if [[ "$INSTALL_MODE" == "default" ]]; then
      run_default_wizard
    else
      run_advanced_wizard
    fi

    if confirm_summary; then
      break
    fi
  done

  finalize_generated_values
  validate_settings
  ensure_template
  create_container
  start_container
  wait_for_container_network
  install_semaphore_stack
  print_completion
}

main "$@"