import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland
import "../../theme"

RowLayout {
    id: root
    spacing: 6
    property int focusedId: Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : 1
    property int maxOccupied: {
        let m = 0
        if (Hyprland.workspaces) {
            for (let i=0;i<Hyprland.workspaces.values.length;i++) {
                const w = Hyprland.workspaces.values[i]
                if (w.id > m) m = w.id
            }
        }
        return m
    }
    property int count: {
        let c = Math.max(3, maxOccupied, focusedId)
        let occupied = Hyprland.workspaces ? Hyprland.workspaces.values.length : 0
        if (occupied >= 1 && occupied === c && c < 10) c = c+1
        if (occupied === 0) c = 3
        return Math.min(c, 10)
    }

    Repeater {
        model: root.count
        delegate: Item {
            required property int index
            property int wsId: index + 1
            property bool isActive: wsId === root.focusedId
            width: 20; height: 20
            Text {
                id: dot
                anchors.centerIn: parent
                text: Icons.workspaceDot
                font.family: Theme.fontFamily
                font.pixelSize: isActive ? 10 : 8
                color: isActive ? Theme.fg : Theme.fgDim
                opacity: isActive ? 1.0 : 0.85
                Behavior on color { ColorAnimation { duration: Theme.durationFast } }
            }
            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: Hyprland.dispatch("workspace " + wsId)
                onEntered: dot.color = Theme.fgBright
                onExited: dot.color = isActive ? Theme.fg : Theme.fgDim
            }
        }
    }
}
