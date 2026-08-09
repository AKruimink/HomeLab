# Scripts

This folder contains local utility scripts that are intended to be run manually from trusted administrative environments.

Public entrypoints should be easy to execute directly from the repository when appropriate.

Example:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/AKruimink/HomeLab/main/scripts/proxmox/ct/semaphore.sh)"
```

The Proxmox-specific framework now lives under [proxmox/](C:/Users/AlwinKruimink/source/repos/~Personal/HomeLab.worktrees/custom-proxmox-scripts-development/scripts/proxmox).