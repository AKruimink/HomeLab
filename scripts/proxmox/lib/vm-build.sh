#!/usr/bin/env bash

if [[ -n "${HOMELAB_PROXMOX_VM_BUILD_LOADED:-}" ]]; then
  return 0
fi
HOMELAB_PROXMOX_VM_BUILD_LOADED=1

vm_apply_default_settings() {
  local default_name="$1"
  local default_cpu="$2"
  local default_ram="$3"
  local default_disk="$4"

  VMID="${VMID:-$(next_vmid)}"
  VM_NAME="${VM_NAME:-$default_name}"
  VM_CPU="${VM_CPU:-$default_cpu}"
  VM_RAM="${VM_RAM:-$default_ram}"
  VM_DISK="${VM_DISK:-$default_disk}"
  VM_BRIDGE="${VM_BRIDGE:-$(pve_first_bridge)}"
  VM_USE_DHCP="${VM_USE_DHCP:-yes}"
  VM_IPV4_CIDR="${VM_IPV4_CIDR:-}"
  VM_GATEWAY="${VM_GATEWAY:-}"
  VM_ONBOOT="${VM_ONBOOT:-1}"
  VM_IMAGE_STORAGE="${VM_IMAGE_STORAGE:-$(pve_first_storage "images")}"
}

vm_prompt_advanced_settings() {
  local selection

  while true; do
    selection="$(prompt_input "VM ID" "Choose a numeric VMID." "${VMID:-$(next_vmid)}")" || return 1
    validate_integer "$selection" && break
    msg_warn "VMID must be numeric."
  done
  VMID="$selection"

  while true; do
    selection="$(prompt_input "VM Name" "Enter the VM name." "${VM_NAME:-ubuntu-2404-base}")" || return 1
    validate_hostname "$selection" && break
    msg_warn "VM name must start with a letter or number and may contain hyphens."
  done
  VM_NAME="$selection"

  while true; do
    selection="$(prompt_input "CPU Cores" "Set the number of vCPU cores." "${VM_CPU:-2}")" || return 1
    validate_integer "$selection" && break
    msg_warn "CPU cores must be numeric."
  done
  VM_CPU="$selection"

  while true; do
    selection="$(prompt_input "Memory" "Set the RAM size in MiB." "${VM_RAM:-4096}")" || return 1
    validate_integer "$selection" && break
    msg_warn "RAM must be numeric."
  done
  VM_RAM="$selection"

  while true; do
    selection="$(prompt_input "Disk" "Set the VM disk size in GiB." "${VM_DISK:-20}")" || return 1
    validate_integer "$selection" && break
    msg_warn "Disk must be numeric."
  done
  VM_DISK="$selection"

  VM_BRIDGE="$(pve_pick_bridge "${VM_BRIDGE:-}")" || return 1

  if prompt_yes_no "IPv4" "Use DHCP for the cloud-init IPv4 configuration?" "yes"; then
    VM_USE_DHCP="yes"
    VM_IPV4_CIDR=""
    VM_GATEWAY=""
  else
    VM_USE_DHCP="no"
    VM_IPV4_CIDR="$(prompt_input "IPv4 Address" "Enter the cloud-init IPv4 CIDR (example: 192.168.1.60/24)." "${VM_IPV4_CIDR:-}")" || return 1
    VM_GATEWAY="$(prompt_input "Gateway" "Enter the IPv4 gateway." "${VM_GATEWAY:-}")" || return 1
  fi

  if prompt_yes_no "Boot Behavior" "Start this VM automatically on node boot?" "yes"; then
    VM_ONBOOT="1"
  else
    VM_ONBOOT="0"
  fi

  VM_IMAGE_STORAGE="$(pve_pick_storage "images" "VM Disk Storage" "Select where the VM disks should live." "${VM_IMAGE_STORAGE:-}")" || return 1
}

