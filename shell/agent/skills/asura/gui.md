# The Asura GUI & Hub Architecture

Asura OS provides a graphical interface for almost every system setting.
The primary surface is **Asura Hub** (`shell/hub/Hub.qml`), backed by **QS Bar Settings**
and the **Wallpaper Picker**.

When users ask how to modify a configuration, prioritize the GUI route first, followed by
the direct command-line invocation (`SKILL.md` "Answer Policy: GUI First").

---

## Hub Architecture & Schema Pages (`shell/hub/`)

Asura Hub is built on dynamic, data-driven schema pages:
- **`SchemaPage.qml` & `SettingsSheet.qml`**: Rather than writing custom QML forms for every setting, Hub pages define declarative schemas binding keys to controls (toggles, sliders, option pickers).
- **Zero Polling IPC**: `shell/hub/Singletons/Settings.qml` connects to `$XDG_RUNTIME_DIR/asura-shell.sock` and executes `subscribe settings`. The full configuration tree streams as JSON frames on startup and whenever any setting changes. Edits are pushed back as one-shot `settings.patch` calls.
- **Compositor Gating**: The daemon advertises active compositor capabilities (`caps`). Pages or controls gating on unsupported features (e.g. animation curves or specific window manager rules when not on Hyprland) hide themselves automatically via `supports(cap)`.

---

## Accessing the Hub

- **Global Keybind**: Press `Super + comma` (`Super+,`) to open Asura Hub.
- **Direct Deep-Linking**:
  ```bash
  asura-shell hub open <key>
  ```
  Deep-linking raises the window and navigates immediately to the specified section.

---

## Hub Page Directory

| Page Key | Title | File (`shell/hub/pages/`) | Controlled Subsystem |
|---|---|---|---|
| `profile` | Profile | `ProfilePage.qml` | User avatar, name, and profile hero styling |
| `global` | General | `GlobalPage.qml` | Hub preferences, font scaling, UI zoom |
| `updates` | Updates | `UpdatesPage.qml` | System updates, release channel, package manager |
| `displays` | Displays | `DisplaysPage.qml` | Monitor resolutions, refresh rates, scaling |
| `connections` | Connections | `ConnectionsPage.qml` | Wi-Fi networks, Bluetooth pairing |
| `input` | Input | `InputPage.qml` | Keyboard layout, repeat rate, touchpad gestures |
| `gpu` | Graphics & Power | `GpuPage.qml` | Power profiles, GPU performance, idle & lock screen timers |
| `animations` | Animations | `AnimationsPage.qml` | Compositor animation curves and bezier profiles |
| `lockscreen` | Lockscreen | `LockscreenPage.qml` | Hyprlock appearance, clock format, lock timeouts |
| `windowmanager` | Window Manager | `WindowManagerPage.qml` | Window gaps, border radius, active border colors |
| `plugins` | Plugins | `PluginsPage.qml` | Compositor plugins and extensions |
| `layerrules` | Layer Rules | `LayerRulesPage.qml` | Advanced layer-shell window rules |
| `bar-studio` | Bar Studio | `BarStudioPage.qml` | QS Bar styling, border radiuses, height |
| `desktop` | Desktop | `DesktopPage.qml` | Desktop stage, widgets, and background effects |
| `widgets` | Widgets | `WidgetsPage.qml` | Desktop clock, system monitor, and media widgets |
| `launcher` | App Launcher | `LauncherPage.qml` | Super+Space launcher behavior and search engines |
| `keybinds` | Keybinds | `KeybindsPage.qml` | Global shortcut chords and compositor keybindings |
| `appoverrides` | App Overrides | `AppOverridesPage.qml` | Per-application window rules and float settings |
| `windowrules` | Window Rules | `WindowRulesPage.qml` | Tiling rules, workspace assignments |
| `performance` | Performance | `PerformancePage.qml` | Gaming mode toggles, CPU governor tuning |
| `session` | Session | `SessionPage.qml` | Autostart services, session timeout, power actions |
| `recording` | Recording | `RecordingPage.qml` | Screen recording bitrate, audio sources |
| `dictation` | Dictation | `DictationPage.qml` | Voice dictation and input triggers |
| `fastfetch` | Fastfetch | `FastfetchPage.qml` | Terminal system splash logo and info |
| `import` | Import Config | `ImportPage.qml` | Migrate external dotfiles and configs |
| `addons` | Add-ons | `AddonsPage.qml` | Shell plugins catalogue and community extensions |
| `credits` | Credits | `CreditsPage.qml` | Distribution credits and licenses |

---

## Surfaces Outside the Hub

Certain interactive tools run outside the Asura Hub:

| Purpose | GUI Surface | Shortcut / Command | Scriptable Backend |
|---|---|---|---|
| Wallpaper & Palette | Wallpaper Picker | `asura-wallpaper wallpaper ui` | `asura-wallpaper wallpaper set <path>` |
| Bar & Dock Settings | QS Bar Settings | `asura-shell bar settings [route]` | `asura-shell bar ...` / `asura-shell dock ...` |
| Application Launcher | Shell Launcher | `Super + Space` | Managed in `shell.json` (`launcher.*`) |
| Clipboard & Stash | Stash Overlay | `Super + S` | Staged in `~/.local/state/asura/stash/` |

---

## Formulating User Answers

Always formulate answers with the GUI interface as the hero:

**Question**: *"How do I change the display scaling?"*
**Answer**:
> Open **Asura Hub** using `Super+,` and navigate to **Displays**, or run:
> ```bash
> asura-shell hub open displays
> ```
> From there, adjust the monitor scale slider. Alternatively, you can configure it via Hyprland config or `asura-shell`.
