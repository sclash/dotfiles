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

    Rectangle {
        width: 520
        anchors.centerIn: parent
        radius: Theme.roundingLauncher
        color: Theme.bgLauncher
        border.width: 1
        border.color: Theme.borderActive
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Theme.padL
            spacing: Theme.gapM
            Text { text: "Power"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fgMuted; font.capitalization: Font.AllUppercase; font.letterSpacing: 1.2 }
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
                        { label: "Sleep", icon: Icons.sleep, cmd: ["systemctl","suspend"], confirm: false, col: Theme.fg },
                        { label: "Reboot", icon: Icons.reboot, cmd: ["systemctl","reboot"], confirm: true, col: Theme.warning },
                        { label: "Shutdown", icon: Icons.power, cmd: ["systemctl","poweroff"], confirm: true, col: Theme.critical },
                        { label: planeActive ? "Plane ON" : "Plane Mode", sub: planeActive ? "tap to disable" : "airplane", icon: planeActive ? Icons.planeOn : Icons.planeOff, cmd: [], confirm: false, col: planeActive ? Theme.accent : Theme.fg, isPlane: true },
                        { label: "Logout", icon: Icons.logout, cmd: ["hyprctl","dispatch","exit"], confirm: true, col: Theme.warning }
                    ]
                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        Layout.preferredHeight: 84
                        radius: Theme.roundingItem
                        color: grid.currentIndex===index ? Theme.bgActive : (ma.containsMouse ? Theme.bgHover : "transparent")
                        border.color: grid.currentIndex===index ? modelData.col : Theme.border
                        border.width: grid.currentIndex===index ? 2 : 1
                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 6
                            Text { text: modelData.icon; font.family: Theme.fontFamily; font.pixelSize: 22; color: modelData.col; Layout.alignment: Qt.AlignHCenter }
                            Text { text: modelData.label; font.family: Theme.fontFamily; font.pixelSize: 13; font.weight: Theme.fontWeightMedium; color: Theme.fg; Layout.alignment: Qt.AlignHCenter }
                            Text { visible: !!modelData.sub; text: modelData.sub || ""; font.family: Theme.fontFamily; font.pixelSize: 10; color: Theme.fgMuted; Layout.alignment: Qt.AlignHCenter }
                            Text {
                                visible: root.confirmIndex===index
                                text: "↩ again to confirm"
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                                color: modelData.col
                                Layout.alignment: Qt.AlignHCenter
                            }
                        }
                        MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; onClicked: { grid.currentIndex=index; activate() } }
                        function activate(){
                            if (modelData.isPlane) { togglePlane(); return }
                            if (modelData.confirm && root.confirmIndex!==index) { root.confirmIndex=index; return }
                            root.confirmIndex=-1
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
                    const modelData = [
                        { label: "Sleep", cmd: ["systemctl","suspend"], confirm: false },
                        { label: "Reboot", cmd: ["systemctl","reboot"], confirm: true },
                        { label: "Shutdown", cmd: ["systemctl","poweroff"], confirm: true },
                        { label: "Plane", cmd: [], confirm: false, isPlane:true },
                        { label: "Logout", cmd: ["hyprctl","dispatch","exit"], confirm:true }
                    ][idx]
                    if (!modelData) return
                    if (modelData.isPlane) { togglePlane(); return }
                    if (modelData.confirm && root.confirmIndex!==idx) { root.confirmIndex=idx; return }
                    root.confirmIndex=-1
                    execProc.command=modelData.cmd
                    execProc.running=true
                    if (!modelData.isPlane) root.close()
                }
            }
            Text { text: "h/j/k/l move · Enter activate · Esc cancel"; font.family: Theme.fontFamily; font.pixelSize: 10; color: Theme.fgDim; Layout.alignment: Qt.AlignHCenter }
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
