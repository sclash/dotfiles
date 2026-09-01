import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../services"

RowLayout {
    id: root
    spacing: 4

    Rectangle {
        width: 28; height: 28
        radius: 8
        color: handleMA.containsMouse ? Theme.bgHover : "transparent"
        Behavior on color { ColorAnimation { duration: Theme.durationFast } }
        Text {
            anchors.centerIn: parent
            text: PerfService.expanded ? Icons.collapse : Icons.expand
            font.family: Theme.fontFamily
            font.pixelSize: 14
            color: PerfService.expanded ? Theme.accent : Theme.fgMuted
        }
        MouseArea {
            id: handleMA
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: PerfService.toggle()
        }
    }

    RowLayout {
        visible: PerfService.expanded
        spacing: 10

        RowLayout {
            spacing: 4
            Text { text: Icons.disk; font.family: Theme.fontFamily; font.pixelSize: 14; color: Theme.fgMuted }
            Text {
                text: PerfService.diskUsedGb + "G " + PerfService.diskPercent + "%"
                font.family: Theme.fontFamily
                font.pixelSize: 11
                color: {
                    if (PerfService.diskPercent >= 90) return Theme.critical
                    if (PerfService.diskPercent >= 60) return Theme.warning
                    return Theme.fg
                }
            }
        }
        RowLayout {
            spacing: 4
            Text { text: Icons.cpu; font.family: Theme.fontFamily; font.pixelSize: 14; color: Theme.fgMuted }
            Text {
                text: PerfService.cpuUsage + "%"
                font.family: Theme.fontFamily
                font.pixelSize: 11
                font.weight: Theme.fontWeightMedium
                color: {
                    if (PerfService.cpuUsage >= 90) return Theme.critical
                    if (PerfService.cpuUsage >= 60) return Theme.warning
                    return Theme.fg
                }
            }
            Text {
                visible: PerfService.cpuLoad > 0
                text: PerfService.cpuLoad.toFixed(2)
                font.family: Theme.fontFamily
                font.pixelSize: 10
                color: Theme.fgMuted
            }
        }
        RowLayout {
            spacing: 4
            Text { text: Icons.memory; font.family: Theme.fontFamily; font.pixelSize: 14; color: Theme.fgMuted }
            Text {
                text: PerfService.memUsedGiB + "G " + PerfService.memPercent + "%"
                font.family: Theme.fontFamily
                font.pixelSize: 11
                color: {
                    if (PerfService.memPercent >= 90) return Theme.critical
                    if (PerfService.memPercent >= 60) return Theme.warning
                    return Theme.fg
                }
            }
        }
        RowLayout {
            spacing: 4
            Text { text: Icons.temp; font.family: Theme.fontFamily; font.pixelSize: 14; color: Theme.accent }
            Text {
                text: PerfService.tempC >=0 ? PerfService.tempC + "°" : "--°"
                font.family: Theme.fontFamily
                font.pixelSize: 11
                color: {
                    if (PerfService.tempC <0) return Theme.fgDim
                    if (PerfService.tempC >= 80) return Theme.critical
                    if (PerfService.tempC >= 60) return Theme.warning
                    return Theme.accent
                }
            }
        }
        Rectangle { width: 1; height: 14; color: Theme.border; Layout.alignment: Qt.AlignVCenter }
    }
}
