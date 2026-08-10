# HomeLab

This repository is the source of truth for bootstrapping, provisioning, and operating a private home lab environment built around Proxmox, OpenTofu, Ansible, and Semaphore.

The project assumes the lab is not exposed directly to the public internet. Because of that, the control plane is designed to live inside the lab itself. The first goal is to create a small, local management foundation that can bring up the rest of the environment without depending on external CI runners or public automation platforms.

## Proxmox script framework

The repository now includes a local Proxmox scripting framework under [scripts/proxmox/](C:/Users/AlwinKruimink/source/repos/~Personal/HomeLab.worktrees/custom-proxmox-scripts-development/scripts/proxmox) for HomeLab LXC and VM workflows.

The first complete app implementation is the Semaphore LXC flow:

- [semaphore.sh](C:/Users/AlwinKruimink/source/repos/~Personal/HomeLab.worktrees/custom-proxmox-scripts-development/scripts/proxmox/ct/semaphore.sh)
- [semaphore-install.sh](C:/Users/AlwinKruimink/source/repos/~Personal/HomeLab.worktrees/custom-proxmox-scripts-development/scripts/proxmox/install/semaphore-install.sh)

Architecture and flow details are documented in [proxmox-framework.md](C:/Users/AlwinKruimink/source/repos/~Personal/HomeLab.worktrees/custom-proxmox-scripts-development/docs/proxmox-framework.md).