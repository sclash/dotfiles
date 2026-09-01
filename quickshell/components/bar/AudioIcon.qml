import QtQuick
import "../../theme"
import "../../services"
import Quickshell.Services.Pipewire

Text {
    id: root
    signal clicked()
    font.family: Theme.fontFamily
    font.pixelSize: Theme.fontSizeBar
    text: {
        if (!AudioService.available || !AudioService.hasSink) return Icons.audioMuted
        if (AudioService.muted) return Icons.audioMuted
        return Icons.audioVolume + " " + AudioService.volume + "% "
    }
    color: {
        if (!AudioService.available || !AudioService.hasSink) return Theme.critical
        if (AudioService.muted) return Theme.fgDim
        return Theme.fg
    }
    Behavior on color { ColorAnimation { duration: Theme.durationNormal } }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        hoverEnabled: true
        onClicked: root.clicked()
        onWheel: (wheel) => {
            if (wheel.angleDelta.y > 0) AudioService.adjustVolume(0.05)
            else if (wheel.angleDelta.y < 0) AudioService.adjustVolume(-0.05)
        }
    }
}
