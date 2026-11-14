import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui.Singletons
import "../IconMap.js" as IconMap

Item {
    id: rootMod
    required property var root

    visible: implicitWidth > 0.5
    implicitWidth: root.modMemory ? row.implicitWidth + 18 : 0
    implicitHeight: 28
    opacity: root.modMemory ? 1 : 0

    Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

    readonly property int percent: root.systemMemPercent
    readonly property real usedGiB: root.systemMemUsedGiB
    readonly property real totalGiB: root.systemMemTotalGiB
    readonly property string usedLabel: String(Math.round(usedGiB)).padStart(2, '0') + "G"
    readonly property string tooltipText: usedGiB.toFixed(1) + "/" + totalGiB.toFixed(0) + "G"
    readonly property color contentColor: root.widgetContentColor("G4", root.widgetIconColor)

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 4

        IconText {
            anchors.verticalCenter: parent.verticalCenter
            text: IconMap.icon("memory")
            color: rootMod.contentColor
            font.pixelSize: 15
            font.weight: Font.Medium
            fill: 0
        }

        UiText {
            visible: !root.iconOnly("G4")
            anchors.verticalCenter: parent.verticalCenter
            text: rootMod.usedLabel
            color: rootMod.contentColor
            font.family: root.mono
            font.pixelSize: 12
        }
    }

    TooltipMixin { id: tip; root: rootMod.root; owner: rootMod; text: rootMod.tooltipText }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onEntered: tip.show()
        onExited: { tip.hide() }
        onClicked: { tip.hide(); root.memVisible = !root.memVisible }
    }
}
