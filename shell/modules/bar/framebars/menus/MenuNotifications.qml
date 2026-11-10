pragma ComponentBehavior: Bound

import QtQuick
import "../.." as Pill
import qs.Services
import "../../../../components"
import "../../../notifications"
import qs.Ui.Singletons

// Notification history panel (contract 07 sec 2.3/4.3): a DND toggle, a
// "Notifications" title, count badge, and a "Clear all" action, an empty
// placeholder when clean, then every notification newest first as its own card.
// Cards come from the shared NotificationCard; the model is flat Notifs.history.
Item {
    id: root

    property real s: 1
    property real avail: 0
    property bool open: false
    signal requestClose()

    readonly property var notifs: root.open ? (Notifs.history || []) : []

    implicitWidth: 410 * root.s
    implicitHeight: root.avail > 0 ? root.avail : (root.notifs.length === 0 ? (240 * root.s) : Math.min(480 * root.s, (80 + root.notifs.length * 85) * root.s))

    Column {
        id: headerCol
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 12 * root.s

        // Top bar: title, count badge, DND toggle, clear all
        Item {
            id: header
            width: parent.width
            height: 38 * root.s

            // Left: Title and optional unread count pill
            Row {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8 * root.s

                Text {
                    id: titleText
                    text: I18n.tr("Notifications")
                    color: Theme.onSurface
                    font.family: Theme.fontPrimary
                    font.pixelSize: Theme.fontLg
                    font.weight: Font.Bold
                    anchors.verticalCenter: parent.verticalCenter
                }

                Rectangle {
                    visible: root.notifs.length > 0
                    height: 18 * root.s
                    width: Math.max(18 * root.s, countLabel.implicitWidth + 10 * root.s)
                    radius: height / 2
                    color: Theme.surfaceRaised
                    border.width: 1
                    border.color: Theme.outline
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                        id: countLabel
                        anchors.centerIn: parent
                        text: "" + root.notifs.length
                        color: Theme.onSurface
                        font.family: Theme.fontPrimary
                        font.pixelSize: Theme.fontSm - 2
                        font.weight: Font.DemiBold
                    }
                }
            }

            // Right: DND quick switch and Clear All
            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 10 * root.s

                // DND Toggle Button
                Rectangle {
                    id: dndBtn
                    width: Theme.iconSm + Theme.paddingSm * 2
                    height: width
                    radius: Theme.radiusWidget
                    color: Flags.dnd
                        ? Theme.surfaceRaised
                        : (dndHov.hovered
                            ? Qt.tint(Theme.surface, Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.08))
                            : "transparent")
                    border.width: Flags.dnd ? 1 : 0
                    border.color: Theme.outline
                    anchors.verticalCenter: parent.verticalCenter

                    MaterialIcon {
                        anchors.centerIn: parent
                        text: Flags.dnd ? "do_not_disturb_on" : "notifications"
                        font.pixelSize: Theme.iconSm
                        color: Flags.dnd ? Theme.onSurface : (dndHov.hovered ? Theme.onSurface : Theme.onSurfaceVariant)
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Flags.dnd = !Flags.dnd
                        HoverHandler { id: dndHov }
                    }
                }

                // Clear All Button
                Rectangle {
                    id: clearBtnContainer
                    visible: root.notifs.length > 0
                    height: dndBtn.height
                    width: clearText.implicitWidth + 16 * root.s
                    radius: Theme.radiusWidget
                    color: clearHov.hovered
                        ? Qt.tint(Theme.surface, Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.08))
                        : "transparent"
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                        id: clearText
                        anchors.centerIn: parent
                        text: I18n.tr("Clear all")
                        color: clearHov.hovered ? Theme.onSurface : Theme.onSurfaceVariant
                        font.family: Theme.fontPrimary
                        font.pixelSize: Theme.fontSm
                        font.weight: Font.Medium
                    }

                    HoverHandler { id: clearHov; cursorShape: Qt.PointingHandCursor }
                    TapHandler {
                        onTapped: {
                            Notifs.clearAll();
                            root.requestClose();
                        }
                    }
                }
            }
        }

        // Clean divider line below header
        Rectangle {
            width: parent.width
            height: 1
            color: Theme.outline
            opacity: 0.35
        }
    }

    // Empty state plate
    Item {
        anchors.top: headerCol.bottom
        anchors.topMargin: 12 * root.s
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 12 * root.s
        visible: root.notifs.length === 0

        Column {
            anchors.centerIn: parent
            spacing: 10 * root.s
            width: parent.width * 0.85

            MaterialIcon {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "notifications_none"
                font.pixelSize: 42 * root.s
                color: Theme.onSurfaceVariant
                opacity: 0.4
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: I18n.tr("No notifications")
                color: Theme.onSurface
                font.family: Theme.fontPrimary
                font.pixelSize: Theme.fontMd
                font.weight: Font.Medium
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: I18n.tr("You're all caught up")
                color: Theme.onSurfaceVariant
                font.family: Theme.fontPrimary
                font.pixelSize: Theme.fontSm
                opacity: 0.7
            }
        }
    }

    // Scrollable Notifications list
    ListView {
        id: notificationList
        anchors.top: headerCol.bottom
        anchors.topMargin: 12 * root.s
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 8 * root.s
        visible: root.notifs.length > 0
        clip: true
        spacing: 10 * root.s
        model: root.notifs
        reuseItems: true
        cacheBuffer: Math.max(0, height)
        boundsBehavior: Flickable.StopAtBounds

        delegate: NotificationCard {
            required property var modelData
            width: notificationList.width
            notif: modelData
            onActionInvoked: root.requestClose()
        }
    }
}
