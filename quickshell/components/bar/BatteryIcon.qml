import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../services"

Rectangle {
    id: root
    visible: BatteryService.available
    height: Theme.barIconSlot
    Layout.preferredWidth: batRow.implicitWidth + 14
    radius: Theme.roundingItem
    color: batMA.containsMouse ? Theme.bgHover : "transparent"
    Behavior on color { ColorAnimation { duration: Theme.durationFast } }

    RowLayout {
        id: batRow
        anchors.centerIn: parent
        spacing: 4

        Text {
            text: {
                if (!BatteryService.available) return ""
                if (BatteryService.charging) return Icons.batteryCharging
                if (BatteryService.plugged) return Icons.batteryPlugged
                const cap = BatteryService.capacity
                if (cap < 0) return ""
                const idx = cap <= 20 ? 0 : cap <= 30 ? 1 : cap <= 50 ? 2 : cap <= 70 ? 3 : cap <= 90 ? 4 : 5
                return Icons.batteryLevels.substring(idx * 2, idx * 2 + 2)
            }
            font.family: Theme.fontFamily
            font.pixelSize: Theme.barIconSize
            color: {
                if (BatteryService.plugged) return Theme.fg
                const cap = BatteryService.capacity
                if (cap >= 0 && cap <= 20) return Theme.critical
                if (cap > 20 && cap <= 30) return Theme.warning
                if (BatteryService.charging) return Theme.success
                return Theme.fg
            }
        }

        Text {
            id: capText
            visible: BatteryService.capacity >= 0 && !BatteryService.plugged
            text: BatteryService.capacity + "%"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
            color: {
                const cap = BatteryService.capacity
                if (cap >= 0 && cap <= 20) return Theme.critical
                if (cap > 20 && cap <= 30) return Theme.warning
                if (BatteryService.charging) return Theme.success
                return Theme.fgMuted
            }
        }
    }

    MouseArea {
        id: batMA
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
    }
}