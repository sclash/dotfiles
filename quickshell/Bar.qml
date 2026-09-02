import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import "theme"
import "services"
import "components/bar"

Scope {
    id: root
    signal launcherToggleRequested(string name)

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: barWin
            required property var modelData
            screen: modelData

            anchors { top: true; left: true; right: true }
            implicitHeight: Theme.barHeight
            color: "transparent"
            exclusionMode: ExclusionMode.Auto

            Rectangle {
                anchors.fill: parent
                color: Theme.bgBar

                RowLayout {
                    id: leftGroup
                    anchors { left: parent.left; leftMargin: Theme.padM; verticalCenter: parent.verticalCenter }
                    spacing: Theme.gapM
                    Workspaces { }
                    Rectangle {
                        visible: tray.visible
                        width: 1; height: 18
                        color: Theme.border
                    }
                    AppTray { id: tray; barWindow: barWin }
                }

                DateBlock {
                    id: dateBlock
                    anchors { horizontalCenter: parent.horizontalCenter; verticalCenter: parent.verticalCenter }
                    onToggleNotif: root.launcherToggleRequested("notification")
                }

                RowLayout {
                    id: rightGroup
                    anchors { right: parent.right; rightMargin: Theme.padM; verticalCenter: parent.verticalCenter }
                    spacing: 2

                    PerfDrawer { }

                    Rectangle {
                        width: Theme.barIconSlot
                        height: Theme.barIconSlot
                        radius: Theme.roundingItem
                        color: btMA.containsMouse ? Theme.bgHover : "transparent"
                        Behavior on color { ColorAnimation { duration: Theme.durationFast } }
                        Text {
                            anchors.centerIn: parent
                            text: {
                                if (!BluetoothService.available || !BluetoothService.powered) return Icons.bluetoothOff
                                return Icons.bluetoothOn
                            }
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.barIconSize
                            color: {
                                if (!BluetoothService.available || !BluetoothService.powered) return Theme.fgDim
                                if (BluetoothService.connectedCount > 0) return Theme.accent
                                return Theme.fg
                            }
                        }
                        Rectangle {
                            visible: BluetoothService.connectedCount > 1
                            width: 14; height: 14; radius: 7
                            color: Theme.accent
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.rightMargin: -2
                            anchors.topMargin: -2
                            Text {
                                anchors.centerIn: parent
                                text: String(BluetoothService.connectedCount)
                                font.pixelSize: 8
                                font.family: Theme.fontFamily
                                color: Theme.bgBar
                            }
                        }
                        MouseArea {
                            id: btMA
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.launcherToggleRequested("bluetooth")
                        }
                    }

                    Rectangle {
                        width: Theme.barIconSlot
                        height: Theme.barIconSlot
                        radius: Theme.roundingItem
                        color: audioMA.containsMouse ? Theme.bgHover : "transparent"
                        Behavior on color { ColorAnimation { duration: Theme.durationFast } }
                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 2
                            Text {
                                text: {
                                    if (!AudioService.available || !AudioService.hasSink) return Icons.audioMuted
                                    if (AudioService.muted) return Icons.audioMuted
                                    if (AudioService.volume >= 66) return Icons.audioHigh
                                    if (AudioService.volume >= 33) return Icons.audioMedium
                                    return Icons.audioLow
                                }
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.barIconSize
                                color: {
                                    if (!AudioService.available || !AudioService.hasSink) return Theme.critical
                                    if (AudioService.muted) return Theme.fgDim
                                    return Theme.fg
                                }
                            }
                        }
                        MouseArea {
                            id: audioMA
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.launcherToggleRequested("audio")
                            onWheel: (wheel) => {
                                if (wheel.angleDelta.y > 0) AudioService.adjustVolume(0.05)
                                else if (wheel.angleDelta.y < 0) AudioService.adjustVolume(-0.05)
                            }
                        }
                    }

                    Rectangle {
                        width: Theme.barIconSlot
                        height: Theme.barIconSlot
                        radius: Theme.roundingItem
                        color: wifiMA.containsMouse ? Theme.bgHover : "transparent"
                        Behavior on color { ColorAnimation { duration: Theme.durationFast } }
                        Text {
                            anchors.centerIn: parent
                            text: {
                                if (!NetworkService.available) return Icons.wifiDisconnected
                                if (!NetworkService.connected) return Icons.wifiDisconnected
                                if (NetworkService.type === "ethernet") return Icons.wifiEthernet
                                const s = NetworkService.signalStrength
                                if (s >= 75) return Icons.wifiSignal4
                                if (s >= 50) return Icons.wifiSignal3
                                if (s >= 25) return Icons.wifiSignal2
                                return Icons.wifiSignal1
                            }
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.barIconSize
                            color: {
                                if (!NetworkService.available || !NetworkService.connected) return Theme.fgDim
                                if (NetworkService.signalStrength >=0 && NetworkService.signalStrength < 30) return Theme.warning
                                return Theme.fg
                            }
                        }
                        MouseArea {
                            id: wifiMA
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.launcherToggleRequested("network")
                        }
                    }

                    Rectangle {
                        visible: NetworkService.vpnActive
                        height: Theme.barIconSlot
                        Layout.preferredWidth: vpnText.implicitWidth + 14
                        radius: Theme.roundingItem
                        color: vpnMA.containsMouse ? Theme.bgHover : "transparent"
                        Behavior on color { ColorAnimation { duration: Theme.durationFast } }
                        Text {
                            id: vpnText
                            anchors.centerIn: parent
                            text: Icons.vpn + " " + NetworkService.vpnName
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.barIconSize
                            color: Theme.accent
                        }
                        MouseArea {
                            id: vpnMA
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.launcherToggleRequested("network")
                        }
                    }

                    BatteryIcon { }

                    Rectangle {
                        height: Theme.barIconSlot
                        Layout.preferredWidth: kbText.implicitWidth + 14
                        radius: Theme.roundingItem
                        color: kbMA.containsMouse ? Theme.bgHover : "transparent"
                        Behavior on color { ColorAnimation { duration: Theme.durationFast } }
                        Text {
                            id: kbText
                            anchors.centerIn: parent
                            text: Icons.keyboard + " " + HyprService.layoutName
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.barIconSize
                            color: HyprService.available ? Theme.fg : Theme.fgDim
                        }
                        MouseArea {
                            id: kbMA
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: HyprService.cycleLayout()
                        }
                    }

                }
            }
        }
    }
}
