#!/usr/bin/env bash

if [[ -n "${HOMELAB_PROXMOX_COMMON_LOADED:-}" ]]; then
  return 0
fi
HOMELAB_PROXMOX_COMMON_LOADED=1

HOMELAB_PROXMOX_DEFAULT_BASE="${HOMELAB_PROXMOX_DEFAULT_BASE:-https://raw.githubusercontent.com/AKruimink/HomeLab/main/scripts/proxmox}"
HOMELAB_WHIPTAIL_BACKTITLE="${HOMELAB_WHIPTAIL_BACKTITLE:-Proxmox VE Helper Scripts}"

color() {
  YW=$'\033[33m'
  YWB=$'\033[93m'
  BL=$'\033[36m'
  RD=$'\033[31m'
  GN=$'\033[92m'
  BGN=$'\033[4;92m'
  CL=$'\033[m'
  BOLD=$'\033[1m'
}

formatting() {
  TAB="  "
  TAB3="      "
}

icons() {
  INFO="${TAB}💡${TAB}"
  OK_ICON="${TAB}✔${TAB}"
  WARN_ICON="${TAB}!${TAB}"
  ERR_ICON="${TAB}✖${TAB}"
}

load_common() {
  color
  formatting
  icons
}

msg_info() {
  echo -e "${INFO}${YW}$1${CL}" >&2
}

msg_ok() {
  echo -e "${OK_ICON}${GN}$1${CL}" >&2
}

msg_warn() {
  echo -e "${WARN_ICON}${YW}$1${CL}" >&2
}

msg_error() {
  echo -e "${ERR_ICON}${RD}$1${CL}" >&2
}

die() {
  msg_error "$1"
  exit "${2:-1}"
}

header_info() {
  clear
  echo -e "${BL}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${CL}"
  echo -e "${BOLD}${GN}  HomeLab Proxmox Scripts${CL}${BOLD} - ${1}${CL}"
  echo -e "${BL}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${CL}"
  echo ""
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

require_root() {
  [[ "$(id -u)" -eq 0 ]] || die "Please run this script as root."
}

require_proxmox_host() {
  command_exists pveversion || die "This script must run on a Proxmox VE host."
}

ensure_whiptail() {
  if command_exists whiptail; then
    return 0
  fi

  msg_info "Installing whiptail"
  apt-get update >/dev/null
  DEBIAN_FRONTEND=noninteractive apt-get install -y whiptail >/dev/null
  msg_ok "Installed whiptail"
}

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

validate_integer() {
  [[ "$1" =~ ^[0-9]+$ ]]
}

validate_hostname() {
  [[ "$1" =~ ^[a-zA-Z0-9][a-zA-Z0-9-]{0,62}$ ]]
}

generate_secret() {
  local length="${1:-24}"
  openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c "$length"
}

prompt_yes_no() {
  local title="$1"
  local question="$2"
  local default="${3:-yes}"

  if command_exists whiptail; then
    local yes_args=()
    local no_args=()
    if [[ "$default" == "no" ]]; then
      yes_args=(--defaultno)
    fi
    if whiptail --backtitle "$HOMELAB_WHIPTAIL_BACKTITLE" --title "$title" "${yes_args[@]}" --yesno "$question" 12 72; then
      return 0
    fi
    return 1
  fi

  local prompt="Y/n"
  [[ "$default" == "no" ]] && prompt="y/N"
  read -r -p "$question [$prompt] " reply
  reply="${reply:-$default}"
  [[ "${reply,,}" =~ ^(y|yes)$ ]]
}

prompt_input() {
  local title="$1"
  local prompt="$2"
  local default_value="${3:-}"
  local result

  if command_exists whiptail; then
    result=$(whiptail --backtitle "$HOMELAB_WHIPTAIL_BACKTITLE" --title "$title" --inputbox "$prompt" 12 72 "$default_value" 3>&1 1>&2 2>&3) || return 1
    printf '%s' "$result"
    return 0
  fi

  read -r -p "$prompt " result
  printf '%s' "${result:-$default_value}"
}

prompt_password() {
  local title="$1"
  local prompt="$2"
  local result

  if command_exists whiptail; then
    result=$(whiptail --backtitle "$HOMELAB_WHIPTAIL_BACKTITLE" --title "$title" --passwordbox "$prompt" 12 72 3>&1 1>&2 2>&3) || return 1
    printf '%s' "$result"
    return 0
  fi

  read -r -s -p "$prompt " result
  echo ""
  printf '%s' "$result"
}

prompt_menu() {
  local title="$1"
  local prompt="$2"
  shift 2

  if command_exists whiptail; then
    whiptail --backtitle "$HOMELAB_WHIPTAIL_BACKTITLE" --title "$title" --menu "$prompt" 20 78 10 "$@" 3>&1 1>&2 2>&3
    return $?
  fi

  local i=1
  local choice
  while (($#)); do
    echo "$i) $1 - $2"
    shift 2
    ((i++))
  done
  read -r -p "$prompt " choice
  printf '%s' "$choice"
}

prompt_default_or_advanced() {
  if command_exists whiptail; then
    if whiptail --backtitle "$HOMELAB_WHIPTAIL_BACKTITLE" --title "SETTINGS" --yesno "Use default settings?" --no-button "Advanced" 10 58; then
      printf '%s' "default"
    else
      printf '%s' "advanced"
    fi
    return 0
  fi

  if prompt_yes_no "SETTINGS" "Use default settings?" "yes"; then
    printf '%s' "default"
  else
    printf '%s' "advanced"
  fi
}

prompt_two_option_menu() {
  local title="$1"
  local prompt="$2"
  local option_a="$3"
  local option_a_desc="$4"
  local option_b="$5"
  local option_b_desc="$6"

  prompt_menu "$title" "$prompt" \
    "$option_a" "$option_a_desc" \
    "$option_b" "$option_b_desc"
}

next_lxc_id() {
  pvesh get /cluster/nextid
}

next_vmid() {
  pvesh get /cluster/nextid
}

get_repo_file_content() {
  local script_root="$1"
  local relative_path="$2"
  local local_path=""
  local base_url="${HOMELAB_PROXMOX_BASE:-$HOMELAB_PROXMOX_DEFAULT_BASE}"

  if [[ -n "$script_root" ]]; then
    local_path="${script_root}/${relative_path}"
    if [[ -f "$local_path" ]]; then
      cat "$local_path"
      return 0
    fi
  fi

  curl -fsSL "${base_url}/${relative_path}"
}

proxmox_remote_base() {
  printf '%s' "${HOMELAB_PROXMOX_BASE:-$HOMELAB_PROXMOX_DEFAULT_BASE}"
}

proxmox_remote_entrypoint() {
  local relative_path="$1"
  printf '%s/%s' "$(proxmox_remote_base)" "$relative_path"
}

load_common
