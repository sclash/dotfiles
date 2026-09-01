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
            // Total height = bar pill (30) + vertical margins (5+5) ≈ 40, keep spec barHeight as pill height
            implicitHeight: Theme.barHeight + 10
            color: "transparent"
            exclusionMode: ExclusionMode.Auto

            // Pill — STYLE.md §4 single pill fallback with 3 groups inside
            Rectangle {
                id: pill
                anchors {
                    left: parent.left; right: parent.right; top: parent.top; bottom: parent.bottom
                    leftMargin: Theme.padL      // 10
                    rightMargin: Theme.padL     // 10
                    topMargin: 5
                    bottomMargin: 5
                }
                radius: Theme.roundingBar       // 10
                color: Theme.bgBar              // #00000099
                border.width: Theme.borderWidth
                border.color: Theme.border      // #59595955
                // Shadow via layer (optional, matches waybar shadow range 4)
                // layer.enabled: true not needed for simple rect

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.padM   // 7 — waybar modules-left padding
                    anchors.rightMargin: Theme.padM
                    spacing: Theme.gapM

                    // Left — Workspaces + AppTray per Bar-App-Tray.md
                    RowLayout {
                        Layout.alignment: Qt.AlignVCenter
                        spacing: Theme.gapS
                        Workspaces { }
                        Rectangle {
                            visible: tray.visible
                            width: 1; height: 18
                            color: Theme.border
                            Layout.alignment: Qt.AlignVCenter
                        }
                        AppTray { id: tray; barWindow: barWin }
                    }

                    Item { Layout.fillWidth: true }

                    DateBlock {
                        id: dateBlock
                        Layout.alignment: Qt.AlignVCenter
                        onToggleNotif: root.launcherToggleRequested("notification")
                    }

                    Item { Layout.fillWidth: true }

                    RowLayout {
                        Layout.alignment: Qt.AlignVCenter
                        spacing: Theme.gapS

                        PerfDrawer { }

                        // Audio — uses AudioIcon component inside hover slot (STYLE.m)
                        Rectangle {
                            width: Theme.barIconSlot
                            height: Theme.barIconSlot
                            radius: Theme.roundingItem
                            color: audioMA.containsMouse ? Theme.bgHover : "transparent"
                            Behavior on color { ColorAnimation { duration: Theme.durationFast } }
                            // AudioIcon itself handles click+wheel; wrapper provides hover bg
                            Item {
                                anchors.centerIn: parent
                                width: Theme.barIconSlot - 4; height: Theme.barIconSlot - 4
                                clip: true
                                // Use the dedicated component for logic, but keep visual consistent with bar slot
                                RowLayout {
                                    anchors.centerIn: parent
                                    spacing: 2
                                    Text {
                                        text: {
                                            if (!AudioService.available || !AudioService.hasSink) return Icons.audioMuted
                                            if (AudioService.muted) return Icons.audioMuted
                                            return Icons.audioVolume
                                        }
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.barIconSize
                                        color: {
                                            if (!AudioService.available || !AudioService.hasSink) return Theme.critical
                                            if (AudioService.muted) return Theme.fgDim
                                            return Theme.fg
                                        }
                                    }
                                    Text {
                                        visible: AudioService.hasSink && !AudioService.muted
                                        text: AudioService.hasSink ? AudioService.volume + "%" : ""
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 9
                                        color: Theme.fgMuted
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
                            // Tooltip via hover? simple text
                        }

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
                            color: wifiMA.containsMouse ? Theme.bgHover : "transparent"
                            Behavior on color { ColorAnimation { duration: Theme.durationFast } }
                            Text {
                                anchors.centerIn: parent
                                text: {
                                    if (!NetworkService.available) return Icons.wifiDisconnected
                                    if (NetworkService.vpnActive) return Icons.vpn
                                    if (!NetworkService.connected) return Icons.wifiDisconnected
                                    if (NetworkService.type === "ethernet") return Icons.wifiEthernet
                                    return Icons.wifiConnected
                                }
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.barIconSize
                                color: {
                                    if (!NetworkService.available || !NetworkService.connected) return Theme.fgDim
                                    if (NetworkService.vpnActive) return Theme.accent
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
                            width: 78
                            height: Theme.barIconSlot
                            radius: Theme.roundingItem
                            color: kbMA.containsMouse ? Theme.bgHover : "transparent"
                            Behavior on color { ColorAnimation { duration: Theme.durationFast } }
                            Text {
                                anchors.centerIn: parent
                                text: {
                                    const flag = HyprService.layoutName === "IT" ? " \uD83C\uDDEE\uD83C\uDDF9" : " \uD83C\uDDFA\uD83C\uDDF8"
                                    return Icons.keyboard + " " + HyprService.layoutName + flag
                                }
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
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
}
