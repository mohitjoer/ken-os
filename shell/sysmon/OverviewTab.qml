import QtQuick
import QtQuick.Controls

Item {
    id: tab
    property var stats
    property var app

    readonly property real cpuPct: stats && stats.cpu ? stats.cpu.usagePercent : 0
    readonly property real memPct: stats && stats.memory ? stats.memory.usedPercent : 0
    readonly property real swapPct: stats && stats.swap ? stats.swap.usedPercent : 0
    readonly property real cpuTemp: stats && stats.cpu ? stats.cpu.tempC : 0

    readonly property string fontUi: app ? app.fontUi : "Space Grotesk, Inter, system-ui, sans-serif"
    readonly property string fontMono: app ? app.fontMono : "JetBrains Mono, monospace"

    Flickable {
        anchors.fill: parent
        anchors.margins: 16
        contentWidth: width
        contentHeight: Math.max(grid.implicitHeight + 20, height)
        clip: true

        Grid {
            id: grid
            width: parent.width
            columns: parent.width > 760 ? 2 : 1
            spacing: 14

            // ════════════════════════════════════════════════════════════════
            // ── Card 1: Processor (CPU) with Live Rolling Waveform ──────────
            // ════════════════════════════════════════════════════════════════
            Rectangle {
                width: (grid.width - (grid.columns - 1) * grid.spacing) / grid.columns
                height: 310
                radius: 8
                color: "#10131c"
                border.color: "#1e2332"
                border.width: 1

                Column {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 10

                    // Header row
                    Item {
                        width: parent.width
                        height: 20
                        Row {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 8
                            Text {
                                text: "PROCESSOR (CPU)"
                                color: "#9ca3af"
                                font.family: tab.fontMono
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                                font.letterSpacing: 1
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Rectangle {
                                width: 1; height: 12
                                color: "#252b3d"
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                text: (tab.stats && tab.stats.cpu && tab.stats.cpu.cores ? tab.stats.cpu.cores.length : "0") + " CORES"
                                color: "#6b7280"
                                font.family: tab.fontMono
                                font.pixelSize: 10
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        // Temp Badge
                        Rectangle {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            height: 20
                            width: tempText.implicitWidth + 12
                            radius: 4
                            color: tab.cpuTemp > 80 ? "#3b1717" : "#171b26"
                            border.color: tab.cpuTemp > 80 ? "#7f1d1d" : "#283044"
                            border.width: 1
                            Text {
                                id: tempText
                                anchors.centerIn: parent
                                text: tab.cpuTemp > 0 ? Math.round(tab.cpuTemp) + " °C" : "-- °C"
                                color: tab.cpuTemp > 80 ? "#f87171" : "#e5e7eb"
                                font.family: tab.fontMono
                                font.pixelSize: 10
                                font.weight: Font.Medium
                            }
                        }
                    }

                    // Numeric Summary Row
                    Row {
                        width: parent.width
                        spacing: 16
                        Text {
                            text: Math.round(tab.cpuPct) + "%"
                            color: "#ffffff"
                            font.family: tab.fontUi
                            font.pixelSize: 34
                            font.weight: Font.Bold
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2
                            Text {
                                text: "LOAD " + (tab.stats && tab.stats.loadAvg ? tab.stats.loadAvg.map(function(v) { return v.toFixed(2); }).join("  ") : "0.00  0.00  0.00")
                                color: "#d1d5db"
                                font.family: tab.fontMono
                                font.pixelSize: 11
                            }
                            Text {
                                text: "Real-time kernel scheduler utilization"
                                color: "#6b7280"
                                font.family: tab.fontUi
                                font.pixelSize: 10
                            }
                        }
                    }

                    // ── Live CPU Rolling Area Chart ──
                    Canvas {
                        id: cpuCanvas
                        width: parent.width
                        height: 72
                        property var pts: app ? app.cpuHistory : []
                        onPtsChanged: requestPaint()
                        onPaint: {
                            var ctx = getContext("2d");
                            ctx.reset();
                            var arr = pts || [];
                            var n = arr.length;
                            if (n < 2) return;
                            var dx = width / (n - 1);
                            function fy(v) { return height - Math.max(0, Math.min(1, v)) * (height - 6) - 3; }

                            // Subtle guideline grid
                            ctx.strokeStyle = "rgba(255, 255, 255, 0.05)";
                            ctx.lineWidth = 1;
                            for (var gl = 0.25; gl < 1.0; gl += 0.25) {
                                var gy = fy(gl);
                                ctx.beginPath();
                                ctx.moveTo(0, gy);
                                ctx.lineTo(width, gy);
                                ctx.stroke();
                            }

                            // Fill under curve
                            ctx.beginPath();
                            ctx.moveTo(0, height);
                            for (var i = 0; i < n; i++) ctx.lineTo(i * dx, fy(arr[i]));
                            ctx.lineTo(width, height);
                            ctx.closePath();
                            var grad = ctx.createLinearGradient(0, 0, 0, height);
                            grad.addColorStop(0, "rgba(255, 255, 255, 0.20)");
                            grad.addColorStop(1, "rgba(255, 255, 255, 0.01)");
                            ctx.fillStyle = grad;
                            ctx.fill();

                            // Stroke line
                            ctx.beginPath();
                            for (i = 0; i < n; i++) {
                                var yy = fy(arr[i]);
                                if (i === 0) ctx.moveTo(0, yy);
                                else ctx.lineTo(i * dx, yy);
                            }
                            ctx.lineWidth = 1.75;
                            ctx.strokeStyle = "rgba(255, 255, 255, 0.95)";
                            ctx.stroke();
                        }
                        Component.onCompleted: requestPaint()
                    }

                    // ── Per-Core Logical Matrix ──
                    Item {
                        width: parent.width
                        height: 80

                        Column {
                            anchors.fill: parent
                            spacing: 6

                            Text {
                                text: "CORE DISTRIBUTION MATRIX"
                                color: "#6b7280"
                                font.family: tab.fontMono
                                font.pixelSize: 9
                                font.letterSpacing: 1
                            }

                            Flow {
                                width: parent.width
                                spacing: 4
                                Repeater {
                                    model: tab.stats && tab.stats.cpu && tab.stats.cpu.cores ? tab.stats.cpu.cores : []
                                    delegate: Rectangle {
                                        required property real modelData
                                        required property int index
                                        width: Math.max(22, (parent.width - 36) / 8)
                                        height: 32
                                        radius: 4
                                        color: "#141722"
                                        border.color: "#222738"
                                        border.width: 1

                                        // Vertical load fill
                                        Rectangle {
                                            anchors.bottom: parent.bottom
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            height: Math.max(2, parent.height * Math.min(1.0, modelData / 100.0))
                                            color: modelData > 85 ? "#ffffff" : "#c5cad6"
                                            opacity: 0.85
                                            radius: 3
                                        }

                                        Text {
                                            anchors.centerIn: parent
                                            text: String(index + 1)
                                            color: modelData > 55 ? "#000000" : "#9ca3af"
                                            font.family: tab.fontMono
                                            font.pixelSize: 9
                                            font.weight: Font.Bold
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ════════════════════════════════════════════════════════════════
            // ── Card 2: Memory (RAM) & Swap Architecture ────────────────────
            // ════════════════════════════════════════════════════════════════
            Rectangle {
                width: (grid.width - (grid.columns - 1) * grid.spacing) / grid.columns
                height: 310
                radius: 8
                color: "#10131c"
                border.color: "#1e2332"
                border.width: 1

                Column {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 12

                    // Header row
                    Item {
                        width: parent.width
                        height: 20
                        Row {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 8
                            Text {
                                text: "MEMORY (RAM) & SWAP"
                                color: "#9ca3af"
                                font.family: tab.fontMono
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                                font.letterSpacing: 1
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                        Text {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: tab.stats && tab.stats.memory ? app.fmtBytes(tab.stats.memory.totalBytes) + " TOTAL" : ""
                            color: "#6b7280"
                            font.family: tab.fontMono
                            font.pixelSize: 10
                        }
                    }

                    // Numeric Summary Row
                    Row {
                        width: parent.width
                        spacing: 16
                        Text {
                            text: Math.round(tab.memPct) + "%"
                            color: "#ffffff"
                            font.family: tab.fontUi
                            font.pixelSize: 34
                            font.weight: Font.Bold
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2
                            Text {
                                text: (tab.stats && tab.stats.memory ? app.fmtBytes(tab.stats.memory.usedBytes) + " in active use" : "")
                                color: "#ffffff"
                                font.family: tab.fontMono
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                            }
                            Text {
                                text: "Available for allocation: " + (tab.stats && tab.stats.memory ? app.fmtBytes(tab.stats.memory.availableBytes) : "")
                                color: "#9ca3af"
                                font.family: tab.fontUi
                                font.pixelSize: 10
                            }
                        }
                    }

                    // Proportional Segmented Memory Bar
                    Column {
                        width: parent.width
                        spacing: 6

                        Item {
                            width: parent.width
                            height: 14
                            Text { anchors.left: parent.left; text: "DISTRIBUTION"; color: "#6b7280"; font.family: tab.fontMono; font.pixelSize: 9; font.letterSpacing: 1 }
                            Text {
                                anchors.right: parent.right
                                text: (tab.stats && tab.stats.memory && tab.stats.memory.cachedBytes ? app.fmtBytes(tab.stats.memory.cachedBytes) + " cached" : "")
                                color: "#9ca3af"
                                font.family: tab.fontMono
                                font.pixelSize: 9
                            }
                        }

                        Rectangle {
                            width: parent.width
                            height: 10
                            radius: 5
                            color: "#181b26"
                            clip: true

                            // Active Used
                            Rectangle {
                                anchors.left: parent.left
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                width: parent.width * Math.min(1.0, Math.max(0, tab.memPct / 100.0))
                                color: "#ffffff"
                            }
                            // Cached overlay
                            Rectangle {
                                anchors.left: parent.left
                                anchors.leftMargin: parent.width * Math.min(1.0, Math.max(0, tab.memPct / 100.0))
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                width: parent.width * Math.min(1.0, (tab.stats && tab.stats.memory && tab.stats.memory.totalBytes > 0 ? (tab.stats.memory.cachedBytes / tab.stats.memory.totalBytes) : 0))
                                color: "#6b7280"
                            }
                        }

                        // Legend labels
                        Row {
                            spacing: 16
                            anchors.right: parent.right
                            Row {
                                spacing: 5
                                Rectangle { width: 8; height: 8; radius: 2; color: "#ffffff"; anchors.verticalCenter: parent.verticalCenter }
                                Text { text: "Active"; color: "#9ca3af"; font.family: tab.fontMono; font.pixelSize: 9; anchors.verticalCenter: parent.verticalCenter }
                            }
                            Row {
                                spacing: 5
                                Rectangle { width: 8; height: 8; radius: 2; color: "#6b7280"; anchors.verticalCenter: parent.verticalCenter }
                                Text { text: "Cached"; color: "#9ca3af"; font.family: tab.fontMono; font.pixelSize: 9; anchors.verticalCenter: parent.verticalCenter }
                            }
                            Row {
                                spacing: 5
                                Rectangle { width: 8; height: 8; radius: 2; color: "#181b26"; border.color: "#283044"; border.width: 1; anchors.verticalCenter: parent.verticalCenter }
                                Text { text: "Free"; color: "#9ca3af"; font.family: tab.fontMono; font.pixelSize: 9; anchors.verticalCenter: parent.verticalCenter }
                            }
                        }
                    }

                    // 4-Card Memory Breakdown Grid
                    Grid {
                        width: parent.width
                        columns: 2
                        spacing: 8

                        Rectangle {
                            width: (parent.width - 8) / 2
                            height: 52
                            radius: 6
                            color: "#141722"
                            border.color: "#222738"
                            border.width: 1
                            Column {
                                anchors.centerIn: parent
                                spacing: 2
                                Text { text: "Active Working Set"; color: "#6b7280"; font.pixelSize: 9; font.family: tab.fontUi }
                                Text { text: tab.stats && tab.stats.memory ? app.fmtBytes(tab.stats.memory.usedBytes) : "0 B"; color: "#ffffff"; font.pixelSize: 13; font.weight: Font.DemiBold; font.family: tab.fontMono }
                            }
                        }
                        Rectangle {
                            width: (parent.width - 8) / 2
                            height: 52
                            radius: 6
                            color: "#141722"
                            border.color: "#222738"
                            border.width: 1
                            Column {
                                anchors.centerIn: parent
                                spacing: 2
                                Text { text: "Available Reserve"; color: "#6b7280"; font.pixelSize: 9; font.family: tab.fontUi }
                                Text { text: tab.stats && tab.stats.memory ? app.fmtBytes(tab.stats.memory.availableBytes) : "0 B"; color: "#ffffff"; font.pixelSize: 13; font.weight: Font.DemiBold; font.family: tab.fontMono }
                            }
                        }
                        Rectangle {
                            width: (parent.width - 8) / 2
                            height: 52
                            radius: 6
                            color: "#141722"
                            border.color: "#222738"
                            border.width: 1
                            Column {
                                anchors.centerIn: parent
                                spacing: 2
                                Text { text: "Page Cache & Buffers"; color: "#6b7280"; font.pixelSize: 9; font.family: tab.fontUi }
                                Text { text: tab.stats && tab.stats.memory ? app.fmtBytes(tab.stats.memory.cachedBytes) : "0 B"; color: "#ffffff"; font.pixelSize: 13; font.weight: Font.DemiBold; font.family: tab.fontMono }
                            }
                        }
                        Rectangle {
                            width: (parent.width - 8) / 2
                            height: 52
                            radius: 6
                            color: "#141722"
                            border.color: "#222738"
                            border.width: 1
                            Column {
                                anchors.centerIn: parent
                                spacing: 2
                                Text { text: "Virtual Swap Partition"; color: "#6b7280"; font.pixelSize: 9; font.family: tab.fontUi }
                                Text {
                                    text: tab.stats && tab.stats.swap && tab.stats.swap.totalBytes > 0 ? app.fmtBytes(tab.stats.swap.usedBytes) + " / " + app.fmtBytes(tab.stats.swap.totalBytes) : "ZRAM / Inactive"
                                    color: "#ffffff"
                                    font.pixelSize: 13
                                    font.weight: Font.DemiBold
                                    font.family: tab.fontMono
                                }
                            }
                        }
                    }
                }
            }

            // ════════════════════════════════════════════════════════════════
            // ── Card 3: Network Throughput & Dual-Trace Waveform ────────────
            // ════════════════════════════════════════════════════════════════
            Rectangle {
                width: (grid.width - (grid.columns - 1) * grid.spacing) / grid.columns
                height: 250
                radius: 8
                color: "#10131c"
                border.color: "#1e2332"
                border.width: 1

                Column {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 10

                    // Header row
                    Item {
                        width: parent.width
                        height: 20
                        Row {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 8
                            Text {
                                text: "NETWORK THROUGHPUT"
                                color: "#9ca3af"
                                font.family: tab.fontMono
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                                font.letterSpacing: 1
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                        Text {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: (tab.stats && tab.stats.network && tab.stats.network.interfaces && tab.stats.network.interfaces.length > 0) ? tab.stats.network.interfaces[0].name.toUpperCase() : "ETHERNET"
                            color: "#6b7280"
                            font.family: tab.fontMono
                            font.pixelSize: 10
                        }
                    }

                    // ── Dual-Trace Rolling Canvas Graph ──
                    Canvas {
                        id: netCanvas
                        width: parent.width
                        height: 64
                        property var rxPts: app ? app.netRxHistory : []
                        property var txPts: app ? app.netTxHistory : []
                        onRxPtsChanged: requestPaint()
                        onTxPtsChanged: requestPaint()
                        onPaint: {
                            var ctx = getContext("2d");
                            ctx.reset();
                            var rx = rxPts || [];
                            var tx = txPts || [];
                            var n = Math.max(rx.length, tx.length);
                            if (n < 2) return;

                            var peak = 1024;
                            for (var i = 0; i < rx.length; i++) if (rx[i] > peak) peak = rx[i];
                            for (var j = 0; j < tx.length; j++) if (tx[j] > peak) peak = tx[j];

                            var dx = width / (n - 1);
                            function fy(v) { return height - Math.max(0, Math.min(1, v / peak)) * (height - 6) - 3; }

                            // Center divider line
                            ctx.strokeStyle = "rgba(255, 255, 255, 0.05)";
                            ctx.lineWidth = 1;
                            ctx.beginPath();
                            ctx.moveTo(0, height / 2);
                            ctx.lineTo(width, height / 2);
                            ctx.stroke();

                            // Draw RX (Download - solid bright)
                            if (rx.length > 1) {
                                ctx.beginPath();
                                for (i = 0; i < rx.length; i++) {
                                    var yrx = fy(rx[i]);
                                    if (i === 0) ctx.moveTo(0, yrx);
                                    else ctx.lineTo(i * dx, yrx);
                                }
                                ctx.lineWidth = 1.8;
                                ctx.strokeStyle = "#ffffff";
                                ctx.stroke();
                            }

                            // Draw TX (Upload - dim stroke)
                            if (tx.length > 1) {
                                ctx.beginPath();
                                for (i = 0; i < tx.length; i++) {
                                    var ytx = fy(tx[i]);
                                    if (i === 0) ctx.moveTo(0, ytx);
                                    else ctx.lineTo(i * dx, ytx);
                                }
                                ctx.lineWidth = 1.2;
                                ctx.strokeStyle = "rgba(160, 166, 181, 0.65)";
                                ctx.stroke();
                            }
                        }
                        Component.onCompleted: requestPaint()
                    }

                    // Download / Upload Rate Plates
                    Row {
                        width: parent.width
                        spacing: 12

                        Rectangle {
                            width: (parent.width - 12) / 2
                            height: 72
                            radius: 6
                            color: "#141722"
                            border.color: "#222738"
                            border.width: 1
                            Column {
                                anchors.centerIn: parent
                                spacing: 3
                                Row {
                                    spacing: 5
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    Text { text: "↓"; color: "#ffffff"; font.pixelSize: 11; font.weight: Font.Bold }
                                    Text { text: "DOWNLOAD"; color: "#9ca3af"; font.pixelSize: 10; font.family: tab.fontMono; font.letterSpacing: 1 }
                                }
                                Text {
                                    text: tab.stats && tab.stats.network ? app.fmtRate(tab.stats.network.rxRateSec) : "0 B/s"
                                    color: "#ffffff"
                                    font.pixelSize: 16
                                    font.weight: Font.Bold
                                    font.family: tab.fontMono
                                    anchors.horizontalCenter: parent.horizontalCenter
                                }
                                Text {
                                    text: "Total: " + (tab.stats && tab.stats.network ? app.fmtBytes(tab.stats.network.rxBytes) : "0 B")
                                    color: "#6b7280"
                                    font.pixelSize: 9
                                    font.family: tab.fontMono
                                    anchors.horizontalCenter: parent.horizontalCenter
                                }
                            }
                        }

                        Rectangle {
                            width: (parent.width - 12) / 2
                            height: 72
                            radius: 6
                            color: "#141722"
                            border.color: "#222738"
                            border.width: 1
                            Column {
                                anchors.centerIn: parent
                                spacing: 3
                                Row {
                                    spacing: 5
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    Text { text: "↑"; color: "#9ca3af"; font.pixelSize: 11; font.weight: Font.Bold }
                                    Text { text: "UPLOAD"; color: "#9ca3af"; font.pixelSize: 10; font.family: tab.fontMono; font.letterSpacing: 1 }
                                }
                                Text {
                                    text: tab.stats && tab.stats.network ? app.fmtRate(tab.stats.network.txRateSec) : "0 B/s"
                                    color: "#ffffff"
                                    font.pixelSize: 16
                                    font.weight: Font.Bold
                                    font.family: tab.fontMono
                                    anchors.horizontalCenter: parent.horizontalCenter
                                }
                                Text {
                                    text: "Total: " + (tab.stats && tab.stats.network ? app.fmtBytes(tab.stats.network.txBytes) : "0 B")
                                    color: "#6b7280"
                                    font.pixelSize: 9
                                    font.family: tab.fontMono
                                    anchors.horizontalCenter: parent.horizontalCenter
                                }
                            }
                        }
                    }

                    Text {
                        text: "Interfaces: " + (tab.stats && tab.stats.network && tab.stats.network.interfaces ? tab.stats.network.interfaces.map(function(i){ return i.name; }).join(", ") : "None")
                        color: "#6b7280"
                        font.family: tab.fontMono
                        font.pixelSize: 9
                    }
                }
            }

            // ════════════════════════════════════════════════════════════════
            // ── Card 4: Storage & Disk Velocity ─────────────────────────────
            // ════════════════════════════════════════════════════════════════
            Rectangle {
                width: (grid.width - (grid.columns - 1) * grid.spacing) / grid.columns
                height: 250
                radius: 8
                color: "#10131c"
                border.color: "#1e2332"
                border.width: 1

                Column {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 12

                    // Header row
                    Item {
                        width: parent.width
                        height: 20
                        Row {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 8
                            Text {
                                text: "STORAGE & DISK VELOCITY"
                                color: "#9ca3af"
                                font.family: tab.fontMono
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                                font.letterSpacing: 1
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                        Text {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: tab.stats && tab.stats.diskIO && (tab.stats.diskIO.readIOPS + tab.stats.diskIO.writeIOPS > 0) ? Math.round(tab.stats.diskIO.readIOPS + tab.stats.diskIO.writeIOPS) + " IOPS" : "NVME/SATA"
                            color: "#6b7280"
                            font.family: tab.fontMono
                            font.pixelSize: 10
                        }
                    }

                    // Read & Write Velocity Boxes
                    Row {
                        width: parent.width
                        spacing: 12
                        Rectangle {
                            width: (parent.width - 12) / 2
                            height: 60
                            radius: 6
                            color: "#141722"
                            border.color: "#222738"
                            border.width: 1
                            Column {
                                anchors.centerIn: parent
                                spacing: 2
                                Text { text: "DISK READ VELOCITY"; color: "#6b7280"; font.pixelSize: 9; font.family: tab.fontMono; font.letterSpacing: 1 }
                                Text { text: tab.stats && tab.stats.diskIO ? app.fmtRate(tab.stats.diskIO.readBytesSec) : "0 B/s"; color: "#ffffff"; font.pixelSize: 14; font.weight: Font.Bold; font.family: tab.fontMono }
                            }
                        }

                        Rectangle {
                            width: (parent.width - 12) / 2
                            height: 60
                            radius: 6
                            color: "#141722"
                            border.color: "#222738"
                            border.width: 1
                            Column {
                                anchors.centerIn: parent
                                spacing: 2
                                Text { text: "DISK WRITE VELOCITY"; color: "#6b7280"; font.pixelSize: 9; font.family: tab.fontMono; font.letterSpacing: 1 }
                                Text { text: tab.stats && tab.stats.diskIO ? app.fmtRate(tab.stats.diskIO.writeBytesSec) : "0 B/s"; color: "#ffffff"; font.pixelSize: 14; font.weight: Font.Bold; font.family: tab.fontMono }
                            }
                        }
                    }

                    // Primary Root Storage Bar
                    Item {
                        width: parent.width
                        height: 56
                        property var rootDisk: {
                            if (tab.stats && tab.stats.disks) {
                                for (var i = 0; i < tab.stats.disks.length; i++) {
                                    if (tab.stats.disks[i].mountPoint === "/") return tab.stats.disks[i];
                                }
                                if (tab.stats.disks.length > 0) return tab.stats.disks[0];
                            }
                            return null;
                        }

                        Column {
                            anchors.fill: parent
                            spacing: 6
                            visible: parent.rootDisk !== null

                            Item {
                                width: parent.width
                                height: 16
                                Text {
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "ROOT (/) · " + (parent.parent.rootDisk ? parent.parent.rootDisk.fsType.toUpperCase() : "BTRFS") + " · " + (parent.parent.rootDisk ? app.fmtBytes(parent.parent.rootDisk.usedBytes) + " used of " + app.fmtBytes(parent.parent.rootDisk.totalBytes) : "")
                                    color: "#9ca3af"
                                    font.family: tab.fontMono
                                    font.pixelSize: 10
                                }
                                Text {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: parent.parent.rootDisk ? Math.round(parent.parent.rootDisk.usedPercent) + "%" : ""
                                    color: "#ffffff"
                                    font.family: tab.fontMono
                                    font.pixelSize: 11
                                    font.weight: Font.Bold
                                }
                            }

                            Rectangle {
                                width: parent.width
                                height: 8
                                radius: 4
                                color: "#181b26"
                                Rectangle {
                                    width: parent.width * Math.min(1.0, (parent.parent.parent.rootDisk ? parent.parent.parent.rootDisk.usedPercent : 0) / 100.0)
                                    height: parent.height
                                    radius: 4
                                    color: "#ffffff"
                                }
                            }

                            Text {
                                text: "Free Space: " + (parent.parent.rootDisk ? app.fmtBytes(parent.parent.rootDisk.freeBytes) : "")
                                color: "#6b7280"
                                font.family: tab.fontMono
                                font.pixelSize: 9
                            }
                        }
                    }
                }
            }

            // ════════════════════════════════════════════════════════════════
            // ── Dynamic Card 5: GPU Accelerator (if present) ────────────────
            // ════════════════════════════════════════════════════════════════
            Repeater {
                model: tab.stats && tab.stats.gpus ? tab.stats.gpus : []
                delegate: Rectangle {
                    required property var modelData
                    width: (grid.width - (grid.columns - 1) * grid.spacing) / grid.columns
                    height: 220
                    radius: 8
                    color: "#10131c"
                    border.color: "#1e2332"
                    border.width: 1

                    Column {
                        anchors.fill: parent
                        anchors.margins: 16
                        spacing: 12

                        Item {
                            width: parent.width
                            height: 20
                            Row {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 8
                                Text {
                                    text: modelData.isVirtual ? "VIRTUAL GRAPHICS ADAPTER" : "GPU ACCELERATOR"
                                    color: "#9ca3af"
                                    font.family: tab.fontMono
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold
                                    font.letterSpacing: 1
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }
                            Text {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.tempC > 0 ? Math.round(modelData.tempC) + " °C" : modelData.vendor.toUpperCase()
                                color: "#e5e7eb"
                                font.family: tab.fontMono
                                font.pixelSize: 11
                            }
                        }

                        Text {
                            text: modelData.name
                            color: "#ffffff"
                            font.family: tab.fontUi
                            font.pixelSize: 14
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                            width: parent.width
                        }

                        Column {
                            width: parent.width
                            spacing: 10

                            Row {
                                spacing: 14
                                Text {
                                    text: Math.round(modelData.utilizationPct) + "%"
                                    color: "#ffffff"
                                    font.family: tab.fontUi
                                    font.pixelSize: 32
                                    font.weight: Font.Bold
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                Column {
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 2
                                    Text {
                                        text: modelData.memoryTotalMB > 0 ? "VRAM: " + modelData.memoryUsedMB + " MB / " + (modelData.memoryTotalMB >= 1024 ? (modelData.memoryTotalMB / 1024).toFixed(1) + " GB" : modelData.memoryTotalMB + " MB") : "Shared System Memory"
                                        color: "#e5e7eb"
                                        font.family: tab.fontMono
                                        font.pixelSize: 11
                                    }
                                    Text {
                                        text: "Architecture: " + modelData.vendor.toUpperCase()
                                        color: "#6b7280"
                                        font.family: tab.fontMono
                                        font.pixelSize: 10
                                    }
                                }
                            }

                            // Utilization Bar
                            Rectangle {
                                width: parent.width
                                height: 6
                                radius: 3
                                color: "#181b26"
                                Rectangle {
                                    width: parent.width * Math.min(1.0, Math.max(0.01, modelData.utilizationPct / 100.0))
                                    height: parent.height
                                    radius: 3
                                    color: "#ffffff"
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
