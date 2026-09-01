import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../../theme"
import "../../services"

PanelWindow {
    id: root
    property bool isOpen: false
    property int confirmIndex: -1
    function open(){ isOpen=true }
    function close(){ isOpen=false; confirmIndex=-1 }
    function toggle(){ if(isOpen) close(); else open() }

    anchors { top:true; bottom:true; left:true; right:true }
    color: "transparent"
    visible: isOpen
    focusable: true
    exclusionMode: ExclusionMode.Ignore
    Rectangle { anchors.fill: parent; color: Theme.overlay; MouseArea { anchors.fill: parent; onClicked: root.close() } }

    // Card — omarchy matte-black: warm accent, low chrome, generous radius
    Rectangle {
        width: 520
        anchors.centerIn: parent
        radius: Theme.roundingLauncher
        color: Theme.bgLauncher
        border.width: 1
        border.color: Theme.borderActive
        // subtle shadow via border + overlay already
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Theme.padL
            spacing: Theme.gapM
            Text { text: "Power"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fgMuted; font.capitalization: Font.AllUppercase; font.letterSpacing: 1.2 }
            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border }
            GridLayout {
                id: grid
                columns: 2
                rowSpacing: Theme.gapM
                columnSpacing: Theme.gapM
                Layout.fillWidth: true
                focus: true
                property int currentIndex: 0
                Repeater {
                    model: [
                        { label: "Sleep", icon: Icons.sleep, cmd: ["systemctl","suspend"], confirm: false, col: Theme.fg, isPlane: false },
                        { label: "Reboot", icon: Icons.reboot, cmd: ["systemctl","reboot"], confirm: true, col: Theme.warning, isPlane: false },
                        { label: "Shutdown", icon: Icons.power, cmd: ["systemctl","poweroff"], confirm: true, col: Theme.critical, isPlane: false },
                        { label: planeActive ? "Plane ON" : "Plane Mode", sub: planeActive ? "tap to disable" : "airplane", icon: planeActive ? Icons.planeOn : Icons.planeOff, cmd: [], confirm: false, col: planeActive ? Theme.accent : Theme.fg, isPlane: true },
                        { label: "Logout", icon: Icons.logout, cmd: ["hyprctl","dispatch","exit"], confirm: true, col: Theme.warning, isPlane: false }
                    ]
                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        // Orphan Logout spans full width centered — fixes 2-col 5-item asymmetry
                        Layout.fillWidth: true
                        Layout.columnSpan: (index === 4) ? 2 : 1
                        Layout.preferredWidth: (index === 4) ? grid.width : -1
                        Layout.maximumWidth: (index === 4) ? 260 : 9999
                        Layout.alignment: (index === 4) ? Qt.AlignHCenter : Qt.AlignLeft
                        Layout.preferredHeight: 92
                        radius: Theme.roundingItem
                        // omarchy quattro: normal transparent, hover selection, selected muted, plane ON accent tint
                        color: {
                            if (modelData.isPlane && planeActive) return Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.14)
                            if (grid.currentIndex===index) return Theme.bgActive
                            if (ma.containsMouse) return Theme.bgHover
                            return "transparent"
                        }
                        border.color: {
                            if (grid.currentIndex===index) {
                                if (modelData.isPlane && planeActive) return Theme.accent
                                // Sleep focused should pop accent, not fg
                                if (modelData.label === "Sleep") return Theme.accent
                                return modelData.col
                            }
                            return Theme.border
                        }
                        border.width: grid.currentIndex===index ? 2 : 1
                        Behavior on color { ColorAnimation { duration: Theme.durationFast } }
                        Behavior on border.color { ColorAnimation { duration: Theme.durationFast } }

                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 5
                            // Icon circle — warm accent for plane ON, otherwise muted bar
                            Rectangle {
                                width: 42; height: 42; radius: 12
                                color: {
                                    if (modelData.isPlane && planeActive) return Theme.accent
                                    if (grid.currentIndex===index) return Theme.bgBar
                                    return Theme.bgBar
                                }
                                border.width: 0
                                Layout.alignment: Qt.AlignHCenter
                                Text {
                                    anchors.centerIn: parent
                                    text: modelData.icon
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 22
                                    color: {
                                        if (modelData.isPlane && planeActive) return Theme.bgLauncher
                                        return modelData.col
                                    }
                                }
                            }
                            Text { text: modelData.label; font.family: Theme.fontFamily; font.pixelSize: 13; font.weight: Theme.fontWeightMedium; color: Theme.fg; Layout.alignment: Qt.AlignHCenter }
                            Text {
                                visible: !!modelData.sub
                                text: modelData.sub || ""
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                                color: modelData.isPlane && planeActive ? Theme.accent : Theme.fgMuted
                                Layout.alignment: Qt.AlignHCenter
                            }
                            Text {
                                visible: root.confirmIndex===index
                                text: "↩ again to confirm"
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                                font.weight: Theme.fontWeightMedium
                                color: modelData.col
                                Layout.alignment: Qt.AlignHCenter
                            }
                        }
                        MouseArea {
                            id: ma
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { grid.currentIndex=index; activate() }
                        }
                        function activate(){
                            if (modelData.isPlane) { togglePlane(); return }
                            if (modelData.confirm && root.confirmIndex!==index) { root.confirmIndex=index; return }
                            root.confirmIndex=-1
                            console.log("[ShutdownLauncher] exec:", JSON.stringify(modelData.cmd))
                            execProc.command = modelData.cmd
                            execProc.running = true
                            root.close()
                        }
                    }
                }
                Keys.onPressed: (e)=>{
                    const cols=2; let idx=grid.currentIndex; const count=5
                    if(e.key===Qt.Key_H || e.key===Qt.Key_Left) { idx=Math.max(0,idx-1); e.accepted=true }
                    else if(e.key===Qt.Key_L || e.key===Qt.Key_Right) { idx=Math.min(count-1,idx+1); e.accepted=true }
                    else if(e.key===Qt.Key_K || e.key===Qt.Key_Up) { idx=Math.max(0,idx-cols); e.accepted=true }
                    else if(e.key===Qt.Key_J || e.key===Qt.Key_Down) { idx=Math.min(count-1,idx+cols); e.accepted=true }
                    else if(e.key===Qt.Key_Return || e.key===Qt.Key_Enter) { activateIndex(idx); e.accepted=true }
                    else if(e.key===Qt.Key_Escape) { if(root.confirmIndex!==-1){root.confirmIndex=-1; e.accepted=true} else root.close() }
                    grid.currentIndex=idx
                }
                function activateIndex(idx){
                    const entries = [
                        { label: "Sleep", cmd: ["systemctl","suspend"], confirm: false, isPlane:false },
                        { label: "Reboot", cmd: ["systemctl","reboot"], confirm: true, isPlane:false },
                        { label: "Shutdown", cmd: ["systemctl","poweroff"], confirm: true, isPlane:false },
                        { label: "Plane", cmd: [], confirm: false, isPlane:true },
                        { label: "Logout", cmd: ["hyprctl","dispatch","exit"], confirm:true, isPlane:false }
                    ]
                    const m = entries[idx]
                    if (!m) return
                    if (m.isPlane) { togglePlane(); return }
                    if (m.confirm && root.confirmIndex!==idx) { root.confirmIndex=idx; return }
                    root.confirmIndex=-1
                    if (m.cmd && m.cmd.length>0) {
                        console.log("[ShutdownLauncher] exec:", JSON.stringify(m.cmd))
                        execProc.command=m.cmd
                        execProc.running=true
                    }
                    if (!m.isPlane) root.close()
                }
            }
            Text { text: "h/j/k/l move · Enter activate · Esc cancel · plane toggles radios"; font.family: Theme.fontFamily; font.pixelSize: 10; color: Theme.fgDim; Layout.alignment: Qt.AlignHCenter; wrapMode: Text.Wrap; horizontalAlignment: Text.AlignHCenter; Layout.fillWidth: true }
        }
        Keys.onEscapePressed: { if(confirmIndex!==-1) confirmIndex=-1; else root.close() }
    }

    property bool planeActive: false
    function togglePlane(){
        if (planeActive) {
            planeProc.command = ["sh","-c","rfkill unblock all; nmcli radio all on 2>/dev/null; bluetoothctl power on 2>/dev/null || true"]
            planeActive=false
        } else {
            planeProc.command = ["sh","-c","nmcli radio all off 2>/dev/null; bluetoothctl power off 2>/dev/null; rfkill block all 2>/dev/null || true"]
            planeActive=true
        }
        planeProc.running=true
    }
    property Process execProc: Process {}
    property Process planeProc: Process {}
    property Process planeCheck: Process {
        command: ["sh","-c","rfkill list 2>/dev/null | grep -q \"Soft blocked: yes\" && echo on || echo off"]
        stdout: StdioCollector { onStreamFinished: root.planeActive = this.text.trim()==="on" }
    }
    onIsOpenChanged: if(isOpen) planeCheck.running=true
}
