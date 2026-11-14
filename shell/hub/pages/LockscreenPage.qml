pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Ui.Singletons

// Lockscreen settings page.
// Backed by hyprlock (PAM authenticator), hypridle (inactivity daemon),
// and the org.asura.desktop idle timeouts store.
Item {
    id: pg

    property var hub
    readonly property bool fullBleed: true

    // Missing components probe: "hyprlock", "hypridle", or "idle-off"
    property var missing: []
    readonly property bool canLock: pg.missing.indexOf("hyprlock") < 0
    readonly property bool idleRunning: pg.missing.indexOf("idle-off") < 0 && pg.missing.indexOf("hypridle") < 0

    // Stored idle seconds
    property int lockSeconds: 300
    property int dimSeconds: 0
    property int blankSeconds: 0

    readonly property var lockOptions: ["Never", "1m", "2m", "5m", "10m", "15m", "30m"]
    readonly property var lockValues: [0, 60, 120, 300, 600, 900, 1800]

    readonly property var dimOptions: ["Never", "1m", "2m", "5m"]
    readonly property var dimValues: [0, 60, 120, 300]

    readonly property var blankOptions: ["Never", "2m", "5m", "10m", "15m"]
    readonly property var blankValues: [0, 120, 300, 600, 900]

    function valueToOption(val, vals, opts) {
        var idx = vals.indexOf(val);
        return idx >= 0 ? opts[idx] : opts[0];
    }

    function optionToValue(opt, opts, vals) {
        var idx = opts.indexOf(opt);
        return idx >= 0 ? vals[idx] : 0;
    }

    function setIdleKey(key, seconds) {
        setProc.command = ["sh", "-c", "gsettings set org.asura.desktop " + key + " " + seconds + " 2>/dev/null || asura config set org.asura.desktop." + key + " " + seconds + " 2>/dev/null || true"];
        setProc.running = true;
    }

    Process {
        id: probeProc
        running: true
        command: ["sh", "-c",
            "for t in hyprlock hypridle; do command -v $t >/dev/null || echo $t; done; "
            + "pgrep -x hypridle >/dev/null 2>&1 || echo idle-off"]
        stdout: StdioCollector {
            onStreamFinished: pg.missing = text.trim().split("\n").filter(s => s !== "")
        }
    }

    Process {
        id: readSettingsProc
        running: true
        command: ["sh", "-c",
            "printf '%s\\n' "
            + "\"$(gsettings get org.asura.desktop idle-lock-seconds 2>/dev/null || echo 300)\" "
            + "\"$(gsettings get org.asura.desktop idle-dim-seconds 2>/dev/null || echo 0)\" "
            + "\"$(gsettings get org.asura.desktop idle-blank-seconds 2>/dev/null || echo 0)\""]
        stdout: StdioCollector {
            onStreamFinished: {
                var lines = text.trim().split("\n");
                if (lines.length >= 3) {
                    pg.lockSeconds = parseInt(lines[0]) || 0;
                    pg.dimSeconds = parseInt(lines[1]) || 0;
                    pg.blankSeconds = parseInt(lines[2]) || 0;
                }
            }
        }
    }

    Process {
        id: setProc
    }

    Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: contentCol.implicitHeight + Tokens.s8 * 2
        clip: true

        Column {
            id: contentCol
            x: Tokens.s6
            y: Tokens.s6
            width: Math.min(pg.width - Tokens.s6 * 2, 720)
            spacing: Tokens.s4

            Text {
                text: I18n.tr("Lockscreen")
                color: Tokens.ink
                font.family: Tokens.display
                font.pixelSize: Tokens.fTitle
            }

            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                text: I18n.tr("hyprlock renders the lock surface and checks authentication with PAM. hypridle manages inactivity timeouts and power saving.")
                color: Tokens.inkMuted
                font.family: Tokens.ui
                font.pixelSize: Tokens.fBody
            }

            SettingCard {
                width: parent.width
                title: I18n.tr("SESSION SECURITY")

                SettingRow {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    label: I18n.tr("Lock screen now")
                    desc: pg.canLock
                        ? I18n.tr("Locks the current session immediately.")
                        : I18n.tr("hyprlock is not installed.")
                    controlWidth: 110

                    Btn {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: I18n.tr("LOCK NOW")
                        armed: pg.canLock
                        onAct: Quickshell.execDetached(["asura-shell", "lock"])
                    }
                }
            }

            SettingCard {
                width: parent.width
                title: I18n.tr("IDLE TIMEOUTS")

                SettingRow {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    block: true
                    label: I18n.tr("Lock session after")
                    desc: I18n.tr("Inactivity duration before the screen automatically locks.")
                    source: "org.asura.desktop.idle-lock-seconds"

                    Seg {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        options: pg.lockOptions
                        current: pg.valueToOption(pg.lockSeconds, pg.lockValues, pg.lockOptions)
                        onChose: opt => {
                            var sec = pg.optionToValue(opt, pg.lockOptions, pg.lockValues);
                            pg.lockSeconds = sec;
                            pg.setIdleKey("idle-lock-seconds", sec);
                        }
                    }
                }

                SettingRow {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    block: true
                    divider: true
                    label: I18n.tr("Dim display after")
                    desc: I18n.tr("Lowers display brightness before locking to reduce power consumption.")
                    source: "org.asura.desktop.idle-dim-seconds"

                    Seg {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        options: pg.dimOptions
                        current: pg.valueToOption(pg.dimSeconds, pg.dimValues, pg.dimOptions)
                        onChose: opt => {
                            var sec = pg.optionToValue(opt, pg.dimOptions, pg.dimValues);
                            pg.dimSeconds = sec;
                            pg.setIdleKey("idle-dim-seconds", sec);
                        }
                    }
                }

                SettingRow {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    block: true
                    divider: true
                    label: I18n.tr("Turn display off after")
                    desc: I18n.tr("Powers down displays via DPMS standby after prolonged inactivity.")
                    source: "org.asura.desktop.idle-blank-seconds"

                    Seg {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        options: pg.blankOptions
                        current: pg.valueToOption(pg.blankSeconds, pg.blankValues, pg.blankOptions)
                        onChose: opt => {
                            var sec = pg.optionToValue(opt, pg.blankOptions, pg.blankValues);
                            pg.blankSeconds = sec;
                            pg.setIdleKey("idle-blank-seconds", sec);
                        }
                    }
                }
            }

            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                visible: !pg.idleRunning
                text: I18n.tr("Note: hypridle is not currently running in the background; inactivity timeouts will not trigger until hypridle is running.")
                color: Tokens.inkMuted
                font.family: Tokens.ui
                font.pixelSize: Tokens.fMicro
            }
        }
    }
}
