import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../../theme"
import "../../services"

WlrLayershell {
    id: root
    property bool isOpen: false
    function open() { isOpen = true }
    function close() { isOpen = false }
    function toggle() { if (isOpen) close(); else open() }

    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    visible: isOpen
    keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore
    Rectangle { anchors.fill: parent; color: Theme.overlay; MouseArea { anchors.fill: parent; onClicked: root.close() } }

    // Shared state colour — same thresholds as the bar BatteryIcon:
    // <=20 critical, <=30 warning, charging success, plugged neutral.
    readonly property color stateColor: {
        if (!BatteryService.available) return Theme.fgDim
        if (BatteryService.plugged) return Theme.fg
        const cap = BatteryService.capacity
        if (cap >= 0 && cap <= 20) return Theme.critical
        if (cap > 20 && cap <= 30) return Theme.warning
        if (BatteryService.charging) return Theme.success
        return Theme.fg
    }
    readonly property string stateGlyph: {
        if (!BatteryService.available) return Icons.batteryPlugged
        if (BatteryService.charging) return Icons.batteryCharging
        if (BatteryService.plugged) return Icons.batteryPlugged
        const cap = BatteryService.capacity
        if (cap < 0) return Icons.batteryPlugged
        const idx = cap <= 20 ? 0 : cap <= 30 ? 1 : cap <= 50 ? 2 : cap <= 70 ? 3 : cap <= 90 ? 4 : 5
        return Icons.batteryLevels.substring(idx * 2, idx * 2 + 2)
    }
    readonly property string stateLabel: {
        if (!BatteryService.available) return "No battery"
        if (BatteryService.charging) return "Charging"
        if (BatteryService.plugged) return "Plugged in"
        if (BatteryService.discharging) return "On battery"
        return "Unknown"
    }

    function formatMinutes(m) {
        if (m === undefined || m === null || m < 0) return "—"
        if (m < 1) return "<1m"
        if (m < 60) return m + "m"
        const h = Math.floor(m / 60)
        const mm = m % 60
        return mm === 0 ? h + "h" : h + "h " + mm + "m"
    }
    function formatWh(uwh) {
        if (uwh === undefined || uwh === null || uwh < 0) return "—"
        return (uwh / 1000000).toFixed(1) + " Wh"
    }
    function formatW(uw) {
        if (uw === undefined || uw === null || uw < 0) return "—"
        return (uw / 1000000).toFixed(1) + " W"
    }

    Rectangle {
        id: card
        width: 620
        height: Math.min(560, mainCol.implicitHeight + Theme.padL * 2)
        anchors.centerIn: parent
        radius: Theme.roundingLauncher
        color: Theme.bgLauncher
        border.width: 1
        border.color: Theme.borderActive
        clip: true

        ColumnLayout {
            id: mainCol
            anchors.fill: parent
            anchors.margins: Theme.padL
            spacing: Theme.gapM
            focus: true

            Text { text: "Power"; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; color: Theme.fgMuted; font.capitalization: Font.AllUppercase; font.letterSpacing: 1.2 }
            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border }

            // Hero — glyph + state + percent, critical wash per STYLE §6.
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 84
                radius: Theme.roundingItem
                color: (BatteryService.available && !BatteryService.plugged && BatteryService.capacity >= 0 && BatteryService.capacity <= 20) ? Theme.bgCritical : "transparent"
                border.width: 1
                border.color: Theme.border
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.padL
                    anchors.rightMargin: Theme.padL
                    spacing: Theme.gapL
                    Text {
                        text: root.stateGlyph
                        font.family: Theme.fontFamily
                        font.pixelSize: 40
                        color: root.stateColor
                        Layout.alignment: Qt.AlignVCenter
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        Text {
                            text: root.stateLabel
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeLauncher
                            font.weight: Theme.fontWeightMedium
                            color: Theme.fg
                        }
                        Text {
                            visible: BatteryService.available && BatteryService.discharging && BatteryService.timeLeftMinutes >= 0
                            text: formatMinutes(BatteryService.timeLeftMinutes) + " remaining"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSmall
                            color: root.stateColor
                        }
                        Text {
                            visible: BatteryService.available && BatteryService.charging && BatteryService.timeLeftMinutes >= 0
                            text: "Full in " + formatMinutes(BatteryService.timeLeftMinutes)
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.fgMuted
                        }
                        Text {
                            visible: !BatteryService.available
                            text: "No battery detected"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.fgDim
                        }
                    }
                    Text {
                        visible: BatteryService.available && BatteryService.capacity >= 0 && !BatteryService.plugged
                        text: BatteryService.capacity + "%"
                        font.family: Theme.fontFamily
                        font.pixelSize: 28
                        font.weight: Theme.fontWeightMedium
                        color: root.stateColor
                        Layout.alignment: Qt.AlignVCenter
                    }
                }
            }

            // Charge bar — full width, colour follows state.
            Rectangle {
                visible: BatteryService.available && BatteryService.capacity >= 0 && !BatteryService.plugged
                Layout.fillWidth: true
                Layout.preferredHeight: 6
                radius: 3
                color: Theme.border
                clip: true
                Rectangle {
                    width: parent.width * Math.max(0, Math.min(100, BatteryService.capacity)) / 100
                    height: parent.height
                    radius: 3
                    color: root.stateColor
                    Behavior on width { NumberAnimation { duration: Theme.durationNormal; easing.type: Easing.OutCubic } }
                    Behavior on color { ColorAnimation { duration: Theme.durationFast } }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border }

            // Detail rows — label left, value right-aligned.
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.gapS
                RowLayout {
                    Layout.fillWidth: true
                    Text { text: "Charge"; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeLauncher; color: Theme.fgMuted; Layout.fillWidth: true }
                    Text {
                        text: !BatteryService.available ? "—" : BatteryService.plugged ? "Full / on AC" : BatteryService.capacity >= 0 ? BatteryService.capacity + "%" : "—"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeLauncher
                        font.weight: Theme.fontWeightMedium
                        color: root.stateColor
                    }
                }
                RowLayout {
                    visible: BatteryService.available && BatteryService.discharging
                    Layout.fillWidth: true
                    Text { text: "Time left unplugged"; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeLauncher; color: Theme.fgMuted; Layout.fillWidth: true }
                    Text {
                        text: formatMinutes(BatteryService.timeLeftMinutes)
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeLauncher
                        font.weight: Theme.fontWeightMedium
                        color: root.stateColor
                    }
                }
                RowLayout {
                    visible: BatteryService.available && (BatteryService.discharging || BatteryService.charging) && BatteryService.powerNow >= 0
                    Layout.fillWidth: true
                    Text { text: BatteryService.charging ? "Charge rate" : "Power draw"; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeLauncher; color: Theme.fgMuted; Layout.fillWidth: true }
                    Text {
                        text: formatW(BatteryService.powerNow)
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeLauncher
                        color: Theme.fg
                    }
                }
                RowLayout {
                    visible: BatteryService.available && BatteryService.energyNow >= 0 && BatteryService.energyFull > 0
                    Layout.fillWidth: true
                    Text { text: "Energy"; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeLauncher; color: Theme.fgMuted; Layout.fillWidth: true }
                    Text {
                        text: formatWh(BatteryService.energyNow) + " / " + formatWh(BatteryService.energyFull)
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeLauncher
                        color: Theme.fg
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    Text { text: "Status"; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeLauncher; color: Theme.fgMuted; Layout.fillWidth: true }
                    Text {
                        text: root.stateLabel
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeLauncher
                        color: Theme.fg
                    }
                }
            }

            Text { text: "r refresh · Esc close"; font.family: Theme.fontFamily; font.pixelSize: 10; color: Theme.fgDim; Layout.alignment: Qt.AlignHCenter }

            Keys.onPressed: (e) => {
                if (e.key === Qt.Key_Escape) { root.close(); e.accepted = true }
                else if (e.text === "r" || e.text === "R") { BatteryService.refresh(); e.accepted = true }
            }
            Component.onCompleted: forceActiveFocus()
        }
        Keys.onEscapePressed: root.close()
        onVisibleChanged: if (visible) mainCol.forceActiveFocus()
    }

    onIsOpenChanged: {
        if (isOpen) { BatteryService.refresh(); Qt.callLater(() => mainCol.forceActiveFocus()) }
    }
}
