import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../../theme"

PanelWindow {
    id: root
    property bool isOpen: false
    function open(){ isOpen=true }
    function close(){ isOpen=false }
    function toggle(){ if(isOpen) close(); else open() }

    anchors { top:true; bottom:true; left:true; right:true }
    onIsOpenChanged: if(isOpen) { refresh(); Qt.callLater(()=> mainCol.forceActiveFocus()) }
    color: "transparent"
    visible: isOpen
    focusable: true
    exclusionMode: ExclusionMode.Ignore
    Rectangle { anchors.fill: parent; color: Theme.overlay; MouseArea { anchors.fill: parent; onClicked: root.close() } }

    Rectangle {
        width: 640
        height: Math.min(640, mainCol.implicitHeight + Theme.padL*2)
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
            Text { text: "Display"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fgMuted; font.capitalization: Font.AllUppercase; font.letterSpacing: 1.2 }
            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border }

            Text { text: "Current"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fgMuted }
            ListView {
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(160, contentHeight)
                clip: true
                spacing: 4
                model: monitors
                delegate: Rectangle {
                    required property var modelData
                    width: parent.width
                    height: 56
                    radius: Theme.roundingItem
                    color: modelData.focused ? Theme.bgSelected : Theme.bgActive
                    border.color: modelData.focused ? Theme.borderSelected : Theme.border
                    border.width: modelData.focused ? 2 : 1
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.padM
                        anchors.rightMargin: Theme.padM
                        spacing: Theme.gapM
                        Rectangle {
                            width: 36; height: 36
                            radius: 8
                            color: modelData.focused ? Theme.bgSelected : Theme.bgBar
                            Text { anchors.centerIn: parent; text: Icons.display; font.family: Theme.fontFamily; font.pixelSize: 16; color: modelData.focused ? Theme.fg : Theme.fgMuted }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            Text { text: modelData.name + (modelData.focused ? " · focused" : ""); font.family: Theme.fontFamily; font.pixelSize: 13; font.weight: Theme.fontWeightMedium; color: Theme.fg }
                            Text { text: modelData.mode + " · scale " + modelData.scale + " · " + modelData.pos; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fgMuted }
                        }
                        Rectangle {
                            visible: monitors.length >=2
                            width: 90; height: 30
                            radius: 6
                            color: Theme.bgBar
                            border.color: Theme.critical
                            border.width: 1
                            Text { anchors.centerIn: parent; text: "Disconnect"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.critical }
                            MouseArea { anchors.fill: parent; onClicked: {
                                if(monitors.length<2){ errorText.text="Cannot disable the only monitor"; return }
                                disconnectProc.command = ["hyprctl","keyword","monitor", modelData.name+",disable"]
                                disconnectProc.running=true
                            } }
                        }
                    }
                }
            }

            Text { text: "Available"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fgMuted }
            ListView {
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(140, contentHeight)
                clip: true
                spacing: 4
                model: availableMonitors
                delegate: Rectangle {
                    required property var modelData
                    width: parent.width
                    height: 52
                    radius: Theme.roundingItem
                    color: Theme.bgHover
                    border.color: Theme.border
                    border.width: 1
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.padM
                        anchors.rightMargin: Theme.padM
                        spacing: Theme.gapM
                        Text { text: modelData.name; font.family: Theme.fontFamily; font.pixelSize: 13; color: Theme.fg; font.weight: Theme.fontWeightMedium }
                        Text { text: modelData.mode; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fgMuted; Layout.fillWidth: true }
                        Rectangle {
                            width: 70; height: 28
                            radius: 6
                            color: Theme.bgActive
                            border.color: Theme.borderActive
                            border.width: 1
                            Text { anchors.centerIn: parent; text: "Extend"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fg }
                            MouseArea { anchors.fill: parent; onClicked: connectProc("extend", modelData.name) }
                        }
                        Rectangle {
                            width: 80; height: 28
                            radius: 6
                            color: Theme.bgActive
                            Text { anchors.centerIn: parent; text: "Duplicate"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fg }
                            MouseArea { anchors.fill: parent; onClicked: connectProc("duplicate", modelData.name) }
                        }
                    }
                }
            }
            Text { visible: availableMonitors.length===0; text: "No additional outputs detected"; font.family: Theme.fontFamily; font.pixelSize: 12; color: Theme.fgDim; Layout.alignment: Qt.AlignHCenter }

            ColumnLayout {
                visible: monitors.length >=2
                Layout.fillWidth: true
                spacing: Theme.gapS
                Text { text: "Orientation"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fgMuted }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.gapS
                    Repeater {
                        model: ["Left","Right","Top","Bottom"]
                        delegate: Rectangle {
                            required property string modelData
                            Layout.fillWidth: true
                            height: 32
                            radius: Theme.roundingItem
                            color: ma.containsMouse ? Theme.bgHover : Theme.bgActive
                            border.color: Theme.border
                            border.width: 1
                            Text { anchors.centerIn: parent; text: modelData; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fg }
                            MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; onClicked: orient(modelData.toLowerCase()) }
                        }
                    }
                }
            }

            Text { id: errorText; visible: text.length>0; color: Theme.critical; font.family: Theme.fontFamily; font.pixelSize: 11 }
            RowLayout {
                Layout.fillWidth: true
                Rectangle {
                    width: 100; height: 32
                    radius: Theme.roundingItem
                    color: Theme.bgHover
                    border.color: Theme.border
                    border.width: 1
                    Text { anchors.centerIn: parent; text: "Refresh"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fg }
                    MouseArea { anchors.fill: parent; onClicked: refresh() }
                }
                Item { Layout.fillWidth: true }
                Text { text: "r refresh · / filter · Esc close"; font.family: Theme.fontFamily; font.pixelSize: 10; color: Theme.fgDim }
            }
        }
        Keys.onPressed: (e)=>{
            if(e.key===Qt.Key_Escape) root.close()
            else if(e.text==="/") { e.accepted=true }
            else if(e.key===Qt.Key_R) { refresh(); e.accepted=true }
        }
    }
    property var monitors: []
    property var availableMonitors: []
    function refresh(){
        monitorsProc.running=true
        allMonitorsProc.running=true
        errorText.text=""
    }
    function connectProc(mode, name){
        let cmd=[]
        if(mode==="extend") cmd=["hyprctl","keyword","monitor", name+",preferred,auto,1"]
        else if(mode==="duplicate") {
            const primary = monitors.length>0 ? monitors[0].name : name
            cmd=["hyprctl","keyword","monitor", name+",preferred,auto,1,mirror,"+primary]
        } else if(mode==="only") {
            for(let i=0;i<monitors.length;i++) if(monitors[i].name!==name) { disconnectProc.command=["hyprctl","keyword","monitor", monitors[i].name+",disable"]; disconnectProc.running=true }
            cmd=["hyprctl","keyword","monitor", name+",preferred,auto,1"]
        }
        connectCmdProc.command=cmd
        connectCmdProc.running=true
    }
    function orient(dir){
        if(availableMonitors.length===0 || monitors.length===0) return
        const name = availableMonitors[0].name
        let pos="auto"
        if(dir==="left") pos="-1920x0"
        else if(dir==="right") pos="1920x0"
        else if(dir==="top") pos="0x-1080"
        else if(dir==="bottom") pos="0x1080"
        connectCmdProc.command=["hyprctl","keyword","monitor", name+",preferred,"+pos+",1"]
        connectCmdProc.running=true
    }
    property Process monitorsProc: Process {
        command: ["hyprctl","monitors","-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const arr=JSON.parse(this.text)
                    monitors = arr.map(m=> ({ name: m.name, mode: (m.width+"x"+m.height+"@"+m.refreshRate), scale: m.scale, pos: m.x+"x"+m.y, focused: m.focused }))
                } catch(e){ errorText.text="hyprctl failed"; monitors=[] }
            }
        }
    }
    property Process allMonitorsProc: Process {
        command: ["sh","-c","hyprctl monitors all -j 2>/dev/null || hyprctl monitors -j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const arr=JSON.parse(this.text)
                    const currentNames = monitors.map(m=>m.name)
                    const avail = arr.filter(m=> currentNames.indexOf(m.name)===-1 || m.disabled)
                    availableMonitors = avail.map(m=> ({ name: m.name, mode: m.width ? (m.width+"x"+m.height) : "preferred" }))
                } catch(e){ availableMonitors=[] }
            }
        }
    }
    property Process connectCmdProc: Process { stdout: StdioCollector { onStreamFinished: refresh() } }
    property Process disconnectProc: Process { stdout: StdioCollector { onStreamFinished: refresh() } }
}
