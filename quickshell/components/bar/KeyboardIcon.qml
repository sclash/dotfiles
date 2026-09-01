import QtQuick
import "../../theme"
import "../../services"

Text {
    id: root
    signal clicked()
    font.family: Theme.fontFamily
    font.pixelSize: Theme.fontSizeBar
    text: {
        const flag = HyprService.layoutName === "IT" ? " \uD83C\uDDEE\uD83C\uDDF9" : " \uD83C\uDDFA\uD83C\uDDF8"
        const code = HyprService.layoutName
        return "|| " + Icons.keyboard + " " + code + flag + " ||"
    }
    color: HyprService.available ? Theme.fg : Theme.fgDim
    Behavior on color { ColorAnimation { duration: Theme.durationNormal } }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            // cycle layout via hyprctl
            HyprService.cycleLayout()
            root.clicked()
        }
    }
}
