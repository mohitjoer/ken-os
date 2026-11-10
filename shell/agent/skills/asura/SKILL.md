---
name: asura
description: >
  Customize an Asura OS desktop: a Hyprland compositor and
  a Quickshell shell (the QS Bar, the dock, widgets, the launcher, and the Hub).
  Use for end-user requests that touch the desktop or its config. Triggers:
  Hyprland, window rules, keybinds, monitors, gaps, borders, the bar, the dock,
  bar widgets, plugins, themes, wallpaper, colours, night light, idle, lock
  screen, and user-facing asura commands (asura, asura-shell, asura-hubd,
  asura-wallpaper, asura-agent). Read the system configuration first; act through commands,
  not by editing shipped files.
---

# Asura OS Desktop Skill

Asura OS is an independent modern operating system built on Void Linux x86_64 (glibc)
with `runit` supervision. The desktop environment consists of:
- **Compositor**: Hyprland
- **Shell**: A unified Quickshell architecture drawing the QS Bar, the dock, launcher, popouts, Hub, and desktop widgets
- **Control Plane**: Go command-line tools (`asura`, `asura-shell`, `asura-hubd`, `asura-wallpaper`, `asura-agent`)
- **State Store**: Managed JSON stores (`shell.json`, `plugins.json`, `colors.json`) served by `asura-shell daemon` over `$XDG_RUNTIME_DIR/asura-shell.sock`

This skill is for configuring, customizing, extending, and diagnosing a running Asura OS desktop.
It is not for modifying shipped package files in place.

---

## Core Asura OS Rules

### 1. Strict Monochrome Ink Aesthetic
Asura's visual language is strictly monochrome ink. Express character through **material, shape, and rhythm**, never through accent colour.
- **Singletons**: All UI components must import and draw strictly from `shell/Ui/Singletons/Tokens.qml` and `Ink.qml` (or through `qs.PluginKit` / `qs.PluginKit.Singletons`).
- **Zero Hardcoded Colours**: Never hardcode non-monochrome hex literals (`#ff0000`, `#3b82f6`, etc.) in QML. Colors resolve live through `Tokens.paper`, `Tokens.ink`, `Tokens.inkDim`, `Tokens.line`, `Tokens.tint5`, etc.
- **Contrast Floor**: Body ink must satisfy a strict **4.5:1** contrast ratio against its composite backdrop (`Ink.legible()`); UI indicators/borders must clear **3:1**.
- **Radius Scale**: Use only the standardized corner radius scale: `6 / 7 / 8 / 10 / 12 / 14 / 18 / 22 px`. Never invent intermediate radius values.
- **Spacing Grid**: Standard 4px grid (`Tokens.s1` = 4px, `Tokens.s2` = 8px, `Tokens.s3` = 12px, `Tokens.s4` = 16px, `Tokens.s5` = 24px, `Tokens.s6` = 32px, `Tokens.s7` = 48px).
- **Two-Stop Elevation**: Raised surfaces get a 1px contact border (`Tokens.line`) plus a soft ambient shadow.

### 2. The Overlay Boundary & Ownership Model
Asura cleanly isolates package-shipped files from user-customized state:
- **Shipped Base (`/usr/share/asura/shell/`)**: Owned by packages. **Never edit shipped files in place.** Any edits here are destroyed on the next package update.
- **Materialized Config (`~/.config/asura/`)**: Active desktop configs materialized by `asura materialize`. Shipped templates are clobbered on updates.
- **User Overrides (`~/.config/asura/user_edits/`)**: The overlay tree. Any file placed here mirrors `~/.config/asura/` and wins unconditionally over the base, surviving updates intact. For Hyprland tweaks, prefer `~/.config/asura/hyprland/user.conf`.
- **Live Daemon Socket**: `asura-shell daemon` serves live state and configuration over `$XDG_RUNTIME_DIR/asura-shell.sock`. All settings changes flow through the owning command or daemon IPC.
- **One Writer Per Setting**: Only the owning tool (`asura-shell`, `asura-hubd`, `asura-wallpaper`) may write to its respective store. Never hand-edit `shell.json` or `plugins.json`.

