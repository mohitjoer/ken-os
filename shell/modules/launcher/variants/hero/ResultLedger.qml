import QtQuick
import qs.Ui
import qs.Ui.Singletons as Ui
import "../../shared/Singletons"

// The results, one column: a row per result — icon, title, and the provider
// tag on the right. The selected row is the lead itself: it lifts (raised
// fill, hairline border) and its right side becomes the command column — the
// verb and the Enter hint the old lead card carried. There is no duplicate
// of the selection above the list, and no rank numerals. Selecting is not
// committing: click a highlighted row (or press Enter) to run it.
ListView {
    id: root

    property real s: 1
    property var results: []
    property string selectedResultKey: ""
    property int windowCount: 0
    property bool windowFocusActive: false
    property int secondaryCount: 0

    signal resultSelected(string resultKey, int rank)
    signal activateRequested()

    readonly property var rows: {
        var output = [];
        var source = root.results || [];
        for (var index = 0; index < source.length; index++) {
            var entry = source[index];
            if (entry)
                output.push({ entry: entry, rank: index + 1 });
        }
        return output;
    }
    readonly property real rowHeight: 44 * s
    readonly property real desiredHeight: rows.length * rowHeight

    model: rows.length
    clip: true
    reuseItems: true
    boundsBehavior: Flickable.StopAtBounds
    flickDeceleration: 2600

    function revealRank(rank) {
        if (rows.length === 0)
            return;
        var filtered = rows.length - 1;
        for (var index = 0; index < rows.length; index++) {
            if (rows[index].rank - 1 >= rank) {
                filtered = index;
                break;
            }
        }
        positionViewAtIndex(Math.max(0, filtered), ListView.Contain);
    }

    function metadataFor(source) {
        if (!source)
            return "";
        var provider = Ui.I18n.tr(String(source.type || source.providerId || "")).toUpperCase();
        var detail = String(source.subtitle || "");
        return provider.length && detail.length ? provider + " / " + detail
            : (provider.length ? provider : detail);
    }

    delegate: Item {
        id: cell

        required property int index
        readonly property var rowData: root.rows[index]
        readonly property var entry: rowData ? rowData.entry : null
        readonly property bool selected: entry !== null
            && entry.resultKey === root.selectedResultKey
        readonly property bool hasIcon: entry && String(entry.icon || "").length > 0
        readonly property bool hasPreview: entry
            && String(entry.preview || "").length > 0
        readonly property bool isWeb: entry && String(entry.providerId || "") === "web"
        readonly property var primaryAction: selected && entry
            ? entry.primaryAction : null
        readonly property bool executable: primaryAction !== null
            && entry && !entry.disabled
        // the command column, carried over from the old lead card: the verb,
        // the window nuance, and the shelf hint — one line each.
        readonly property string verb: primaryAction
            ? (root.windowCount > 0 ? Ui.I18n.tr("OPEN NEW")
                : String(primaryAction.name || Ui.I18n.tr("OPEN")).toUpperCase())
            : Ui.I18n.tr("INFO")
        readonly property string hint: !executable ? Ui.I18n.tr("NO ACTION")
            : root.secondaryCount > 0
                ? Ui.I18n.tr("+%1 MORE  \u00b7  CTRL+K").arg(root.secondaryCount)
                : root.windowCount > 0
                    ? (root.windowFocusActive
                        ? Ui.I18n.tr("WINDOW FOCUS  \u00b7  ENTER")
                        : Ui.I18n.tr("ENTER NEW  \u00b7  TAB WINDOWS"))
                    : Ui.I18n.tr("\u23ce  ENTER")

        objectName: "result-" + (entry ? String(entry.resultKey || "") : "")
        width: ListView.view.width
        height: root.rowHeight
        opacity: entry && entry.disabled ? 0.56 : 1

        Accessible.role: Accessible.ListItem
        Accessible.name: entry ? String(entry.title || "") : ""
        Accessible.description: entry
            ? Ui.I18n.tr("Rank %1, %2").arg(String(rowData.rank))
                .arg(String(entry.type || entry.providerId || ""))
            : ""
        Accessible.ignored: entry === null
        Accessible.focusable: false
        Accessible.selectable: entry !== null
        Accessible.selected: cell.selected
        Accessible.defaultButton: cell.selected && cell.executable
        Accessible.onPressAction: cell.commit()

        function selectResult() {
            if (entry)
                root.resultSelected(entry.resultKey, rowData.rank - 1);
        }

        function commit() {
            if (cell.selected)
                root.activateRequested();
            else
                cell.selectResult();
        }

        Entrance {
            anchors.fill: parent
            index: cell.index
            // The fill makes the implicit size inert here, and measuring it
            // from childrenRect feedback-loops against the view's delegate
            // repositioning (Binding loop on implicitWidth/implicitHeight).
            implicitWidth: cell.width
            implicitHeight: cell.height

            Rectangle {
                anchors.fill: parent
                color: cell.selected ? Theme.drawerRaised : "transparent"
                border.width: cell.selected ? 1 : 0
                border.color: Theme.bright
                Behavior on color {
                    ColorAnimation { duration: Motion.selection; easing.type: Easing.OutCubic }
                }
            }

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 1
                color: Theme.hair
                visible: !cell.selected
            }

            Rectangle {
                id: icon
                anchors.left: parent.left
                anchors.leftMargin: 10 * root.s
                anchors.verticalCenter: parent.verticalCenter
                width: cell.hasPreview || cell.hasIcon || cell.isWeb ? 21 * root.s : 0
                height: width
                color: cell.isWeb ? Theme.onLead : Theme.drawerRaised
                border.width: cell.hasPreview ? 1 : 0
                border.color: Theme.hair
                clip: true

                Image {
                    anchors.fill: parent
                    sourceSize.width: Math.round(42 * root.s)
                    sourceSize.height: Math.round(42 * root.s)
                    fillMode: cell.hasPreview ? Image.PreserveAspectCrop
                        : Image.PreserveAspectFit
                    asynchronous: true
                    smooth: true
                    visible: cell.hasPreview || cell.hasIcon
                    source: cell.hasPreview ? cell.entry.preview : cell.entry.icon
                }

                Text {
                    anchors.centerIn: parent
                    visible: cell.isWeb
                    text: "?"
                    color: Theme.drawer
                    font.family: Theme.mono
                    font.pixelSize: 14 * root.s
                    font.weight: Font.DemiBold
                }
            }

            Text {
                anchors.left: icon.right
                anchors.leftMargin: cell.hasIcon ? 9 * root.s : 0
                anchors.right: cell.selected ? command.left : tag.left
                anchors.rightMargin: 10 * root.s
                anchors.verticalCenter: parent.verticalCenter
                text: cell.entry ? String(cell.entry.title || "") : ""
                color: cell.entry && cell.entry.disabled ? Theme.faint : Theme.cream
                font.family: Theme.font
                font.pixelSize: 11 * root.s
                font.weight: Font.Medium
                elide: Text.ElideRight
            }

            // resting rows carry the provider tag on the right; the selected
            // row swaps it for the command column.
            Text {
                id: tag
                anchors.right: parent.right
                anchors.rightMargin: 10 * root.s
                anchors.verticalCenter: parent.verticalCenter
                visible: !cell.selected
                text: root.metadataFor(cell.entry)
                color: Theme.faint
                font.family: Theme.mono
                font.pixelSize: 7.5 * root.s
                font.letterSpacing: 0.7 * root.s
                elide: Text.ElideMiddle
                width: Math.min(implicitWidth, cell.width * 0.45)
            }

            Column {
                id: command
                anchors.right: parent.right
                anchors.rightMargin: 10 * root.s
                anchors.verticalCenter: parent.verticalCenter
                visible: cell.selected
                spacing: 2 * root.s

                Text {
                    anchors.right: parent.right
                    text: cell.verb
                    color: Theme.bright
                    font.family: Theme.mono
                    font.pixelSize: 9 * root.s
                    font.weight: Font.DemiBold
                    font.letterSpacing: 0.8 * root.s
                }

                Text {
                    anchors.right: parent.right
                    text: cell.hint
                    color: Theme.faint
                    font.family: Theme.mono
                    font.pixelSize: 7.5 * root.s
                    font.letterSpacing: 0.5 * root.s
                }
            }

            MouseArea {
                id: pointer
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor

                onClicked: cell.commit()
            }
        }
    }
}
