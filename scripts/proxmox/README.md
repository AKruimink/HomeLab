# HomeLab Proxmox Scripts

This folder contains a local, self-controlled Proxmox scripting framework for repeatable HomeLab LXC and VM workflows.

## Goals

- keep the familiar `whiptail`-driven UX
- keep a consistent Proxmox-style create/install workflow
- keep shared host/container helper libraries
- keep the implementation fully local to this repository
- provide a clean base for adding more LXC and VM installers over time

## Current entrypoints

### Semaphore LXC

Run locally from a Proxmox host checkout:

```bash
bash scripts/proxmox/ct/semaphore.sh
```

Run directly from GitHub:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/AKruimink/HomeLab/main/scripts/proxmox/ct/semaphore.sh)"
```

Run from a feature branch without merging:

```bash
BASE=https://raw.githubusercontent.com/AKruimink/HomeLab/<your-branch>/scripts/proxmox
curl -fsSL "$BASE/misc/run.sh" | bash -s -- "$BASE" ct/semaphore.sh
```

The local Semaphore CT path is implemented with original HomeLab code and follows the same broad deployment model as the Proxmox ecosystem scripts: host-side create flow, shared helpers, and a smaller in-container installer.

### Ubuntu 24.04 cloud-init VM

Run locally from a Proxmox host checkout:

```bash
bash scripts/proxmox/vm/ubuntu-2404-cloudinit.sh
```

Run directly from GitHub:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/AKruimink/HomeLab/main/scripts/proxmox/vm/ubuntu-2404-cloudinit.sh)"
```

Run from a feature branch without merging:

```bash
BASE=https://raw.githubusercontent.com/AKruimink/HomeLab/<your-branch>/scripts/proxmox
curl -fsSL "$BASE/misc/run.sh" | bash -s -- "$BASE" vm/ubuntu-2404-cloudinit.sh
```

## Layout

- `ct/` host-side LXC entrypoints
- `install/` scripts executed inside containers
- `lib/` custom helpers still used by the VM-oriented local scripts
- `misc/run.sh` branch-aware remote runner
- `vm/` host-side VM entrypoints

See [proxmox-framework.md](C:/Users/AlwinKruimink/source/repos/~Personal/HomeLab.worktrees/custom-proxmox-scripts-development/docs/proxmox-framework.md) for the detailed architecture and flow diagrams.
