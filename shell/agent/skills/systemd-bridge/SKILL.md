---
name: systemd-bridge
description: >
  Manage and troubleshoot system services, third-party installer scripts, and
  systemd compatibility on Asura OS (Void Linux + runit). Use when dealing with
  `systemctl`, `journalctl`, `runit`, `sv`, background daemons, `.service` unit files,
  vendor install scripts (such as `curl | sh`), or setting up developer services
  like Docker, Ollama, Tailscale, databases, and microservices.
metadata:
  namespace: system
---

# Asura OS Systemd Compatibility Bridge Skill

## Overview

Asura OS uses **Void Linux x86_64 (glibc)** with **`runit`** supervision as its init system. There is **no systemd** on the host.

To ensure frictionless compatibility with the broader Linux developer ecosystem—including online tutorials, vendor `curl | sh` scripts, and third-party tools—Asura OS provides a built-in compatibility layer:
- **`/usr/bin/systemctl`**: Intercepts systemd control commands and maps them directly to `runit` (`sv` and `/var/service` symlinks). It also parses newly dropped `.service` files and generates `runit` services on the fly.
- **`/usr/bin/journalctl`**: Bridges systemd log inspection to `svlogd` log streams at `/var/log/<service>/current`.

---

## Command Reference & Behavior

When an AI agent or a script runs `systemctl`, the bridge handles it as follows:

| Command | Action Performed Under the Hood | Exit Code |
| :--- | :--- | :---: |
| `systemctl daemon-reload` | Acknowledged as a no-op; runit dynamically monitors `/var/service/` | `0` |
| `systemctl enable <unit>` | Ensures `/etc/sv/<unit>` exists (auto-converts if needed), symlinks `/var/service/<unit>` | `0` |
| `systemctl enable --now <unit>` | Symlinks `/var/service/<unit>` and immediately runs `sv up <unit>` | `0` |
| `systemctl disable <unit>` | Removes symlink `/var/service/<unit>` | `0` |
| `systemctl disable --now <unit>` | Runs `sv down <unit>` and removes symlink `/var/service/<unit>` | `0` |
| `systemctl start <unit>` | Symlinks to `/var/service/<unit>` if needed, runs `sv up <unit>` | `0` |
| `systemctl stop <unit>` | Runs `sv down <unit>` | `0` |
| `systemctl restart <unit>` | Runs `sv restart <unit>` | `0` |
| `systemctl status <unit>` | Calls `sv status <unit>` (or reports inactive if unlinked) | `0` or `3` |
| `systemctl is-active <unit>` | Checks if service state starts with `run:`; prints `active`/`inactive` | `0` (active) / `3` |
| `systemctl is-enabled <unit>` | Checks if `/var/service/<unit>` symlink exists; prints `enabled`/`disabled` | `0` (enabled) / `1` |
| `journalctl -u <unit> [-f]` | Tails `/var/log/<unit>/current` using `tail -n 100` (or `tail -f`) | `0` |

---

## On-the-Fly `.service` Conversion Engine

When a third-party installer (such as Ollama, Tailscale, Cloudflare Warp, or custom software) writes a unit file to:
- `/etc/systemd/system/<unit>.service`
- `/usr/lib/systemd/system/<unit>.service`
- `/lib/systemd/system/<unit>.service`

And subsequently invokes `systemctl enable [--now] <unit>`, the bridge automatically:
1. Discovers the `.service` file.
2. Extracts:
   - `ExecStart=`: The command line to execute.
   - `User=` / `Group=`: User and group identity for privilege dropping.
   - `WorkingDirectory=`: Root execution directory.
   - `Environment=`: Inline environment variables (`KEY=VALUE`).
   - `EnvironmentFile=`: Environment files to source before launch.
3. Automatically writes an executable run script at `/etc/sv/<unit>/run`:
   ```sh
   #!/bin/sh
   exec 2>&1
   cd "<WorkingDirectory>" 2>/dev/null || true
   [ -f "<EnvironmentFile>" ] && . "<EnvironmentFile>"
   export KEY=VALUE ...
   exec chpst -u "<User>:<Group>" <ExecStart>
   ```
4. Creates a companion logger script at `/etc/sv/<unit>/log/run`:
   ```sh
   #!/bin/sh
   mkdir -p /var/log/<unit>
   exec svlogd -tt /var/log/<unit>
   ```
5. Symlinks `/var/service/<unit> -> /etc/sv/<unit>`.
6. Starts the service immediately via `sv up <unit>`.

---

## Agent Guidelines for Service Management

### 1. Running Third-Party Install Scripts
When a user asks to install a tool with a standard bash/curl installer (e.g. `curl -fsSL https://ollama.com/install.sh | sh` or `curl -fsSL https://tailscale.com/install.sh | sh`):
- Run the installer directly.
- The `systemctl daemon-reload` and `systemctl enable --now` calls in the vendor script will succeed without modification.

### 2. Manual Service Control
Both idioms are fully supported:
- **Standard Idiom**:
  ```bash
  sudo systemctl enable --now docker
  sudo systemctl status docker
  ```
- **Native Runit Idiom**:
  ```bash
  sudo ln -sf /etc/sv/docker /var/service/docker
  sudo sv up docker
  sudo sv status docker
  ```

### 3. Diagnosing and Troubleshooting Services
If a service fails or exits:
1. **Check Status**:
   ```bash
   sudo systemctl status <service>
   # or
   sudo sv status <service>
   ```
2. **Inspect Logs**:
   ```bash
   journalctl -u <service> -f
   # or directly read the svlogd stream:
   tail -n 100 /var/log/<service>/current
   ```
3. **Inspect the Generated Service Script**:
   Check `/etc/sv/<service>/run`.
4. **Foreground Requirement (Crucial Runit Rule)**:
   - `runit` supervises processes that run in the **foreground**.
   - If a binary double-forks or daemonizes into the background by default (e.g., standard `nginx` without `daemon off;` or legacy daemons), `runit` will think it died and restart it in a rapid loop.
   - Fix: Ensure the command has its foreground flag enabled (e.g., `--foreground`, `-f`, `-D`, or `daemon off;`).

### 4. Privilege Dropping
- In Asura OS, `chpst -u <user>:<group>` (from `runit`) is the standard tool to run a daemon as a non-root user.
- If creating custom services, avoid `su` or `sudo` inside the run script; prefer `exec chpst -u <user> <command>`.

---

## Repository Implementation Files

- **Bridge Implementation**:
  - [`system/helpers/systemctl`](file:///home/mohit/code/ASURA-OS/system/helpers/systemctl)
  - [`system/helpers/journalctl`](file:///home/mohit/code/ASURA-OS/system/helpers/journalctl)
- **Automated Tests**:
  - [`system/helpers/tools/tests/systemctl-bridge_test.sh`](file:///home/mohit/code/ASURA-OS/system/helpers/tools/tests/systemctl-bridge_test.sh)
- **ISO Deployment**:
  - Staged in [`installation/build-iso-void.sh`](file:///home/mohit/code/ASURA-OS/installation/build-iso-void.sh) to `/usr/bin/systemctl` and `/usr/bin/journalctl`.
