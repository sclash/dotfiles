import QtQuick
import "../../theme"
import "../../services"

Text {
    id: root
    signal clicked()
    font.family: Theme.fontFamily
    font.pixelSize: Theme.fontSizeBar
    text: {
        if (!BluetoothService.available || !BluetoothService.powered) return Icons.bluetoothOff
        if (BluetoothService.connectedCount > 0) return Icons.bluetoothOn + (BluetoothService.connectedCount > 1 ? " " + BluetoothService.connectedCount : "")
        return Icons.bluetoothOn
    }
    color: {
        if (!BluetoothService.available || !BluetoothService.powered) return Theme.fgDim
        if (BluetoothService.connectedCount > 0) return Theme.accent
        return Theme.fg
    }
    Behavior on color { ColorAnimation { duration: Theme.durationNormal } }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
