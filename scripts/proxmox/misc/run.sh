#!/usr/bin/env bash
set -euo pipefail

BASE="${1:-}"
SCRIPT="${2:-}"

if [[ -z "$BASE" || -z "$SCRIPT" ]]; then
  echo "Usage: curl -fsSL <base>/misc/run.sh | bash -s -- <base> <script>" >&2
  exit 2
fi

BASE="${BASE%/}"
SCRIPT="${SCRIPT#./}"
shift 2
export HOMELAB_PROXMOX_BASE="$BASE"

echo "HomeLab Proxmox origin: ${HOMELAB_PROXMOX_BASE}" >&2
echo "Running: ${SCRIPT}" >&2
curl -fsSL "${HOMELAB_PROXMOX_BASE}/${SCRIPT}" | bash -s -- "$@"
