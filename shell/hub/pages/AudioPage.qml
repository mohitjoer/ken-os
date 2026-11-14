pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Services
import qs.Ui
import qs.Ui.Singletons

// Audio & Equalizer (DEVICES). Output volume, microphones, per-application streams,
// and the system's 10-band PipeWire graphic equalizer.
//
// Self-contained full-bleed page: draws its own header and scrolling body.
// The Equalizer is powered by the Equalizer singleton and asura-eq DSP filter chain.
Item {
    id: pg

    property var hub
    readonly property bool fullBleed: true

    Component.onCompleted: {
        Equalizer.refresh()
    }

    // ── Watermark & Head ────────────────────────────────────────────────────
    Watermark {
        anchors.fill: parent
        text: "AUDIO"
    }

    Column {
        id: head
        anchors {
            left: parent.left; right: parent.right; top: parent.top
            leftMargin: Tokens.s6; rightMargin: Tokens.s6; topMargin: Tokens.s6
        }
        spacing: Tokens.s2

        Text {
            text: I18n.tr("DEVICES")
            color: Tokens.inkDim; font.family: Tokens.mono
            font.pixelSize: Tokens.fSmall; font.letterSpacing: 2
            font.weight: Font.DemiBold
        }
        Text {
            text: I18n.tr("Audio & Equalizer")
            color: Tokens.ink; font.family: Tokens.serif
            font.pixelSize: Tokens.fTitle; font.weight: Font.Medium
        }
        Text {
            width: Math.min(parent.width, 720)
            text: I18n.tr("Volume, sound devices, and the desktop 10-band graphic equalizer.")
            color: Tokens.inkMuted; font.family: Tokens.ui
            font.pixelSize: Tokens.fBody; wrapMode: Text.WordWrap
        }
    }

    // ── Content ─────────────────────────────────────────────────────────────
    Item {
        id: body
        anchors {
            left: parent.left; right: parent.right; top: head.bottom; bottom: parent.bottom
            leftMargin: Tokens.s6; rightMargin: Tokens.s6; topMargin: Tokens.s5; bottomMargin: Tokens.s6
        }

        Flickable {
            id: flick
            anchors.fill: parent
            contentWidth: width
            contentHeight: contentCol.height + Tokens.s6
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollRail { policy: ScrollBar.AsNeeded }
            WheelScroll { }

            Column {
                id: contentCol
                width: flick.width - Tokens.s3
                spacing: Tokens.s5

                // ═══════════════════════════════════════════════════════════
                // SECTION 1: 10-BAND GRAPHIC EQUALIZER
                // ═══════════════════════════════════════════════════════════
                Rectangle {
                    width: parent.width
                    height: eqCol.height + Tokens.s5 * 2
                    radius: Tokens.radius
                    color: Tokens.tint5
                    border.width: Tokens.border
                    border.color: Tokens.line

                    Column {
                        id: eqCol
                        anchors {
                            left: parent.left; right: parent.right; top: parent.top
                            margins: Tokens.s5
                        }
                        spacing: Tokens.s4

                        // Header row with ON/OFF switch
                        Row {
                            width: parent.width
                            height: 32

                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 2

                                Row {
                                    spacing: Tokens.s2
                                    Text {
                                        text: I18n.tr("10-BAND GRAPHIC EQUALIZER")
                                        color: Tokens.ink
                                        font.family: Tokens.mono
                                        font.pixelSize: Tokens.fSmall
                                        font.letterSpacing: 1.5
                                        font.weight: Font.DemiBold
                                    }
                                    Rectangle {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 6; height: 6
                                        radius: 3
                                        color: Equalizer.on ? Tokens.ink : Tokens.inkFaint
                                    }
                                }
                                Text {
                                    text: I18n.tr("PipeWire parametric filter chain with real-time biquad audio DSP")
                                    color: Tokens.inkMuted
                                    font.family: Tokens.ui
                                    font.pixelSize: Tokens.fMicro
                                }
                            }

                            Item {
                                width: Math.max(0, parent.width - 450)
                                height: 1
                            }

                            // Preset tag + ON/OFF toggle
                            Row {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: Tokens.s3

                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    height: 26
                                    width: presetText.implicitWidth + 16
                                    radius: Tokens.radius
                                    color: Tokens.paper
                                    border.width: Tokens.border
                                    border.color: Tokens.line

                                    Text {
                                        id: presetText
                                        anchors.centerIn: parent
                                        text: Equalizer.presetLabel(Equalizer.preset)
                                        color: Tokens.ink
                                        font.family: Tokens.mono
                                        font.pixelSize: Tokens.fMicro
                                        font.weight: Font.Medium
                                    }
                                }

                                Rectangle {
                                    id: eqToggleBtn
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 58; height: 26
                                    radius: Tokens.radius
                                    color: Equalizer.on ? Tokens.ink : Tokens.paper
                                    border.width: Tokens.border
                                    border.color: Equalizer.on ? Tokens.ink : Tokens.line

                                    Behavior on color { ColorAnimation { duration: 120 } }

                                    Text {
                                        anchors.centerIn: parent
                                        text: Equalizer.on ? I18n.tr("ON") : I18n.tr("OFF")
                                        color: Equalizer.on ? Tokens.paper : Tokens.inkMuted
                                        font.family: Tokens.mono
                                        font.pixelSize: Tokens.fSmall
                                        font.weight: Font.Bold
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: Equalizer.setOn(!Equalizer.on)
                                    }
                                }
                            }
                        }

                        // Presets row
                        Flow {
                            width: parent.width
                            spacing: Tokens.s2

                            Repeater {
                                model: Equalizer.presets
                                delegate: Rectangle {
                                    id: pChip
                                    required property string modelData
                                    readonly property bool active: Equalizer.preset === modelData

                                    width: pChipText.implicitWidth + 24
                                    height: 28
                                    radius: Tokens.radius
                                    color: active ? Tokens.ink : (pChipMa.containsMouse ? Tokens.tint8 : Tokens.paper)
                                    border.width: Tokens.border
                                    border.color: active ? Tokens.ink : (pChipMa.containsMouse ? Tokens.lineStrong : Tokens.line)

                                    Behavior on color { ColorAnimation { duration: 120 } }

                                    Text {
                                        id: pChipText
                                        anchors.centerIn: parent
                                        text: Equalizer.presetLabel(pChip.modelData)
                                        color: pChip.active ? Tokens.paper : Tokens.ink
                                        font.family: Tokens.ui
                                        font.pixelSize: Tokens.fSmall
                                        font.weight: pChip.active ? Font.DemiBold : Font.Normal
                                    }

                                    MouseArea {
                                        id: pChipMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: Equalizer.applyPreset(pChip.modelData)
                                    }
                                }
                            }
                        }

                        // Equalizer Sliders Container
                        Rectangle {
                            width: parent.width
                            height: 180
                            radius: Tokens.radius
                            color: Tokens.paper
                            border.width: Tokens.border
                            border.color: Tokens.line

                            Row {
                                id: bandRow
                                anchors.fill: parent
                                anchors.margins: Tokens.s4

                                Repeater {
                                    model: Equalizer.bandCount
                                    delegate: Item {
                                        id: bandItem
                                        required property int index
                                        width: bandRow.width / Equalizer.bandCount
                                        height: bandRow.height

                                        property bool dragging: false
                                        property int dragDb: 0
                                        readonly property int db: dragging ? dragDb : Equalizer.gainAt(index)
                                        readonly property real frac: (db + Equalizer.range) / (2 * Equalizer.range)

                                        readonly property int trackHeight: bandItem.height - 38
                                        readonly property real handleSize: 14

                                        function dbAt(y) {
                                            var usable = bandItem.trackHeight - bandItem.handleSize
                                            var t = 1 - Math.max(0, Math.min(1, (y - bandItem.handleSize / 2) / usable))
                                            return Math.round(t * 2 * Equalizer.range - Equalizer.range)
                                        }

                                        Timer {
                                            id: bandPush
                                            interval: 100
                                            onTriggered: Equalizer.setBand(bandItem.index, bandItem.dragDb)
                                        }

                                        // Slider track
                                        Rectangle {
                                            id: bTrack
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            anchors.top: parent.top
                                            anchors.topMargin: 4
                                            width: 8
                                            height: bandItem.trackHeight
                                            radius: 4
                                            color: Tokens.tint8
                                            border.width: Tokens.border
                                            border.color: bMa.containsMouse || bandItem.dragging ? Tokens.ink : Tokens.line

                                            // Filled bar
                                            Rectangle {
                                                anchors.bottom: parent.bottom
                                                anchors.left: parent.left
                                                anchors.right: parent.right
                                                anchors.margins: 1
                                                height: Math.max(0, (parent.height - 2) * bandItem.frac)
                                                radius: 3
                                                color: Equalizer.on ? Tokens.ink : Tokens.inkFaint

                                                Behavior on height {
                                                    NumberAnimation {
                                                        duration: bandItem.dragging ? 0 : 200
                                                        easing.type: Easing.OutCubic
                                                    }
                                                }
                                            }

                                            // 0 dB center tick
                                            Rectangle {
                                                anchors.horizontalCenter: parent.horizontalCenter
                                                y: (parent.height - 2) * 0.5
                                                width: parent.width + 6
                                                height: 1
                                                color: Tokens.inkDim
                                            }
                                        }

                                        // Handle
                                        Rectangle {
                                            id: bHandle
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            width: bandItem.handleSize
                                            height: width
                                            radius: width / 2
                                            y: 4 + (bandItem.trackHeight - bandItem.handleSize) * (1 - bandItem.frac)
                                            color: Tokens.paper
                                            border.width: 2
                                            border.color: Equalizer.on ? Tokens.ink : Tokens.inkDim
                                            scale: bandItem.dragging ? 1.25 : 1

                                            Behavior on y {
                                                NumberAnimation {
                                                    duration: bandItem.dragging ? 0 : 200
                                                    easing.type: Easing.OutCubic
                                                }
                                            }
                                            Behavior on scale { NumberAnimation { duration: 120 } }
                                        }

                                        MouseArea {
                                            id: bMa
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            anchors.top: parent.top
                                            width: 28
                                            height: bandItem.trackHeight + 8
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor

                                            onPressed: (m) => {
                                                bandItem.dragDb = bandItem.dbAt(m.y)
                                                bandItem.dragging = true
                                                bandPush.restart()
                                            }
                                            onPositionChanged: (m) => {
                                                if (!bandItem.dragging) return
                                                var next = bandItem.dbAt(m.y)
                                                if (next === bandItem.dragDb) return
                                                bandItem.dragDb = next
                                                if (!bandPush.running) bandPush.restart()
                                            }
                                            onReleased: {
                                                bandPush.stop()
                                                Equalizer.setBand(bandItem.index, bandItem.dragDb)
                                                bandItem.dragging = false
                                            }
                                            onCanceled: {
                                                bandPush.stop()
                                                bandItem.dragging = false
                                            }
                                            onWheel: (w) => {
                                                var step = w.angleDelta.y > 0 ? 1 : -1
                                                Equalizer.setBand(bandItem.index, Equalizer.gainAt(bandItem.index) + step)
                                            }
                                        }

                                        // Label underneath
                                        Text {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            anchors.top: bTrack.bottom
                                            anchors.topMargin: 8
                                            text: bMa.containsMouse || bandItem.dragging
                                                ? (bandItem.db > 0 ? "+" + bandItem.db : "" + bandItem.db)
                                                : Equalizer.bandLabels[bandItem.index]
                                            color: bMa.containsMouse || bandItem.dragging ? Tokens.ink : Tokens.inkMuted
                                            font.family: Tokens.mono
                                            font.pixelSize: Tokens.fMicro
                                            font.weight: bMa.containsMouse ? Font.Bold : Font.Normal
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // ═══════════════════════════════════════════════════════════
                // SECTION 2: OUTPUT & VOLUME
                // ═══════════════════════════════════════════════════════════
                SettingCard {
                    width: parent.width
                    title: I18n.tr("Output Devices & Volume")
                    collapsible: false

                    SettingRow {
                        label: I18n.tr("Default Output Device")
                        desc: Audio.sink ? (Audio.sink.description || Audio.sink.name) : I18n.tr("None detected")
                        divider: false

                        Btn {
                            text: Audio.muted ? I18n.tr("Unmute") : I18n.tr("Mute")
                            primary: Audio.muted
                            onAct: Audio.setMuted(!Audio.muted)
                        }
                    }

                    SettingRow {
                        label: I18n.tr("Master Output Volume")
                        desc: I18n.tr("Desktop playback volume level (%1%)").arg(Audio.volume)
                        value: Audio.volume + "%"
                        divider: true
                        banded: true

                        Slid {
                            anchors.fill: parent
                            from: 0
                            to: pg.hub && pg.hub.cfg && pg.hub.cfg.qsbar && pg.hub.cfg.qsbar.audioBoost ? 150 : 100
                            value: Audio.volume
                            onModified: (v) => Audio.setVolume(v)
                        }
                    }

                    SettingRow {
                        label: I18n.tr("Volume Boost")
                        desc: I18n.tr("Allow audio output volume to exceed 100% up to 150%")
                        divider: true

                        Sw {
                            checked: pg.hub && pg.hub.cfg && pg.hub.cfg.qsbar ? pg.hub.cfg.qsbar.audioBoost === true : false
                            onClicked: {
                                if (pg.hub && pg.hub.cfg && pg.hub.cfg.qsbar) {
                                    pg.hub.cfg.qsbar.audioBoost = !pg.hub.cfg.qsbar.audioBoost
                                }
                            }
                        }
                    }
                }

                // ═══════════════════════════════════════════════════════════
                // SECTION 3: INPUT (MICROPHONE)
                // ═══════════════════════════════════════════════════════════
                SettingCard {
                    width: parent.width
                    title: I18n.tr("Input & Microphone")
                    collapsible: false

                    SettingRow {
                        label: I18n.tr("Default Microphone")
                        desc: Audio.source ? (Audio.source.description || Audio.source.name) : I18n.tr("None detected")
                        divider: false

                        Btn {
                            readonly property bool isMuted: Audio.source && Audio.source.audio ? Audio.source.audio.muted : false
                            text: isMuted ? I18n.tr("Unmute Mic") : I18n.tr("Mute Mic")
                            primary: isMuted
                            onAct: if (Audio.source && Audio.source.audio) Audio.source.audio.muted = !Audio.source.audio.muted
                        }
                    }

                    SettingRow {
                        label: I18n.tr("Microphone Input Level")
                        desc: I18n.tr("Recording sensitivity level")
                        divider: true
                        banded: true

                        Slid {
                            anchors.fill: parent
                            from: 0
                            to: 100
                            value: Audio.source && Audio.source.audio ? Math.round(Audio.source.audio.volume * 100) : 0
                            onModified: (v) => {
                                if (Audio.source && Audio.source.audio)
                                    Audio.source.audio.volume = v / 100.0
                            }
                        }
                    }
                }

                // ═══════════════════════════════════════════════════════════
                // SECTION 4: APPLICATION STREAMS
                // ═══════════════════════════════════════════════════════════
                SettingCard {
                    width: parent.width
                    title: I18n.tr("Application Volume Controls")
                    collapsible: true
                    expanded: true

                    Repeater {
                        model: Audio.streams || []
                        delegate: SettingRow {
                            id: streamRow
                            required property var modelData
                            readonly property string sName: Audio.streamName(modelData) || I18n.tr("Application")
                            readonly property int sVol: modelData && modelData.audio ? Math.round(modelData.audio.volume * 100) : 100
                            readonly property bool sMuted: modelData && modelData.audio ? modelData.audio.muted : false

                            label: sName
                            desc: sMuted ? I18n.tr("Muted") : I18n.tr("Volume: %1%").arg(sVol)
                            value: sVol + "%"
                            divider: true
                            banded: true

                            Slid {
                                anchors.fill: parent
                                from: 0
                                to: 100
                                value: streamRow.sVol
                                onModified: (v) => {
                                    if (streamRow.modelData && streamRow.modelData.audio)
                                        streamRow.modelData.audio.volume = v / 100.0
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
