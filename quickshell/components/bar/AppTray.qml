import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import "../../theme"

RowLayout {
    id: root
    spacing: 12
    // SystemTray.items is an ObjectModel — use count or values length safely
    visible: SystemTray.items.values ? SystemTray.items.values.length > 0 : false

    // Expose the bar window for menu display (set from Bar.qml if available)
    property var barWindow: null

    Repeater {
        model: SystemTray.items
        delegate: Item {
            required property SystemTrayItem modelData
            required property int index
            // Spec: icon-size 12, spacing 12 — Waybar parity
            width: 12; height: 12
            visible: index < 6 || SystemTray.items.values.length <= 6
            IconImage {
                id: trayIcon
                anchors.centerIn: parent
                width: 12; height: 12
                source: Quickshell.iconPath(modelData.icon, "image-missing")
                // Smooth fallback — if image-missing, show warning glyph
                asynchronous: true
            }
            Text {
                anchors.centerIn: parent
                visible: trayIcon.status === Image.Error || trayIcon.source.toString().indexOf("image-missing") !== -1
                text: Icons.warning
                font.family: Theme.fontFamily
                font.pixelSize: 10
                color: Theme.fgDim
            }
            ToolTip.visible: hoverMA.containsMouse && !!modelData.tooltipTitle
            ToolTip.text: (modelData.tooltipTitle || "") + (modelData.tooltipDescription ? "\n" + modelData.tooltipDescription : "")
            ToolTip.delay: 500
            MouseArea {
                id: hoverMA
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                onClicked: (mouse) => {
                    if (mouse.button === Qt.RightButton) {
                        if (modelData.hasMenu) {
                            // Try to display menu at cursor position
                            let win = root.barWindow
                            if (!win) win = root.QsWindow.window
                            if (win) modelData.display(win, mouse.x, mouse.y)
                            else modelData.secondaryActivate()
                        } else modelData.secondaryActivate()
                    } else if (mouse.button === Qt.MiddleButton) {
                        modelData.secondaryActivate()
                    } else modelData.activate()
                }
                onPressAndHold: {
                    if (modelData.hasMenu) {
                        let win = root.barWindow
                        if (!win) win = root.QsWindow.window
                        if (win) modelData.display(win, 0, 0)
                        else modelData.secondaryActivate()
                    } else modelData.secondaryActivate()
                }
            }
        }
    }
    // Overflow indicator — collapses to … when >6 items (spec)
    Text {
        visible: SystemTray.items.values ? SystemTray.items.values.length > 6 : false
        text: "…"
        font.family: Theme.fontFamily
        font.pixelSize: 12
        color: Theme.fgMuted
        Layout.alignment: Qt.AlignVCenter
    }
}
