import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Services.SystemTray
import "../../theme"

RowLayout {
    id: root
    spacing: 4
    visible: SystemTray.items.values.length > 0

    // Expose the bar window for menu display (set from Bar.qml if available)
    property var barWindow: null

    Repeater {
        model: SystemTray.items
        delegate: Rectangle {
            id: slot
            required property var modelData
            required property int index
            width: 32; height: 32
            radius: Theme.roundingItem
            color: slotMA.containsMouse ? Theme.bgHover : "transparent"
            Behavior on color { ColorAnimation { duration: Theme.durationFast } }
            visible: index < 6 || SystemTray.items.values.length <= 6

            Image {
                id: trayIcon
                anchors.centerIn: parent
                width: 20; height: 20
                // systemTrayItem.icon is already a source string in 0.3.0 —
                // do not pass it through Quickshell.iconPath (that is for themed
                // icon *names*, and would garble already-resolved sources)
                source: slot.modelData.icon
                smooth: true
                asynchronous: true
                sourceSize: Qt.size(20, 20)
            }
            Text {
                anchors.centerIn: parent
                visible: trayIcon.status === Image.Error
                text: Icons.warning
                font.family: Theme.fontFamily
                font.pixelSize: 12
                color: Theme.fgDim
            }

            // Platform menu (hyprland menubar) for tray items that provide one.
            // Requires `//@ pragma UseQApplication` in shell.qml.
            QsMenuAnchor {
                id: menuAnchor
                anchor.item: slot
                menu: slot.modelData.menu
            }

            ToolTip.visible: slotMA.containsMouse && !!slot.modelData.tooltipTitle
            ToolTip.text: (slot.modelData.tooltipTitle || "") + (slot.modelData.tooltipDescription ? "\n" + slot.modelData.tooltipDescription : "")
            ToolTip.delay: 500
            MouseArea {
                id: slotMA
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                onClicked: (mouse) => {
                    if (mouse.button === Qt.RightButton) {
                        if (slot.modelData.hasMenu) menuAnchor.open()
                        else slot.modelData.secondaryActivate()
                    } else if (mouse.button === Qt.MiddleButton) {
                        slot.modelData.secondaryActivate()
                    } else slot.modelData.activate()
                }
                onPressAndHold: {
                    if (slot.modelData.hasMenu) menuAnchor.open()
                    else slot.modelData.secondaryActivate()
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