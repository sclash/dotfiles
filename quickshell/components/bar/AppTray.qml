import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Services.SystemTray
import "../../theme"

RowLayout {
    id: root
    spacing: 12
    visible: SystemTray.items.values.length > 0

    // Expose the bar window for menu display (set from Bar.qml if available)
    property var barWindow: null

    Repeater {
        model: SystemTray.items
        delegate: Item {
            required property var modelData
            required property int index
            // Spec: icon-size 12, spacing 12 — Waybar parity
            width: 12; height: 12
            visible: index < 6 || SystemTray.items.values.length <= 6

            Image {
                id: trayIcon
                anchors.fill: parent
                // systemTrayItem.icon is already a source string in 0.3.0 —
                // do not pass it through Quickshell.iconPath (that is for themed
                // icon *names*, and would garble already-resolved sources)
                source: modelData.icon
                smooth: true
                asynchronous: true
                sourceSize: Qt.size(12, 12)
            }
            Text {
                anchors.centerIn: parent
                visible: trayIcon.status === Image.Error
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
        visible: SystemTray.items.values.length > 6
        text: "…"
        font.family: Theme.fontFamily
        font.pixelSize: 12
        color: Theme.fgMuted
        Layout.alignment: Qt.AlignVCenter
    }
}