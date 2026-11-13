pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import qs.Ui
import qs.Ui.Singletons
import "../Singletons"

// Animations, kept deliberately small. One card: the master switch for desktop
// motion and a reduce-motion switch for the shell's own panels and menus. The
// window animations themselves are the shipped set — session/hyprland/
// animations.conf, short fades and one slide on the compositor's built-in
// curve, which is also the cheapest motion the compositor can draw — and the
// page no longer edits them per-leaf. Everything this page used to stage (the
// curve workshop, the per-leaf table, focus flash, the preview) is gone from
// the UI; a user who stored overrides keeps them, they are just not editable
// here.
Item {
    id: pg
    property var hub

    // staged store shortcuts (reactive: the cell refreshes on edit/save/revert)
    function hv(path) { return pg.hub ? pg.hub.hyprVal(path) : undefined }
    function cv(path) { return pg.hub ? pg.hub.hyprCommittedVal(path) : undefined }
    function he(path, v) { if (pg.hub) pg.hub.hyprEdit(path, v) }
    function chg(path) { return JSON.stringify(pg.hv(path)) !== JSON.stringify(pg.cv(path)) }

    // reduce motion in shell.json, written instantly through the settings seam
    // (not the staged hypr draft); the shell's ui tokens read the same key and
    // snap every shell animation to its end state while it is on.
    readonly property bool reduceMotion: { Settings.revision; return Settings.get("theme.motion.reduce") === true; }
    function setReduce(v) { Settings.patch("theme.motion.reduce", v); }

    // search integration
    readonly property string query: pg.hub ? (pg.hub.query || "") : ""
    function hit(s) { return pg.query === "" || String(s).toLowerCase().indexOf(pg.query.toLowerCase()) >= 0 }
    readonly property bool mVisible: pg.hit("animations master switch desktop motion reduce motion shell panels")
    readonly property bool anyVisible: pg.mVisible

    // ── head ─────────────────────────────────────────────────────────────────
    Column {
        id: head
        anchors.top: parent.top
        // framed page: the pageArea already insets it, so the head starts at the
        // body's own left edge, over the first card column
        width: Math.max(320, pg.width - Tokens.s4)
        spacing: Tokens.s3

        Row {
            // the register row holds a fixed box, so the rule and the seal keep
            // their distance from the title on every page
            height: Tokens.s5
            spacing: Tokens.s2
            Rectangle { width: 16; height: 1; color: Tokens.ink; anchors.verticalCenter: parent.verticalCenter }
            Image {
                width: 12; height: 12
                anchors.verticalCenter: parent.verticalCenter
                source: Qt.resolvedUrl("../../assets/asura-logo-on-dark.svg")
                sourceSize.width: 24; sourceSize.height: 24
                fillMode: Image.PreserveAspectFit
                smooth: true
            }
            Text {
                text: I18n.tr("DESKTOP"); color: Tokens.inkMuted; font.family: Tokens.ui
                font.pixelSize: Tokens.fTiny; font.weight: Font.Medium; font.letterSpacing: Tokens.trackMark
                anchors.verticalCenter: parent.verticalCenter
            }
        }
        Text { text: I18n.tr("Animations"); color: Tokens.ink; font.family: Tokens.display; font.pixelSize: Tokens.fTitle }
        Text {
            width: Math.min(parent.width, 720)
            text: I18n.tr("One switch for desktop motion, one comfort switch for the shell's own panels. Windows move on short, cheap fades the compositor draws itself.")
            color: Tokens.inkMuted; font.family: Tokens.ui; font.pixelSize: Tokens.fBody; wrapMode: Text.WordWrap
        }
        Item { width: 1; height: Tokens.s1 }
    }

    // ── content ────────────────────────────────────────────────────────────
    Flickable {
        id: flick
        anchors { left: parent.left; right: parent.right; top: head.bottom; bottom: parent.bottom; topMargin: Tokens.s5 }
        contentWidth: width
        contentHeight: col.height + Tokens.s5
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollRail { }
        WheelScroll { }

        CardColumns {
            id: col
            // a body of cards fills the measure and splits into balanced columns
            width: flick.width - Tokens.s4
            spacing: Tokens.s5
            fillTo: flick.height

            SettingCard {
                width: col.colWidth
                title: I18n.tr("MOTION")
                visible: pg.mVisible

                // the one genuine setting: the master switch for desktop motion
                SettingRow {
                    anchors.left: parent.left; anchors.right: parent.right
                    label: I18n.tr("Animations")
                    desc: I18n.tr("Master switch for desktop motion")
                    def: pg.cv("desktop.appearance.animations") ? I18n.tr("ON") : I18n.tr("OFF")
                    changed: pg.chg("desktop.appearance.animations")
                    source: "desktop.json"
                    controlWidth: 54
                    Sw {
                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                        on: !!pg.hv("desktop.appearance.animations")
                        onToggled: (v) => pg.he("desktop.appearance.animations", v)
                    }
                }

                SettingRow {
                    anchors.left: parent.left; anchors.right: parent.right
                    divider: true
                    label: I18n.tr("Reduce motion")
                    desc: I18n.tr("Snap the shell's own animations into place instead of playing them.")
                    controlWidth: 54
                    Sw {
                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                        on: pg.reduceMotion
                        onToggled: (v) => pg.setReduce(v)
                    }
                }
            }
        }
    }

    // no-match state, mirroring the schema sheet
    Column {
        anchors.centerIn: flick
        visible: pg.query !== "" && !pg.anyVisible
        spacing: Tokens.s2
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: I18n.tr("NO MATCH"); color: Tokens.inkDim; font.family: Tokens.ui
            font.pixelSize: Tokens.fSmall; font.letterSpacing: 2
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: I18n.tr("nothing here matches “%1”").arg(pg.query)
            color: Tokens.inkMuted; font.family: Tokens.ui; font.pixelSize: Tokens.fSmall
        }
    }
}
