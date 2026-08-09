# Scripts

This folder contains local utility scripts that are intended to be run manually from trusted administrative environments.

These scripts should stay narrow in scope.

- Use them for bootstrap, recovery, or break-glass tasks.
- Do not let them grow into a second configuration-management layer.
- Prefer readable shell over abstract helper frameworks.

Public entrypoints should be easy to execute directly from the repository when appropriate.

Example:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/AKruimink/HomeLab/main/scripts/proxmox/semaphore.sh)"
```