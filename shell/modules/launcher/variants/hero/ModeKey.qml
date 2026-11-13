import QtQuick
import qs.Ui
import qs.Ui.Singletons
import "../../shared/Singletons"

// A launcher mode as a quiet text tab: no box, no fill — the underline is the
// only ornament, and it belongs to the active mode alone.
Item {
    id: root

    property real s: 1
    property string label: ""
    property bool active: false

    signal activated()

    implicitWidth: caption.implicitWidth + 18 * s
    implicitHeight: 24 * s

    Accessible.role: Accessible.Button
    Accessible.name: label
    Accessible.description: active ? I18n.tr("Active launcher mode") : I18n.tr("Launcher mode")
    Accessible.focusable: false
    Accessible.checkable: true
    Accessible.checked: active
    Accessible.selectable: true
    Accessible.selected: active
    Accessible.onPressAction: root.activated()

    Text {
        id: caption
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        text: root.label
        color: root.active ? Theme.bright
            : (pointer.hovered ? Theme.cream : Theme.faint)
        font.family: Theme.mono
        font.pixelSize: 9 * root.s
        font.weight: Font.DemiBold
        font.letterSpacing: 1.4 * root.s
        Behavior on color {
            ColorAnimation { duration: Motion.selection; easing.type: Easing.OutCubic }
        }
    }

    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: caption.bottom
        anchors.topMargin: 4 * root.s
        width: caption.implicitWidth
        height: Math.max(1, root.s)
        color: root.active ? Theme.bright : "transparent"
        Behavior on color {
            ColorAnimation { duration: Motion.selection; easing.type: Easing.OutCubic }
        }
    }

    HoverHandler {
        id: pointer
        cursorShape: Qt.PointingHandCursor
    }

    TapHandler {
        onTapped: root.activated()
    }
}
