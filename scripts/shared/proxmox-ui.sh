#!/usr/bin/env bash

UI_BACKTITLE="HomeLab Proxmox Scripts"

ui_require_whiptail() {
  if ! command -v whiptail >/dev/null 2>&1; then
    printf 'Missing dependency: whiptail\n' >&2
    printf 'Install it first on the Proxmox host with: apt update ; apt install -y whiptail\n' >&2
    exit 127
  fi
}

ui_msg() {
  local title=$1
  local text=$2
  local height=${3:-12}
  local width=${4:-70}

  whiptail --backtitle "$UI_BACKTITLE" --title "$title" --msgbox "$text" "$height" "$width"
}

ui_yesno() {
  local title=$1
  local text=$2
  local height=${3:-12}
  local width=${4:-70}
  local yes_label=${5:-Yes}
  local no_label=${6:-No}

  whiptail \
    --backtitle "$UI_BACKTITLE" \
    --title "$title" \
    --yes-button "$yes_label" \
    --no-button "$no_label" \
    --yesno "$text" "$height" "$width"
}

ui_input() {
  local title=$1
  local text=$2
  local default_value=${3:-}
  local ok_label=${4:-Next}
  local cancel_label=${5:-Back}
  local height=${6:-11}
  local width=${7:-72}

  whiptail \
    --backtitle "$UI_BACKTITLE" \
    --title "$title" \
    --ok-button "$ok_label" \
    --cancel-button "$cancel_label" \
    --inputbox "$text" "$height" "$width" "$default_value" \
    3>&1 1>&2 2>&3
}

ui_password() {
  local title=$1
  local text=$2
  local ok_label=${3:-Next}
  local cancel_label=${4:-Back}
  local height=${5:-12}
  local width=${6:-72}

  whiptail \
    --backtitle "$UI_BACKTITLE" \
    --title "$title" \
    --ok-button "$ok_label" \
    --cancel-button "$cancel_label" \
    --passwordbox "$text" "$height" "$width" \
    3>&1 1>&2 2>&3
}

ui_menu() {
  local title=$1
  local text=$2
  local height=${3:-20}
  local width=${4:-60}
  local list_height=${5:-8}
  shift 5

  whiptail \
    --backtitle "$UI_BACKTITLE" \
    --title "$title" \
    --ok-button "Select" \
    --cancel-button "Exit Script" \
    --notags \
    --menu "$text" "$height" "$width" "$list_height" \
    "$@" \
    3>&1 1>&2 2>&3
}

ui_radiolist() {
  local title=$1
  local text=$2
  local height=${3:-14}
  local width=${4:-58}
  local list_height=${5:-4}
  shift 5

  whiptail \
    --backtitle "$UI_BACKTITLE" \
    --title "$title" \
    --ok-button "Next" \
    --cancel-button "Back" \
    --radiolist "$text" "$height" "$width" "$list_height" \
    "$@" \
    3>&1 1>&2 2>&3
}