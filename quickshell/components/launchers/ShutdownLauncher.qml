import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../../theme"
import "../../services"

WlrLayershell {
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
    keyboardFocus: WlrKeyboardFocus.Exclusive
    layer: WlrLayer.Overlay
    exclusionMode: ExclusionMode.Ignore
    Rectangle { anchors.fill: parent; color: Theme.overlay; MouseArea { anchors.fill: parent; onClicked: root.close() } }

    // One big box, icons left-to-right
    Rectangle {
        id: card
        width: 620
        height: mainCol.implicitHeight + Theme.padL * 2
        anchors.centerIn: parent
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

            RowLayout {
                id: row
                Layout.fillWidth: true
                spacing: Theme.gapS

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 110
                    radius: Theme.roundingItem
                    color: root.currentIndex===0 ? Theme.bgSelected : (sleepMA.containsMouse ? Theme.bgHover : "transparent")
                    border.color: root.currentIndex===0 ? Theme.borderSelected : "transparent"
                    border.width: 1
                    ColumnLayout { anchors.centerIn: parent; spacing: 8
                        Text { text: Icons.sleep; font.family: Theme.fontFamily; font.pixelSize: 26; color: Theme.fg; Layout.alignment: Qt.AlignHCenter }
                        Text { text: "Sleep"; font.family: Theme.fontFamily; font.pixelSize: 13; font.weight: Theme.fontWeightMedium; color: Theme.fg; Layout.alignment: Qt.AlignHCenter }
                        Text { visible: root.confirmIndex===0; text: "↩ again"; font.family: Theme.fontFamily; font.pixelSize: 9; color: Theme.fg; Layout.alignment: Qt.AlignHCenter }
                    }
                    MouseArea { id: sleepMA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { root.currentIndex=0; activate(0) } }
                }
                Rectangle {
                    // Shown only when logind reports CanHibernate=yes (swap + resume device present).
                    visible: root.canHibernate
                    Layout.fillWidth: true
                    Layout.preferredHeight: 110
                    radius: Theme.roundingItem
                    color: root.currentIndex===1 ? Theme.bgSelected : (hibernateMA.containsMouse ? Theme.bgHover : "transparent")
                    border.color: root.currentIndex===1 ? Theme.borderSelected : "transparent"
                    border.width: 1
                    ColumnLayout { anchors.centerIn: parent; spacing: 8
                        Text { text: Icons.hibernate; font.family: Theme.fontFamily; font.pixelSize: 26; color: Theme.fg; Layout.alignment: Qt.AlignHCenter }
                        Text { text: "Hibernate"; font.family: Theme.fontFamily; font.pixelSize: 13; font.weight: Theme.fontWeightMedium; color: Theme.fg; Layout.alignment: Qt.AlignHCenter }
                    }
                    MouseArea { id: hibernateMA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { root.currentIndex=1; activate(1) } }
                }
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 110
                    radius: Theme.roundingItem
                    color: root.currentIndex===2 ? Theme.bgSelected : (rebootMA.containsMouse ? Theme.bgHover : "transparent")
                    border.color: root.currentIndex===2 ? Theme.warning : "transparent"
                    border.width: 1
                    ColumnLayout { anchors.centerIn: parent; spacing: 8
                        Text { text: Icons.reboot; font.family: Theme.fontFamily; font.pixelSize: 26; color: Theme.warning; Layout.alignment: Qt.AlignHCenter }
                        Text { text: "Reboot"; font.family: Theme.fontFamily; font.pixelSize: 13; font.weight: Theme.fontWeightMedium; color: Theme.fg; Layout.alignment: Qt.AlignHCenter }
                        Text { visible: root.confirmIndex===2; text: "↩ again"; font.family: Theme.fontFamily; font.pixelSize: 9; color: Theme.warning; Layout.alignment: Qt.AlignHCenter }
                    }
                    MouseArea { id: rebootMA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { root.currentIndex=2; activate(2) } }
                }
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 110
                    radius: Theme.roundingItem
                    color: root.currentIndex===3 ? Theme.bgSelected : (shutdownMA.containsMouse ? Theme.bgHover : "transparent")
                    border.color: root.currentIndex===3 ? Theme.critical : "transparent"
                    border.width: 1
                    ColumnLayout { anchors.centerIn: parent; spacing: 8
                        Text { text: Icons.power; font.family: Theme.fontFamily; font.pixelSize: 26; color: Theme.critical; Layout.alignment: Qt.AlignHCenter }
                        Text { text: "Shutdown"; font.family: Theme.fontFamily; font.pixelSize: 13; font.weight: Theme.fontWeightMedium; color: Theme.fg; Layout.alignment: Qt.AlignHCenter }
                        Text { visible: root.confirmIndex===3; text: "↩ again"; font.family: Theme.fontFamily; font.pixelSize: 9; color: Theme.critical; Layout.alignment: Qt.AlignHCenter }
                    }
                    MouseArea { id: shutdownMA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { root.currentIndex=3; activate(3) } }
                }
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 110
                    radius: Theme.roundingItem
                    color: planeActive ? Theme.bgSelected : (root.currentIndex===4 ? Theme.bgSelected : (planeMA.containsMouse ? Theme.bgHover : "transparent"))
                    border.color: planeActive ? Theme.borderSelected : (root.currentIndex===4 ? Theme.borderSelected : "transparent")
                    border.width: 1
                    ColumnLayout { anchors.centerIn: parent; spacing: 8
                        Text { text: planeActive ? Icons.planeOn : Icons.planeOff; font.family: Theme.fontFamily; font.pixelSize: 26; color: planeActive ? Theme.accent : Theme.fg; Layout.alignment: Qt.AlignHCenter }
                        Text { text: planeActive ? "Plane ON" : "Plane"; font.family: Theme.fontFamily; font.pixelSize: 13; font.weight: Theme.fontWeightMedium; color: Theme.fg; Layout.alignment: Qt.AlignHCenter }
                    }
                    MouseArea { id: planeMA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { root.currentIndex=4; togglePlane() } }
                }
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 110
                    radius: Theme.roundingItem
                    color: root.currentIndex===5 ? Theme.bgSelected : (lockMA.containsMouse ? Theme.bgHover : "transparent")
                    border.color: root.currentIndex===5 ? Theme.borderSelected : "transparent"
                    border.width: 1
                    ColumnLayout { anchors.centerIn: parent; spacing: 8
                        Text { text: Icons.lock; font.family: Theme.fontFamily; font.pixelSize: 26; color: Theme.fg; Layout.alignment: Qt.AlignHCenter }
                        Text { text: "Lock"; font.family: Theme.fontFamily; font.pixelSize: 13; font.weight: Theme.fontWeightMedium; color: Theme.fg; Layout.alignment: Qt.AlignHCenter }
                    }
                    MouseArea { id: lockMA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { root.currentIndex=5; activate(5) } }
                }
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 110
                    radius: Theme.roundingItem
                    color: root.currentIndex===6 ? Theme.bgSelected : (logoutMA.containsMouse ? Theme.bgHover : "transparent")
                    border.color: root.currentIndex===6 ? Theme.warning : "transparent"
                    border.width: 1
                    ColumnLayout { anchors.centerIn: parent; spacing: 8
                        Text { text: Icons.logout; font.family: Theme.fontFamily; font.pixelSize: 26; color: Theme.warning; Layout.alignment: Qt.AlignHCenter }
                        Text { text: "Logout"; font.family: Theme.fontFamily; font.pixelSize: 13; font.weight: Theme.fontWeightMedium; color: Theme.fg; Layout.alignment: Qt.AlignHCenter }
                        Text { visible: root.confirmIndex===6; text: "↩ again"; font.family: Theme.fontFamily; font.pixelSize: 9; color: Theme.warning; Layout.alignment: Qt.AlignHCenter }
                    }
                    MouseArea { id: logoutMA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { root.currentIndex=6; activate(6) } }
                }
            }

            Text { text: "← → / h l move · Enter activate · Esc cancel"; font.family: Theme.fontFamily; font.pixelSize: 10; color: Theme.fgDim; Layout.alignment: Qt.AlignHCenter }

            Keys.onPressed: (e)=>{
                let idx=root.currentIndex
                if(e.key===Qt.Key_Q) { root.close(); e.accepted=true }
                else if(e.key===Qt.Key_H || e.key===Qt.Key_Left) { idx=root.step(idx,-1); e.accepted=true }
                else if(e.key===Qt.Key_L || e.key===Qt.Key_Right) { idx=root.step(idx,1); e.accepted=true }
                else if(e.key===Qt.Key_J || e.key===Qt.Key_Down) { idx=root.step(idx,1); e.accepted=true }
                else if(e.key===Qt.Key_K || e.key===Qt.Key_Up) { idx=root.step(idx,-1); e.accepted=true }
                else if(e.key===Qt.Key_Return || e.key===Qt.Key_Enter) { activate(idx); e.accepted=true }
                else if(e.key===Qt.Key_Escape) { if(root.confirmIndex!==-1){root.confirmIndex=-1; e.accepted=true} else root.close() }
                root.currentIndex=idx
            }
            Component.onCompleted: forceActiveFocus()
        }
        Keys.onPressed: (e) => { if (e.key === Qt.Key_Escape || e.key === Qt.Key_Q) { if(confirmIndex!==-1) confirmIndex=-1; else root.close(); e.accepted = true } }
        onVisibleChanged: if(visible) mainCol.forceActiveFocus()
    }

    function activate(idx){
        if (idx===4) { togglePlane(); return }
        if (idx===5) { execProc.command=["hyprlock"]; execProc.running=true; root.close(); return }
        const needsConfirm = (idx===2 || idx===3 || idx===6)
        if (needsConfirm && root.confirmIndex!==idx) { root.confirmIndex=idx; return }
        root.confirmIndex=-1
        let cmd=[]
        if(idx===0) cmd=["systemctl","suspend"]
        else if(idx===1) { if(!root.canHibernate) return; cmd=["systemctl","hibernate"] }
        else if(idx===2) cmd=["systemctl","reboot"]
        else if(idx===3) cmd=["systemctl","poweroff"]
        else if(idx===6) cmd=["hyprctl","dispatch","exit"]
        if(cmd.length>0){
            console.log("[ShutdownLauncher] exec:", JSON.stringify(cmd))
            execProc.command=cmd
            execProc.running=true
            root.close()
        }
    }

    // Tile 1 (Hibernate) is skipped when the machine can't hibernate.
    readonly property int lastIndex: 6
    function step(idx, d){
        let n=Math.max(0, Math.min(lastIndex, idx+d))
        if(n===1 && !canHibernate) n=Math.max(0, Math.min(lastIndex, n+d))
        return n
    }

    // logind answers "yes" only with enough swap and a resume device; anything else hides the tile.
    property bool canHibernate: false
    property Process hibernateCheck: Process {
        command: ["busctl","--system","call","org.freedesktop.login1","/org/freedesktop/login1","org.freedesktop.login1.Manager","CanHibernate"]
        stdout: StdioCollector { onStreamFinished: root.canHibernate = this.text.trim()==='s "yes"' }
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
        command: ["sh","-c","if rfkill list 2>/dev/null | grep -q 'Soft blocked: no'; then echo off; elif rfkill list 2>/dev/null | grep -q 'Soft blocked: yes'; then echo on; else echo off; fi"]
        stdout: StdioCollector { onStreamFinished: root.planeActive = this.text.trim()==="on" }
    }
    onIsOpenChanged: {
        if(isOpen) { planeCheck.running=true; hibernateCheck.running=true; currentIndex=0; confirmIndex=-1; Qt.callLater(()=> mainCol.forceActiveFocus()) }
    }
}
