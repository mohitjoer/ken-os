.pragma library

// LockscreenPage schema.
// Configures session locking and inactivity timeouts backed by org.asura.desktop.
var rows = [
    {
        "id": "lockscreen.now",
        "label": "Lock screen now",
        "key": "lockscreen.now",
        "section": "lockscreen",
        "desc": "Lock the current session immediately via hyprlock",
        "kind": "action",
        "keywords": "lock now screen hyprlock security password"
    },
    {
        "id": "idle.lock",
        "label": "Lock session after",
        "key": "idle-lock-seconds",
        "section": "lockscreen",
        "desc": "Inactivity duration before the screen automatically locks",
        "kind": "choice",
        "src": "org.asura.desktop.idle-lock-seconds",
        "keywords": "lock idle timeout security password inactivity sleep"
    },
    {
        "id": "idle.dim",
        "label": "Dim display after",
        "key": "idle-dim-seconds",
        "section": "lockscreen",
        "desc": "Lowers display brightness before locking to reduce power consumption",
        "kind": "choice",
        "src": "org.asura.desktop.idle-dim-seconds",
        "keywords": "dim backlight brightness screen idle battery"
    },
    {
        "id": "idle.blank",
        "label": "Turn display off after",
        "key": "idle-blank-seconds",
        "section": "lockscreen",
        "desc": "Powers down displays via DPMS standby after prolonged inactivity",
        "kind": "choice",
        "src": "org.asura.desktop.idle-blank-seconds",
        "keywords": "display screen off blank dpms standby monitor power"
    }
];
