#!/usr/bin/env bash

set -Eeuo pipefail

DEFAULT_HOSTNAME="semaphore"
DEFAULT_CORES=2
DEFAULT_MEMORY=2048
DEFAULT_SWAP=512
DEFAULT_DISK=8
DEFAULT_BRIDGE="vmbr0"
DEFAULT_TEMPLATE_STORAGE="local"
DEFAULT_CONTAINER_STORAGE="local-lvm"
DEFAULT_TEMPLATE="ubuntu-24.04-standard_24.04-2_amd64.tar.zst"
DEFAULT_START_ON_BOOT=1
DEFAULT_UNPRIVILEGED=1
DEFAULT_SEMAPHORE_PORT=3000

CTID=""
HOSTNAME="$DEFAULT_HOSTNAME"
CORES="$DEFAULT_CORES"
MEMORY="$DEFAULT_MEMORY"
SWAP="$DEFAULT_SWAP"
DISK="$DEFAULT_DISK"
BRIDGE="$DEFAULT_BRIDGE"
VLAN_TAG=""
IP_CONFIG="dhcp"
GATEWAY=""
TEMPLATE_STORAGE="$DEFAULT_TEMPLATE_STORAGE"
CONTAINER_STORAGE="$DEFAULT_CONTAINER_STORAGE"
TEMPLATE_NAME="$DEFAULT_TEMPLATE"
START_ON_BOOT="$DEFAULT_START_ON_BOOT"
UNPRIVILEGED="$DEFAULT_UNPRIVILEGED"
ROOT_PASSWORD=""
SEMAPHORE_ADMIN_LOGIN="admin"
SEMAPHORE_ADMIN_NAME="Administrator"
SEMAPHORE_ADMIN_EMAIL="admin@homelab.local"
SEMAPHORE_ADMIN_PASSWORD=""

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

prompt_with_default() {
  local label=$1
  local default_value=$2
  local result

  read -r -p "$label [$default_value]: " result
  if [[ -z "$result" ]]; then
    printf '%s\n' "$default_value"
  else
    printf '%s\n' "$result"
  fi
}

prompt_secret_with_default() {
  local label=$1
  local default_value=$2
  local result

  read -r -s -p "$label [$default_value]: " result
  printf '\n'
  if [[ -z "$result" ]]; then
    printf '%s\n' "$default_value"
  else
    printf '%s\n' "$result"
  fi
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

validate_ip_config() {
  [[ "$1" == "dhcp" || "$1" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}/[0-9]{1,2}$ ]]
}

validate_optional_vlan() {
  [[ -z "$1" || "$1" =~ ^[0-9]+$ ]]
}

choose_mode() {
  local choice
  printf 'Select setup mode:\n'
  printf '1. Default\n'
  printf '2. Advanced\n'
  read -r -p 'Choice [1]: ' choice
  if [[ -z "$choice" || "$choice" == "1" ]]; then
    printf '%s\n' 'default'
  elif [[ "$choice" == "2" ]]; then
    printf '%s\n' 'advanced'
  else
    fail 'Invalid mode selection'
  fi
}

configure_default_settings() {
  CTID=$(next_container_id)
  ROOT_PASSWORD=$(generate_password)
  SEMAPHORE_ADMIN_PASSWORD=$(generate_password)
}

