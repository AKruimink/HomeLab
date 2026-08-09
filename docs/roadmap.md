# Roadmap

## Phase 1

Establish the minimum viable control plane.

- Add a Proxmox host-run script that creates a Semaphore LXC.
- Install Semaphore, SQLite, and Ansible in that LXC.
- Document the default and advanced bootstrap flow.
- Define the repository layout for `scripts`, `ansible`, and `tofu`.

## Phase 2

Make Semaphore useful immediately after bootstrap.

- Add repository-backed Semaphore job conventions.
- Add initial Ansible inventory and playbook structure.
- Add initial OpenTofu root module structure.
- Define how shared variables move between Semaphore, Ansible, and OpenTofu.

## Phase 3

Start managing real infrastructure and platform services.

- Create OpenTofu modules for Proxmox-backed LXC and VM resources.
- Add Ansible roles for baseline Linux configuration.
- Add Ansible roles for core applications and maintenance patterns.
- Define day-2 workflows such as updates, backups, and health checks.

## Phase 4

Move routine lab operations behind repeatable scheduled automation.

- Weekly or monthly LXC and VM patching.
- Application update jobs for services such as Pi-hole and Jellyfin.
- Drift checks and reporting.
- Backup validation and restore drills.

## Exit Criteria For The Bootstrap Script

The initial Semaphore bootstrap script remains valuable as long as it provides:

- a fast way to recover a lost management plane
- an auditable day-0 install path
- a smaller trust surface than third-party helper scripts

If OpenTofu and Ansible eventually manage even the control-plane lifecycle end to end, the bootstrap script can be narrowed further to a recovery-only tool.