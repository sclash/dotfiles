import QtQuick
import "../../theme"
import "../../services"

Text {
    id: root
    signal clicked()
    font.family: Theme.fontFamily
    font.pixelSize: Theme.fontSizeBar
    text: {
        if (!NetworkService.available) return Icons.wifiDisconnected
        if (!NetworkService.connected) return Icons.wifiDisconnected
        if (NetworkService.type === "ethernet") return Icons.wifiEthernet
        return Icons.wifiConnected
    }
    color: {
        if (!NetworkService.available || !NetworkService.connected) return Theme.fgDim
        if (NetworkService.signalStrength >=0 && NetworkService.signalStrength < 30) return Theme.warning
        return Theme.fg
    }
    Behavior on color { ColorAnimation { duration: Theme.durationNormal } }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        hoverEnabled: true
        onClicked: root.clicked()
    }
}
