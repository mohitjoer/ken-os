# The Top/Side Bar and Dock Architecture

The Asura desktop bar is the **Top Bar** (`top`) or **Side Bar** (`side`), rendered by Quickshell. It is driven by data
and reactive event streaming, never by polling subprocesses.

---

## Layout Model & Storage

Bar configuration lives in `~/.config/asura/shell.json` under the `top` or `side` namespace:

```json
"top": {
  "layout": {
    "version": 1,
    "left":   ["launcher", "workspaces"],
    "center": ["clock"],
    "right":  ["media", "cpu", "cputemp", "memory", "storage", "gpu",
               "volume", "brightness", "network", "bluetooth", "battery",
               "power", "status", "quick"]
  },
  "widgets": {
    "status": true,
    "memory": true,
    "battery": true
  }
}
```

```json
"side": {
  "layout": {
    "version": 1,
    "left":   ["launcher", "workspaces"],
    "center": ["clock"],
    "right":  ["media", "cpu", "cputemp", "memory", "storage", "gpu",
               "volume", "brightness", "network", "bluetooth", "battery",
               "power", "status", "quick"]
  },
  "widgets": {
    "status": true,
    "memory": true,
    "battery": true
  }
}
```

- **Order & Placement**: Defined in `top.layout.left`, `.center`, and `.right` (or `side.*`). Built-in widget IDs and installed plugin IDs live side by side.
- **Visibility**: Controlled by `top.widgets[<visibilityKey>]` (or `side.*`). Built-in widgets with no visibility key are always rendered. Plugins render when enabled in `~/.config/asura/plugins.json`.
- **Sole Writer Rule**: Only `asura-shell bar` and `asura-shell daemon` are permitted to mutate `shell.json`. Never hand-edit `shell.json`.

---

## Reactive Binding vs. Polling (Zero Subprocess Polling)

A core rule of Asura OS shell development is: **Never poll subprocesses or run timers in QML for system state.**
Repeated `Quickshell.execDetached` or `Process` loops burn CPU and introduce frame latency.

Instead, the shell uses reactive IPC topics served by `asura-shell daemon` over `$XDG_RUNTIME_DIR/asura-shell.sock`:

1. **Daemon State Streams**:
   - `asura-shell daemon` maintains high-frequency kernel/system monitors in Go.
   - Topics include: `settings`, `mpris`, `audio`, `network`, `bluetooth`, `battery`, `powerprofiles`, `wm`, `tray`, `cputemp`, `stats`.
2. **QML Topic Subscriptions**:
   - Singletons (`Settings.qml`, `qs.Services`) subscribe once over the socket (`subscribe <topic>`).
   - The daemon pushes JSON frames only when state changes.
   - QML property bindings react immediately to incoming frames without polling overhead.
3. **Control Calls**:
   - Actions and mutations send one-shot IPC requests (`call <method> <json>`) over a secondary control socket line.

---

## BarWidgetHost & Dynamic Slot Loading

`shell/modules/bar/BarWidgetHost.qml` hosts each widget inside a bar section:
- Dynamic Resolution: Maps catalogue widget IDs (`clock`, `workspaces`, `tray`, `status`, `dock`, `music`, etc.) and community plugins to their respective visual components via `Loader`.
- Self-Hiding Layout: When a widget has nothing to display (e.g. battery on AC-only desktop, or inactive VPN), it sets its `implicitWidth: 0`. `BarWidgetHost` collapses itself so no empty gap is left on the bar.
- Signal Forwarding: Forwards `menuRequested(id, rect)` and `actionRequested(id)` up to `FrameSurface` and popout controllers without parent coupling.

---

## Popouts (`shell/modules/bar/popouts/`)

Interactive flyout panels attached to bar widgets live in `shell/modules/bar/popouts/`:
- `AudioPopout.qml`: Volume slider, stream mixer, and output sink switcher.
- `NetworkPopout.qml`: Wi-Fi networks and connection controls.
- `BluetoothPopout.qml`: Paired devices, connect/disconnect toggles.
- `BatteryPopout.qml`: Battery health, charge thresholds, power profile modes.
- `SysMonitorPopout.qml`: CPU cores, memory utilization, and top processes.
- `MusicPopout.qml`: MPRIS album art, playback controls, track progress.
- `DockPreviewPopout.qml`: Live Wayland window previews for docked applications.

Popouts bind directly to daemon service singletons (`qs.Services.Audio`, `qs.Services.Network`, etc.) and open smoothly via keyboard triggers or widget clicks.

---

## Bar & Dock CLI Reference

All bar and dock operations should be performed via `asura-shell`:

### Bar Commands
```bash
# List widgets in layout with current section, index, and shown status
asura-shell bar list [--json]

# Print widget catalogue (built-in and installed plugins) with all settings
asura-shell bar catalog [--json]

# Move widget to a section/position
asura-shell bar move clock --section center
asura-shell bar move memory --section right --index 2

# Toggle widget visibility
asura-shell bar show gpu
asura-shell bar hide ai

# Configure widget-specific option
asura-shell bar set cputemp barTemperatureSource gpu
asura-shell bar set volume audioBoost true

# Bar appearance & placement
asura-shell bar position top        # or bottom
asura-shell bar style top           # or side (was: form)
asura-shell bar defaults            # Reset layout to default

# Open GUI settings panel
asura-shell bar settings [route]    # routes: bars, layout, widgets, dock, community
```

### Dock Commands
```bash
# Visibility & Autohide
asura-shell dock show
asura-shell dock hide
asura-shell dock autohide on        # or off

# Edge placement
asura-shell dock edge bottom        # auto, top, bottom, left, right

# Manage pinned applications
asura-shell dock pin org.mozilla.firefox
asura-shell dock unpin org.mozilla.firefox
asura-shell dock list [--json]
```