---

## Sub-Documentation Guides

Before implementing changes, consult the matching specialized guide:

| Guide | When to Read |
|---|---|
| [`gui.md`](gui.md) | Lookup for GUI-first answers: Asura Hub schema pages, deep-links (`asura-shell hub open <key>`), wallpaper picker, QS Bar Settings routes, and the CLI commands behind them. |
| [`bar.md`](bar.md) | Customizing or extending the QS Bar and dock: slot architecture, `BarWidgetHost.qml`, popouts (`shell/modules/bar/popouts/`), layout keys in `shell.json`, and `asura-shell bar` / `asura-shell dock` commands. |
| [`plugins.md`](plugins.md) | Scaffolding, authoring, and testing shell plugins with `asura plugin`: `qs.PluginKit`, R1–R11 static audit rules, manifest configuration, and lifecycle loading. |
| [`diagnostics.md`](diagnostics.md) | Triage playbook for crashes: Void `runit` services (`sv status`), crash dumps (`~/.local/state/asura/`), running Quickshell harnesses, contract tests (`shell_test.sh`, `qml.sh`), and recovery via `asura materialize` / `asura reset`. |

---

## Answer Policy: GUI First

When a user asks **HOW** to change a setting:
1. Lead with the **GUI path**: name the Asura Hub page (Super+comma), QS Bar Settings (`asura-shell bar settings`), or the wallpaper picker (`asura-wallpaper wallpaper ui`).
2. Provide the direct deep-link command: e.g., `asura-shell hub open keybinds`.
3. Provide the command-line equivalent as a scriptable fallback.

When the user asks **YOU** to execute the change:
1. Execute the command directly on their behalf (e.g., `asura-shell bar move clock --section right`).
2. Confirm the action and explain where the user can view or adjust it in the GUI.

---

## System Environment: Void Linux & runit

Asura OS uses **Void Linux x86_64 (glibc)** with **runit** as the init and process supervisor. There is NO systemd and NO apt.
- **Package Management**:
  - Search packages: `xbps-query -Rs <query>`
  - Install packages: `sudo xbps-install -S <package>`
  - Native Asura packages & bundles: `apm`
- **Service Management (`runit`)**:
  - User session services: `sv status ~/.config/service/*` (e.g. `quickshell`, `asurad`)
  - Restart a user service: `sv restart ~/.config/service/<svc>`
  - System services: `sudo sv status /var/service/*`
- **Shell & Daemon Reload**:
  - Reload both live shell and daemon: `asura reload`
  - Reload shell surface via daemon IPC: `asura-shell reload`
  - Reload compositor: `hyprctl reload`

---

## Core Command Reference

| Command | Domain & Ownership |
|---|---|
| `asura doctor` | Check system health, portal bindings, and overlay drift against base. |
| `asura status` | Display package version, channel, and update status. |
| `asura reload` | Signal user `runit` services (`quickshell`, `asurad`) to reload state cleanly. |
| `asura reset <path>` | Drop a user override from `~/.config/asura/user_edits/` and restore base. |
| `asura materialize` | Re-materialize base templates into `~/.config/asura/` (preserves `user_edits`). |
| `asura plugin ...` | Scaffold, audit, install, enable, and manage shell plugins. |
| `asura-shell bar ...` | Inspect and manipulate QS Bar layout, sections, visibility, and widget options. |
| `asura-shell dock ...` | Control dock edge, autohide, pins, and visibility. |
| `asura-shell hub open <key>` | Open Asura Hub directly to a specific settings page. |
| `asura-wallpaper ...` | Set wallpapers and generate dynamic color tokens (`wallpaper set\|next\|ui`). |
| `asura-agent wire` | Wire the Asura OS skill suite into local coding agents (`opencode`, `pi`, `claude`, `gemini`). |
