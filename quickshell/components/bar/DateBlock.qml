import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../services"

RowLayout {
    id: root
    spacing: Theme.gapM
    property string formatted: Qt.formatDateTime(new Date(), Theme.dateFormat)
    signal toggleNotif()

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: root.formatted = Qt.formatDateTime(new Date(), Theme.dateFormat)
    }

    Rectangle {
        radius: Theme.roundingItem
        color: dateMA.containsMouse ? Theme.bgHover : "transparent"
        Layout.preferredWidth: dateText.implicitWidth + 16
        Layout.preferredHeight: 26
        Behavior on color { ColorAnimation { duration: Theme.durationFast } }

        Text {
            id: dateText
            anchors.centerIn: parent
            text: root.formatted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeBar
            font.weight: Theme.fontWeightMedium
            color: Theme.fg
        }
        MouseArea {
            id: dateMA
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.toggleNotif()
        }
    }

    Rectangle {
        width: 32; height: 32
        radius: 8
        color: bellMA.containsMouse ? Theme.bgHover : "transparent"
        Behavior on color { ColorAnimation { duration: Theme.durationFast } }

        Text {
            id: bell
            anchors.centerIn: parent
            text: Icons.notification
            font.family: Theme.fontFamily
            font.pixelSize: 16
            color: {
                if (!NotifService.available) return Theme.fg
                if (NotifService.dnd) return Theme.fgDim
                if (NotifService.hasUnread) return Theme.accent
                return Theme.fg
            }
        }
        Rectangle {
            visible: NotifService.hasUnread && !NotifService.dnd
            width: 8; height: 8; radius: 4
            color: Theme.accent
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.rightMargin: 4
            anchors.topMargin: 4
            border.width: 1
            border.color: Theme.bgBar
        }
        MouseArea {
            id: bellMA
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.toggleNotif()
        }
    }
}
