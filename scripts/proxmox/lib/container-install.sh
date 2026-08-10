#!/usr/bin/env bash

if [[ -n "${HOMELAB_PROXMOX_CONTAINER_INSTALL_LOADED:-}" ]]; then
  return 0
fi
HOMELAB_PROXMOX_CONTAINER_INSTALL_LOADED=1

setting_up_container() {
  local retries=30
  local attempt

  msg_info "Setting up container OS"
  for ((attempt = 1; attempt <= retries; attempt++)); do
    if hostname -I | grep -q "[0-9A-Fa-f:.]"; then
      break
    fi
    sleep 2
  done

  hostname -I | grep -q "[0-9A-Fa-f:.]" || die "No network detected inside the container."
  rm -f /usr/lib/python3.*/EXTERNALLY-MANAGED
  systemctl disable -q --now systemd-networkd-wait-online.service >/dev/null 2>&1 || true
  msg_ok "Container OS is ready"
}

network_check() {
  msg_info "Checking network connectivity"
  ping -c 1 -W 1 1.1.1.1 >/dev/null 2>&1 || die "IPv4 connectivity check failed."
  getent hosts github.com >/dev/null 2>&1 || die "DNS lookup for github.com failed."
  getent hosts raw.githubusercontent.com >/dev/null 2>&1 || die "DNS lookup for raw.githubusercontent.com failed."
  msg_ok "Network connectivity looks good"
}

update_os() {
  export DEBIAN_FRONTEND=noninteractive
  run_with_progress "Updating package metadata" apt-get update
  run_with_progress "Upgrading container packages" apt-get -y upgrade
  run_with_progress "Installing required base packages" apt-get install -y curl ca-certificates
  msg_ok "Container OS is up to date"
}

arch_resolve() {
  case "$(dpkg --print-architecture)" in
  amd64) printf '%s' "amd64" ;;
  arm64) printf '%s' "arm64" ;;
  *)
    die "Unsupported architecture: $(dpkg --print-architecture)"
    ;;
  esac
}

fetch_github_release_asset() {
  local repo="$1"
  local asset_pattern="$2"
  local asset_url
  local asset_file

  asset_url="$(
    curl -fsSL "https://api.github.com/repos/${repo}/releases/latest" |
      grep -Eo '"browser_download_url":\s*"[^"]+"' |
      cut -d'"' -f4 |
      grep -E "${asset_pattern}" |
      head -n1
  )"
  [[ -n "$asset_url" ]] || die "Unable to locate a release asset matching ${asset_pattern}."

  asset_file="/tmp/$(basename "$asset_url")"
  run_with_progress "Downloading release asset $(basename "$asset_url")" curl -fsSL "$asset_url" -o "$asset_file"
  printf '%s' "$asset_file"
}

install_github_deb_release() {
  local repo="$1"
  local asset_pattern="$2"
  local asset_file

  asset_file="$(fetch_github_release_asset "$repo" "$asset_pattern")"
  run_with_progress "Installing package $(basename "$asset_file")" apt-get install -y "$asset_file"
  rm -f "$asset_file"
}

get_primary_ip() {
  hostname -I | awk '{print $1}'
}

write_app_marker() {
  mkdir -p /etc/homelab-proxmox
  cat <<EOF >/etc/homelab-proxmox/app.env
APP_NAME=${APP_NAME}
APP_SLUG=${APP_SLUG}
EOF
}

create_update_wrapper() {
  local wrapper_name="$1"
  local script_path="$2"

  cat <<EOF >/usr/local/bin/${wrapper_name}
#!/usr/bin/env bash
set -euo pipefail
export APP_ACTION=update
export APP_NAME="${APP_NAME}"
export APP_SLUG="${APP_SLUG}"
export IPV6_METHOD="${IPV6_METHOD:-auto}"
export FUNCTIONS_FILE_PATH="\$(cat /opt/homelab-proxmox/lib/container-functions.sh)"
bash ${script_path}
EOF
  chmod 755 "/usr/local/bin/${wrapper_name}"
}

motd_ssh() {
  local app_url="${APP_URL:-N/A}"
  local update_hint="${APP_UPDATE_HINT:-N/A}"
  local ip_address

  ip_address="$(get_primary_ip)"
  cat <<EOF >/etc/motd

  HomeLab Proxmox Scripts

  Application: ${APP_NAME}
  Hostname:    $(hostname)
  IP Address:  ${ip_address}
  URL:         ${app_url}
  Update:      ${update_hint}

EOF
}

customize() {
  cat <<EOF >/etc/profile.d/homelab-proxmox.sh
#!/usr/bin/env bash
[[ "\$-" == *i* ]] || return 0
echo ""
echo "HomeLab Proxmox Scripts: ${APP_NAME}"
echo "Update command: ${APP_UPDATE_HINT:-N/A}"
EOF
  chmod 644 /etc/profile.d/homelab-proxmox.sh
}

cleanup_lxc() {
  export DEBIAN_FRONTEND=noninteractive
  apt-get autoremove -y >/dev/null 2>&1 || true
  apt-get autoclean -y >/dev/null 2>&1 || true
  rm -rf /tmp/* /var/tmp/*
}