configure_advanced_settings() {
  local suggested_ctid

  suggested_ctid=$(next_container_id)
  CTID=$(prompt_with_default 'Container ID' "$suggested_ctid")
  validate_container_id "$CTID" || fail "Container ID $CTID is invalid or already in use"

  HOSTNAME=$(prompt_with_default 'Hostname' "$HOSTNAME")
  CORES=$(prompt_with_default 'CPU cores' "$CORES")
  MEMORY=$(prompt_with_default 'Memory in MiB' "$MEMORY")
  SWAP=$(prompt_with_default 'Swap in MiB' "$SWAP")
  DISK=$(prompt_with_default 'Disk size in GiB' "$DISK")
  BRIDGE=$(prompt_with_default 'Bridge' "$BRIDGE")
  VLAN_TAG=$(prompt_with_default 'VLAN tag, leave blank for none' "$VLAN_TAG")
  IP_CONFIG=$(prompt_with_default 'IPv4 config, use dhcp or CIDR like 192.168.1.20/24' "$IP_CONFIG")

  if [[ "$IP_CONFIG" != 'dhcp' ]]; then
    GATEWAY=$(prompt_with_default 'Gateway' "$GATEWAY")
  fi

  START_ON_BOOT=$(prompt_with_default 'Start on boot, 1 or 0' "$START_ON_BOOT")
  UNPRIVILEGED=$(prompt_with_default 'Unprivileged container, 1 or 0' "$UNPRIVILEGED")
  TEMPLATE_STORAGE=$(prompt_with_default 'Template storage' "$TEMPLATE_STORAGE")
  CONTAINER_STORAGE=$(prompt_with_default 'Container storage' "$CONTAINER_STORAGE")
  TEMPLATE_NAME=$(prompt_with_default 'LXC template name' "$TEMPLATE_NAME")
  ROOT_PASSWORD=$(prompt_secret_with_default 'Linux root password' "$(generate_password)")
  SEMAPHORE_ADMIN_LOGIN=$(prompt_with_default 'Semaphore admin login' "$SEMAPHORE_ADMIN_LOGIN")
  SEMAPHORE_ADMIN_NAME=$(prompt_with_default 'Semaphore admin name' "$SEMAPHORE_ADMIN_NAME")
  SEMAPHORE_ADMIN_EMAIL=$(prompt_with_default 'Semaphore admin email' "$SEMAPHORE_ADMIN_EMAIL")
  SEMAPHORE_ADMIN_PASSWORD=$(prompt_secret_with_default 'Semaphore admin password' "$(generate_password)")
}

collect_identity_defaults() {
  SEMAPHORE_ADMIN_LOGIN=$(prompt_with_default 'Semaphore admin login' "$SEMAPHORE_ADMIN_LOGIN")
  SEMAPHORE_ADMIN_NAME=$(prompt_with_default 'Semaphore admin name' "$SEMAPHORE_ADMIN_NAME")
  SEMAPHORE_ADMIN_EMAIL=$(prompt_with_default 'Semaphore admin email' "$SEMAPHORE_ADMIN_EMAIL")
}

validate_settings() {
  validate_container_id "$CTID" || fail "Container ID $CTID is invalid or already in use"
  validate_integer "$CORES" || fail 'CPU cores must be numeric'
  validate_integer "$MEMORY" || fail 'Memory must be numeric'
  validate_integer "$SWAP" || fail 'Swap must be numeric'
  validate_integer "$DISK" || fail 'Disk size must be numeric'
  validate_integer "$START_ON_BOOT" || fail 'Start on boot must be 1 or 0'
  validate_integer "$UNPRIVILEGED" || fail 'Unprivileged flag must be 1 or 0'
  validate_ip_config "$IP_CONFIG" || fail 'IPv4 config must be dhcp or CIDR notation'
  validate_optional_vlan "$VLAN_TAG" || fail 'VLAN tag must be blank or numeric'
  [[ -n "$ROOT_PASSWORD" ]] || fail 'Linux root password cannot be empty'
  [[ -n "$SEMAPHORE_ADMIN_LOGIN" ]] || fail 'Semaphore admin login cannot be empty'
  [[ -n "$SEMAPHORE_ADMIN_NAME" ]] || fail 'Semaphore admin name cannot be empty'
  [[ -n "$SEMAPHORE_ADMIN_EMAIL" ]] || fail 'Semaphore admin email cannot be empty'
  [[ -n "$SEMAPHORE_ADMIN_PASSWORD" ]] || fail 'Semaphore admin password cannot be empty'
}

template_exists() {
  pveam list "$TEMPLATE_STORAGE" | awk '{print $2}' | grep -Fx "$TEMPLATE_NAME" >/dev/null 2>&1
}

ensure_template() {
  if template_exists; then
    log_info "Using cached template $TEMPLATE_NAME from storage $TEMPLATE_STORAGE"
    return
  fi

  log_info "Downloading template $TEMPLATE_NAME to storage $TEMPLATE_STORAGE"
  pveam download "$TEMPLATE_STORAGE" "$TEMPLATE_NAME"
}

