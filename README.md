# HomeLab

This repository is the source of truth for bootstrapping, provisioning, and operating a private home lab environment built around Proxmox, OpenTofu, Ansible, and Semaphore.

The project assumes the lab is not exposed directly to the public internet. Because of that, the control plane is designed to live inside the lab itself. The first goal is to create a small, local management foundation that can bring up the rest of the environment without depending on external CI runners or public automation platforms.