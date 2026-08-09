# Scripts

## Purpose

This document defines how scripts in this repository should be written, organized, and exposed.

Scripts are primarily for day-0 bootstrap, recovery, and break-glass operations. They are not meant to replace OpenTofu or Ansible.

## Scope

Scripts in this repository should be used for tasks such as:

- creating the first management LXC when no control plane exists yet
- recovering the control plane if Semaphore is unavailable
- performing trusted host-side setup that must happen before repository-managed automation can take over

Scripts should not become a second long-term orchestration layer.

## Structure

Scripts should live in folders that make their execution context obvious.

Examples:

- `scripts/proxmox/` for scripts that run on a Proxmox host
- `scripts/windows/` for admin workstation utilities if those are introduced later
- `scripts/linux/` for local operator utilities outside Proxmox if needed later

## Standards

- Keep scripts readable from top to bottom.
- Prefer explicit variable names over dense helper abstractions.
- Validate preconditions early.
- Print a summary before provisioning or destructive actions.
- Emit credentials and next steps clearly when bootstrap succeeds.
- Keep external dependencies minimal and obvious.
- Prefer repository-owned logic over runtime downloads of shared helper libraries.
- Use shell functions only where they reduce repetition without obscuring the flow.

## Behavior

Scripts should generally follow this lifecycle:

1. verify environment and required commands
2. collect configuration with defaults and optional advanced prompts
3. validate the final input set
4. show a clear summary
5. execute the requested action
6. print outputs, credentials, and next steps

## Public Entrypoints

Because this repository is public, scripts intended for direct consumption should have stable raw-GitHub entrypoints.

That means a script should be callable in a style similar to Proxmox VE Helper Scripts, for example:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/AKruimink/HomeLab/main/scripts/proxmox/semaphore.sh)"
```

The raw entrypoint should point to a repository path that is simple, predictable, and unlikely to move casually.

## Prompt Model

When a script provisions infrastructure, prefer the same operator experience across scripts:

- a default mode with safe, fast choices
- an advanced mode with more control over resources and networking
- explicit confirmation before create or destroy actions

## Relationship To Other Automation

- OpenTofu defines infrastructure state.
- Ansible defines operating system and application configuration.
- Semaphore runs and schedules repository-managed jobs.
- Scripts only bridge the gap before those layers are available or when they are temporarily unavailable.

## Current Entrypoints

- [scripts/proxmox/semaphore.sh](c:/Users/AlwinKruimink/source/repos/~Personal/HomeLab/scripts/proxmox/semaphore.sh)