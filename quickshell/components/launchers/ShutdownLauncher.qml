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
    property int currentIndex: 0
    function open(){ isOpen=true; currentIndex=0 }
    function close(){ isOpen=false; confirmIndex=-1 }
    function toggle(){ if(isOpen) close(); else open() }

    anchors { top:true; bottom:true; left:true; right:true }
    color: "transparent"
    visible: isOpen
    focusable: true
    exclusionMode: ExclusionMode.Ignore
    Rectangle { anchors.fill: parent; color: Theme.overlay; MouseArea { anchors.fill: parent; onClicked: root.close() } }

    Rectangle {
        id: card
        width: 520
        // Explicit centering — ensures card is dead-center on any screen
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        radius: Theme.roundingLauncher
        color: Theme.bgLauncher
        border.width: 1
        border.color: Theme.borderActive

        ColumnLayout {
            id: mainCol
            anchors.fill: parent
            anchors.margins: Theme.padL
            spacing: Theme.gapM
            focus: true

            Text { text: "Power"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fgMuted; font.capitalization: Font.AllUppercase; font.letterSpacing: 1.2 }
            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border }

            // Row 1: Sleep | Reboot
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.gapM
                // Sleep 0
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 92
                    radius: Theme.roundingItem
                    color: {
                        if (root.currentIndex===0) return Theme.bgActive
                        if (sleepMA.containsMouse) return Theme.bgHover
                        return Theme.bgBar
                    }
                    border.color: root.currentIndex===0 ? Theme.accent : Theme.border
                    border.width: root.currentIndex===0 ? 2 : 1
                    Behavior on color { ColorAnimation { duration: Theme.durationFast } }
                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 5
                        Rectangle { width: 42; height: 42; radius: 12; color: Theme.bgBar; Layout.alignment: Qt.AlignHCenter
                            Text { anchors.centerIn: parent; text: Icons.sleep; font.family: Theme.fontFamily; font.pixelSize: 22; color: Theme.fg }
                        }
                        Text { text: "Sleep"; font.family: Theme.fontFamily; font.pixelSize: 13; font.weight: Theme.fontWeightMedium; color: Theme.fg; Layout.alignment: Qt.AlignHCenter }
                        Text { visible: root.confirmIndex===0; text: "↩ again to confirm"; font.family: Theme.fontFamily; font.pixelSize: 10; font.weight: Theme.fontWeightMedium; color: Theme.fg; Layout.alignment: Qt.AlignHCenter }
                    }
                    MouseArea { id: sleepMA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { root.currentIndex=0; activate(0) } }
                }
                // Reboot 1
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 92
                    radius: Theme.roundingItem
                    color: {
                        if (root.currentIndex===1) return Theme.bgActive
                        if (rebootMA.containsMouse) return Theme.bgHover
                        return Theme.bgBar
                    }
                    border.color: root.currentIndex===1 ? Theme.warning : Theme.border
                    border.width: root.currentIndex===1 ? 2 : 1
                    Behavior on color { ColorAnimation { duration: Theme.durationFast } }
                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 5
                        Rectangle { width: 42; height: 42; radius: 12; color: Theme.bgBar; Layout.alignment: Qt.AlignHCenter
                            Text { anchors.centerIn: parent; text: Icons.reboot; font.family: Theme.fontFamily; font.pixelSize: 22; color: Theme.warning }
                        }
                        Text { text: "Reboot"; font.family: Theme.fontFamily; font.pixelSize: 13; font.weight: Theme.fontWeightMedium; color: Theme.fg; Layout.alignment: Qt.AlignHCenter }
                        Text { visible: root.confirmIndex===1; text: "↩ again to confirm"; font.family: Theme.fontFamily; font.pixelSize: 10; font.weight: Theme.fontWeightMedium; color: Theme.warning; Layout.alignment: Qt.AlignHCenter }
                    }
                    MouseArea { id: rebootMA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { root.currentIndex=1; activate(1) } }
                }
            }

            // Row 2: Shutdown | Plane
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.gapM
                // Shutdown 2
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 92
                    radius: Theme.roundingItem
                    color: {
                        if (root.currentIndex===2) return Theme.bgActive
                        if (shutdownMA.containsMouse) return Theme.bgHover
                        return Theme.bgBar
                    }
                    border.color: root.currentIndex===2 ? Theme.critical : Theme.border
                    border.width: root.currentIndex===2 ? 2 : 1
                    Behavior on color { ColorAnimation { duration: Theme.durationFast } }
                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 5
                        Rectangle { width: 42; height: 42; radius: 12; color: Theme.bgBar; Layout.alignment: Qt.AlignHCenter
                            Text { anchors.centerIn: parent; text: Icons.power; font.family: Theme.fontFamily; font.pixelSize: 22; color: Theme.critical }
                        }
                        Text { text: "Shutdown"; font.family: Theme.fontFamily; font.pixelSize: 13; font.weight: Theme.fontWeightMedium; color: Theme.fg; Layout.alignment: Qt.AlignHCenter }
                        Text { visible: root.confirmIndex===2; text: "↩ again to confirm"; font.family: Theme.fontFamily; font.pixelSize: 10; font.weight: Theme.fontWeightMedium; color: Theme.critical; Layout.alignment: Qt.AlignHCenter }
                    }
                    MouseArea { id: shutdownMA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { root.currentIndex=2; activate(2) } }
                }
                // Plane 3
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 92
                    radius: Theme.roundingItem
                    color: {
                        if (planeActive) return Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.14)
                        if (root.currentIndex===3) return Theme.bgActive
                        if (planeMA.containsMouse) return Theme.bgHover
                        return Theme.bgBar
                    }
                    border.color: planeActive ? Theme.accent : (root.currentIndex===3 ? Theme.accent : Theme.border)
                    border.width: (planeActive || root.currentIndex===3) ? 2 : 1
                    Behavior on color { ColorAnimation { duration: Theme.durationFast } }
                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 5
                        Rectangle {
                            width: 42; height: 42; radius: 12
                            color: planeActive ? Theme.accent : Theme.bgBar
                            Layout.alignment: Qt.AlignHCenter
                            Text { anchors.centerIn: parent; text: planeActive ? Icons.planeOn : Icons.planeOff; font.family: Theme.fontFamily; font.pixelSize: 22; color: planeActive ? Theme.bgLauncher : Theme.fg }
                        }
                        Text { text: planeActive ? "Plane ON" : "Plane Mode"; font.family: Theme.fontFamily; font.pixelSize: 13; font.weight: Theme.fontWeightMedium; color: Theme.fg; Layout.alignment: Qt.AlignHCenter }
                        Text { text: planeActive ? "tap to disable" : "airplane"; font.family: Theme.fontFamily; font.pixelSize: 10; color: planeActive ? Theme.accent : Theme.fgMuted; Layout.alignment: Qt.AlignHCenter }
                    }
                    MouseArea { id: planeMA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { root.currentIndex=3; togglePlane() } }
                }
            }

            // Row 3: Logout centered — fixes orphan alignment, guarantees centering
            RowLayout {
                Layout.fillWidth: true
                spacing: 0
                Item { Layout.fillWidth: true }
                Rectangle {
                    Layout.preferredWidth: 240
                    Layout.preferredHeight: 92
                    Layout.alignment: Qt.AlignHCenter
                    radius: Theme.roundingItem
                    color: {
                        if (root.currentIndex===4) return Theme.bgActive
                        if (logoutMA.containsMouse) return Theme.bgHover
                        return Theme.bgBar
                    }
                    border.color: root.currentIndex===4 ? Theme.warning : Theme.border
                    border.width: root.currentIndex===4 ? 2 : 1
                    Behavior on color { ColorAnimation { duration: Theme.durationFast } }
                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 5
                        Rectangle { width: 42; height: 42; radius: 12; color: Theme.bgBar; Layout.alignment: Qt.AlignHCenter
                            Text { anchors.centerIn: parent; text: Icons.logout; font.family: Theme.fontFamily; font.pixelSize: 22; color: Theme.warning }
                        }
                        Text { text: "Logout"; font.family: Theme.fontFamily; font.pixelSize: 13; font.weight: Theme.fontWeightMedium; color: Theme.fg; Layout.alignment: Qt.AlignHCenter }
                        Text { visible: root.confirmIndex===4; text: "↩ again to confirm"; font.family: Theme.fontFamily; font.pixelSize: 10; font.weight: Theme.fontWeightMedium; color: Theme.warning; Layout.alignment: Qt.AlignHCenter }
                    }
                    MouseArea { id: logoutMA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { root.currentIndex=4; activate(4) } }
                }
                Item { Layout.fillWidth: true }
            }

            Text { text: "h/j/k/l move · Enter activate · Esc cancel"; font.family: Theme.fontFamily; font.pixelSize: 10; color: Theme.fgDim; Layout.alignment: Qt.AlignHCenter }

            Keys.onPressed: (e)=>{
                let idx=root.currentIndex; const count=5
                if(e.key===Qt.Key_H || e.key===Qt.Key_Left) { idx=Math.max(0,idx-1); e.accepted=true }
                else if(e.key===Qt.Key_L || e.key===Qt.Key_Right) { idx=Math.min(count-1,idx+1); e.accepted=true }
                else if(e.key===Qt.Key_K || e.key===Qt.Key_Up) { idx=Math.max(0,idx-2); e.accepted=true }
                else if(e.key===Qt.Key_J || e.key===Qt.Key_Down) { idx=Math.min(count-1,idx+2); e.accepted=true }
                else if(e.key===Qt.Key_Return || e.key===Qt.Key_Enter) { activate(idx); e.accepted=true }
                else if(e.key===Qt.Key_Escape) { if(root.confirmIndex!==-1){root.confirmIndex=-1; e.accepted=true} else root.close() }
                root.currentIndex=idx
            }
            Component.onCompleted: forceActiveFocus()
        }
        Keys.onEscapePressed: { if(confirmIndex!==-1) confirmIndex=-1; else root.close() }
        // Ensure card grabs focus when opened
        onVisibleChanged: if(visible) mainCol.forceActiveFocus()
    }

    function activate(idx){
        if (idx===3) { togglePlane(); return }
        const needsConfirm = (idx===1 || idx===2 || idx===4)
        if (needsConfirm && root.confirmIndex!==idx) { root.confirmIndex=idx; return }
        root.confirmIndex=-1
        let cmd=[]
        if(idx===0) cmd=["systemctl","suspend"]
        else if(idx===1) cmd=["systemctl","reboot"]
        else if(idx===2) cmd=["systemctl","poweroff"]
        else if(idx===4) cmd=["hyprctl","dispatch","exit"]
        if(cmd.length>0){
            console.log("[ShutdownLauncher] exec:", JSON.stringify(cmd))
            execProc.command=cmd
            execProc.running=true
            root.close()
        }
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
    onIsOpenChanged: {
        if(isOpen) { planeCheck.running=true; currentIndex=0; confirmIndex=-1; Qt.callLater(()=> mainCol.forceActiveFocus()) }
    }
}