build_net0() {
  local net0
  net0="name=eth0,bridge=${BRIDGE},ip=${IP_CONFIG}"

  if [[ -n "$VLAN_TAG" ]]; then
    net0+=";tag=${VLAN_TAG}"
  fi

  if [[ "$IP_CONFIG" != 'dhcp' && -n "$GATEWAY" ]]; then
    net0+=";gw=${GATEWAY}"
  fi

  printf '%s\n' "$net0" | tr ';' ','
}

print_summary() {
  cat <<EOF

Semaphore bootstrap summary
--------------------------
Container ID:            $CTID
Hostname:                $HOSTNAME
CPU cores:               $CORES
Memory MiB:              $MEMORY
Swap MiB:                $SWAP
Disk GiB:                $DISK
Bridge:                  $BRIDGE
VLAN tag:                ${VLAN_TAG:-none}
IPv4 config:             $IP_CONFIG
Gateway:                 ${GATEWAY:-none}
Template storage:        $TEMPLATE_STORAGE
Container storage:       $CONTAINER_STORAGE
Template name:           $TEMPLATE_NAME
Start on boot:           $START_ON_BOOT
Unprivileged:            $UNPRIVILEGED
Semaphore admin login:   $SEMAPHORE_ADMIN_LOGIN
Semaphore admin email:   $SEMAPHORE_ADMIN_EMAIL

EOF
}

confirm_summary() {
  local answer
  read -r -p 'Create this Semaphore LXC? [y/N]: ' answer
  [[ "$answer" =~ ^([yY][eE][sS]|[yY])$ ]] || fail 'Aborted by user'
}

create_container() {
  local net0

  net0=$(build_net0)

  log_info "Creating LXC container $CTID"
  pct create "$CTID" "${TEMPLATE_STORAGE}:vztmpl/${TEMPLATE_NAME}" \
    -arch amd64 \
    -hostname "$HOSTNAME" \
    -cores "$CORES" \
    -memory "$MEMORY" \
    -swap "$SWAP" \
    -rootfs "${CONTAINER_STORAGE}:${DISK}" \
    -net0 "$net0" \
    -password "$ROOT_PASSWORD" \
    -onboot "$START_ON_BOOT" \
    -unprivileged "$UNPRIVILEGED" \
    -features nesting=1,keyctl=1
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
  local escaped_login escaped_name escaped_email escaped_password

  escaped_login=$(printf '%q' "$SEMAPHORE_ADMIN_LOGIN")
  escaped_name=$(printf '%q' "$SEMAPHORE_ADMIN_NAME")
  escaped_email=$(printf '%q' "$SEMAPHORE_ADMIN_EMAIL")
  escaped_password=$(printf '%q' "$SEMAPHORE_ADMIN_PASSWORD")

  log_info "Installing Semaphore, SQLite, and Ansible inside container $CTID"
  pct exec "$CTID" -- bash -lc "export DEBIAN_FRONTEND=noninteractive
set -Eeuo pipefail
apt-get update
apt-get install -y curl gpg sqlite3 ansible
mkdir -p /etc/apt/keyrings
curl -fsSL https://apt.semaphoreui.com/semaphoreui.key | gpg --dearmor -o /etc/apt/keyrings/semaphoreui.gpg
echo 'deb [signed-by=/etc/apt/keyrings/semaphoreui.gpg] https://apt.semaphoreui.com stable main' >/etc/apt/sources.list.d/semaphoreui.list
apt-get update
apt-get install -y semaphore
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
Linux root password: ${ROOT_PASSWORD}
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

  ip_value=$(container_ip)

  cat <<EOF

Semaphore bootstrap completed.

Container ID:          $CTID
Hostname:              $HOSTNAME
Container IP:          ${ip_value:-unknown}
Semaphore URL:         http://${ip_value:-<container-ip>}:${DEFAULT_SEMAPHORE_PORT}
Linux root user:       root
Linux root password:   $ROOT_PASSWORD
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
  local mode

  ensure_root
  ensure_proxmox_host
  mode=$(choose_mode)

  if [[ "$mode" == 'default' ]]; then
    configure_default_settings
    collect_identity_defaults
  else
    configure_advanced_settings
  fi

  validate_settings
  ensure_template
  print_summary
  confirm_summary
  create_container
  start_container
  wait_for_container_network
  install_semaphore_stack
  print_completion
}

main "$@"