vm_summary_text() {
  cat <<EOF
VMID:      ${VMID}
Name:      ${VM_NAME}
CPU:       ${VM_CPU} core(s)
Memory:    ${VM_RAM} MiB
Disk:      ${VM_DISK} GiB
Bridge:    ${VM_BRIDGE}
IPv4:      $( [[ "${VM_USE_DHCP}" == "yes" ]] && printf '%s' "DHCP" || printf '%s via %s' "${VM_IPV4_CIDR}" "${VM_GATEWAY}" )
On boot:   ${VM_ONBOOT}
Storage:   ${VM_IMAGE_STORAGE}
Image:     Ubuntu 24.04 cloud image
EOF
}

vm_confirm_settings() {
  local summary
  summary="$(vm_summary_text)"

  if command_exists whiptail; then
    whiptail --backtitle "HomeLab Proxmox Scripts" --title "Confirm VM Settings" --yesno "$summary" 18 78
    return $?
  fi

  echo "$summary"
  prompt_yes_no "Confirm VM Settings" "Continue with these settings?" "yes"
}

vm_cloud_image_arch() {
  case "$(dpkg --print-architecture)" in
  amd64) printf '%s' "amd64" ;;
  arm64) printf '%s' "arm64" ;;
  *)
    die "Unsupported architecture for Ubuntu cloud images: $(dpkg --print-architecture)"
    ;;
  esac
}

vm_ensure_ubuntu_cloud_image() {
  local arch
  local image_dir="/var/lib/vz/template/qemu"
  local image_name
  local image_path
  local image_url

  arch="$(vm_cloud_image_arch)"
  image_name="noble-server-cloudimg-${arch}.img"
  image_path="${image_dir}/${image_name}"
  image_url="https://cloud-images.ubuntu.com/noble/current/${image_name}"

  mkdir -p "$image_dir"
  if [[ ! -f "$image_path" ]]; then
    msg_info "Downloading Ubuntu 24.04 cloud image"
    curl -fsSL "$image_url" -o "$image_path"
    msg_ok "Downloaded Ubuntu 24.04 cloud image"
  fi

  printf '%s' "$image_path"
}

vm_create_ubuntu_cloudinit() {
  local image_path
  local ssh_keys_file="/root/.ssh/authorized_keys"

  ensure_guest_id_available "$VMID"
  image_path="$(vm_ensure_ubuntu_cloud_image)"

  msg_info "Creating VM ${VMID}"
  qm create "$VMID" \
    --name "$VM_NAME" \
    --memory "$VM_RAM" \
    --cores "$VM_CPU" \
    --net0 "virtio,bridge=${VM_BRIDGE}" \
    --ostype l26 \
    --agent enabled=1 \
    --scsihw virtio-scsi-pci \
    --serial0 socket \
    --vga serial0 \
    --onboot "$VM_ONBOOT" >/dev/null
  msg_ok "Created VM ${VMID}"

  msg_info "Importing Ubuntu cloud disk"
  qm importdisk "$VMID" "$image_path" "$VM_IMAGE_STORAGE" >/dev/null
  qm set "$VMID" --scsi0 "${VM_IMAGE_STORAGE}:vm-${VMID}-disk-0" >/dev/null
  qm set "$VMID" --boot order=scsi0 >/dev/null
  qm set "$VMID" --ide2 "${VM_IMAGE_STORAGE}:cloudinit" >/dev/null
  qm resize "$VMID" scsi0 "${VM_DISK}G" >/dev/null
  msg_ok "Imported Ubuntu cloud disk"

  qm set "$VMID" --ciuser ubuntu >/dev/null
  if [[ -f "$ssh_keys_file" ]]; then
    qm set "$VMID" --sshkeys "$ssh_keys_file" >/dev/null
  fi

  if [[ "$VM_USE_DHCP" == "yes" ]]; then
    qm set "$VMID" --ipconfig0 ip=dhcp >/dev/null
  else
    qm set "$VMID" --ipconfig0 "ip=${VM_IPV4_CIDR},gw=${VM_GATEWAY}" >/dev/null
  fi

  msg_info "Starting VM ${VMID}"
  qm start "$VMID" >/dev/null
  msg_ok "Started VM ${VMID}"
}
