# Asura OS Diagnostics & Crash Triage Playbook

This playbook provides actionable steps for diagnosing and resolving Quickshell errors,
daemon failures, QML binding issues, and broken user configurations on Asura OS.

---

## 1. Checking Service & Crash Logs (Void Linux `runit`)

Asura OS uses `runit` for process supervision. There is no `systemctl` or `journalctl`.

### Inspecting User and System Services
Session services run under the user's `runsvdir` instance:
```bash
# Check status of all active user session services
sv status ~/.config/service/*

# Typical user services:
#   ~/.config/service/quickshell  (The visual desktop shell)
#   ~/.config/service/asurad      (Core desktop daemon & socket provider)

# Check system services (hardware, power, dbus, seatd)
sudo sv status /var/service/*

# Restart a failing service
sv restart ~/.config/service/quickshell
sv restart ~/.config/service/asurad
```

### Inspecting Crash Dumps & Logs
Quickshell crash environments and state files are written to `~/.local/state/asura/`:
```bash
# List recent crash dumps and logs
ls -la ~/.local/state/asura/

# Inspect recent crash logs or core details
cat ~/.local/state/asura/quickshell.log 2>/dev/null
cat ~/.local/state/asura/asura-shell.log 2>/dev/null
```

### Reproducing QML Errors in an Interactive Test Harness
When the visual shell fails to start or crashes silently, run Quickshell manually in a terminal to capture QML binding warnings, missing module imports, or fatal syntax errors:

```bash
# Test the installed system shell
quickshell -p /usr/share/asura/shell

# Or test against a local repository checkout
quickshell -p shell/

# Test the Asura Hub independently
quickshell -p /usr/share/asura/shell/hub.qml
```

Look for:
- `ReferenceError: ... is not defined` -> Unimported module or missing singleton.
- `Cannot assign to read-only property ...` -> Mutating a read-only token or state binding.
- `Type ... unavailable` -> Broken relative component path or missing plugin dependency.

---

## 2. Static & Contract Verification

Before modifying QML or system code, run the built-in automated test suites:

### 1. Engine Load Verification (`shell/shell_test.sh`)
Verifies that both the desktop shell and the Hub compile and instantiate cleanly under the Quickshell Wayland engine:
```bash
sh shell/shell_test.sh
```
Expected output:
```
ok    — the shell loads with no errors
ok    — the Hub loads with no errors
```

### 2. QML Syntax & Linter Verification (`tests/contract/qml.sh`)
Runs `qmllint` across all QML files against the baseline:
```bash
sh tests/contract/qml.sh
```
Ensures zero new syntax-class errors or malformed property declarations.

### 3. Asura Doctor Diagnostic (`asura doctor`)
Validates system state, schema keys, keybindings, and portal compatibility:
```bash
# Human-readable report
asura doctor

# JSON report for programmatic inspection
asura doctor --json

# Automatically repair renamed keys in ~/.config/asura/shell.json
asura doctor --fix
```
What `asura doctor` inspects:
- **Portals**: Confirms `xdg-desktop-portal-hyprland` is active and `xdg-desktop-portal-gnome` is absent.
- **Keybinds**: Verifies chords in `~/.config/asura/hyprland/rebinds.conf` against `binds.json`.
- **Drift**: Pinpoints differences between `/usr/share/asura/` base templates and `~/.config/asura/user_edits/`.

---

## 3. Safe Recovery & Reloading

If a customized QML file or bad user edit breaks the shell, use the following recovery sequence:

### Step 1: Pinpoint the Broken File
Check for modified files in user overrides:
```bash
ls -la ~/.config/asura/user_edits/
```

### Step 2: Reset or Re-materialize
To revert a specific broken override back to package defaults:
```bash
# Drops the override from user_edits/ and restores the shipped base copy
asura reset <relative/path/to/file>

# Example: reset a corrupted hyprland config
asura reset hyprland/hyprland.conf
```

To refresh all shipped templates while preserving user overrides:
```bash
asura materialize
```

### Step 3: Trigger Live Reload
Once fixed, reload the live components without rebooting:
```bash
# Signal user runit services (quickshell and asurad)
asura reload

# Or trigger daemon-level shell surface reload
asura-shell reload

# Reload Hyprland compositor bindings and rules
hyprctl reload
```

---

## Common Crash Patterns & Solutions

| Symptom | Probable Cause | Fix |
|---|---|---|
| Shell crashes immediately on launch | Missing QML import or syntax error in a modified file | Run `quickshell -p shell/` to see the stack trace; run `sh tests/contract/qml.sh`. |
| Black or missing bar widgets | Non-existent widget ID in `shell.json` or invalid visibility key | Run `asura-shell bar list --json` and `asura-shell bar defaults` to restore layout. |
| Daemon fails to bind socket | Stale `$XDG_RUNTIME_DIR/asura-shell.sock` or lockfile | Verify service with `sv status ~/.config/service/asurad`; clean up stale lock if daemon died. |
| Hub settings do not persist | Multiple writers or manual editing of `shell.json` | Use `asura-shell` CLI or Hub UI to write settings; verify schema with `asura doctor`. |
| Plugin fails to load on bar | Failed static audit rule (e.g. internal import or forbidden binary) | Run `asura plugin audit <path>` and resolve blocking findings. |
