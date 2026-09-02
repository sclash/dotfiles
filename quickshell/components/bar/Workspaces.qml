pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import "../../theme"

RowLayout {
    id: root
    spacing: Theme.gapS
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

    // Windows on workspace <id>, straight from the Hyprland IPC toplevel model.
    // Event-driven (openwindow/closewindow/movewindowv2) — no polling.
    function toplevelsFor(id) {
        const list = []
        if (!Hyprland.toplevels) return list
        for (let i = 0; i < Hyprland.toplevels.values.length; i++) {
            const t = Hyprland.toplevels.values[i]
            if (t.workspace && t.workspace.id === id) list.push(t)
        }
        return list
    }

    Repeater {
        model: root.count
        delegate: RowLayout {
            id: wsGroup
            required property int index
            property int wsId: index + 1
            property bool isActive: wsId === root.focusedId
            property var apps: root.toplevelsFor(wsId)
            spacing: 2

            // Workspace dot — click switches workspace (unchanged)
            Item {
                implicitWidth: 20; implicitHeight: 20
                Text {
                    id: dot
                    anchors.centerIn: parent
                    text: Icons.workspaceDot
                    font.family: Theme.fontFamily
                    font.pixelSize: wsGroup.isActive ? 10 : 8
                    color: wsGroup.isActive ? Theme.fg : Theme.fgDim
                    opacity: wsGroup.isActive ? 1.0 : 0.85
                    Behavior on color { ColorAnimation { duration: Theme.durationFast } }
                }
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Hyprland.dispatch('hl.dsp.focus({ workspace = ' + wsGroup.wsId + ' })')
                    onEntered: dot.color = Theme.fgBright
                    onExited: dot.color = wsGroup.isActive ? Theme.fg : Theme.fgDim
                }
            }

            // Per-workspace app tray — up to wsAppIconMax micro icons
            Repeater {
                model: Math.min(wsGroup.apps.length, Theme.wsAppIconMax)
                delegate: Item {
                    id: iconSlot
                    required property int index
                    property var toplevel: wsGroup.apps[index]
                    property string appId: toplevel && toplevel.wayland ? (toplevel.wayland.appId || "") : ""
                    property string iconSource: appId !== "" ? Quickshell.iconPath(appId) : ""
                    implicitWidth: Theme.wsAppIcon; implicitHeight: Theme.wsAppIcon
                    Layout.alignment: Qt.AlignVCenter

                    Rectangle {
                        anchors.fill: parent
                        radius: Theme.roundingItem
                        color: slotMA.containsMouse ? Theme.bgHover : "transparent"
                        Behavior on color { ColorAnimation { duration: Theme.durationFast } }

                        Image {
                            id: appIcon
                            anchors.centerIn: parent
                            width: Theme.wsAppIconGlyph; height: Theme.wsAppIconGlyph
                            source: iconSlot.iconSource
                            smooth: true
                            asynchronous: true
                            sourceSize: Qt.size(Theme.wsAppIconGlyph, Theme.wsAppIconGlyph)
                            visible: source !== "" && status !== Image.Error
                            opacity: iconSlot.toplevel && iconSlot.toplevel.activated ? 1.0 : 0.55
                        }
                        Text {
                            anchors.centerIn: parent
                            visible: !appIcon.visible
                            text: Icons.window
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.wsAppIconGlyph - 1
                            color: iconSlot.toplevel && iconSlot.toplevel.activated ? Theme.fg : Theme.fgDim
                        }
                    }

                    BarToolTip {
                        id: slotTip
                        visible: slotMA.containsMouse && !!iconSlot.toplevel
                        text: iconSlot.toplevel && iconSlot.toplevel.title ? iconSlot.toplevel.title : ""
                        anchorItem: iconSlot
                    }

                    MouseArea {
                        id: slotMA
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (iconSlot.toplevel && iconSlot.toplevel.address)
                                Hyprland.dispatch('hl.dsp.focus({ window = "address:0x' + iconSlot.toplevel.address + '" })')
                        }
                    }
                }
            }

            // Overflow count when more than wsAppIconMax windows on this workspace
            Text {
                visible: wsGroup.apps.length > Theme.wsAppIconMax
                text: "+" + (wsGroup.apps.length - Theme.wsAppIconMax)
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.fgDim
                Layout.alignment: Qt.AlignVCenter
            }
        }
    }
}
