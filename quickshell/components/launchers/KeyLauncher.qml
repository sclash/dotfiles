import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import "../../theme"

PanelWindow {
    id: root
    property bool isOpen: false
    function open(){ isOpen=true }
    function close(){ isOpen=false }
    function toggle(){ if(isOpen) close(); else open() }

    anchors { top:true; bottom:true; left:true; right:true }
    onIsOpenChanged: if(isOpen) Qt.callLater(()=> filterField.forceActiveFocus())
    color: "transparent"
    visible: isOpen
    focusable: true
    exclusionMode: ExclusionMode.Ignore
    Rectangle { anchors.fill: parent; color: Theme.overlay; MouseArea { anchors.fill: parent; onClicked: root.close() } }

    Rectangle {
        width: 640
        height: Math.min(560, col.implicitHeight + Theme.padL*2)
        anchors.centerIn: parent
        radius: Theme.roundingLauncher
        color: Theme.bgLauncher
        border.width: 1
        border.color: Theme.borderActive
        ColumnLayout {
            id: col
            anchors.fill: parent
            anchors.margins: Theme.padL
            spacing: Theme.gapM
            focus: true
            Text { text: "Key Hints"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fgMuted; font.capitalization: Font.AllUppercase; font.letterSpacing: 1.2 }
            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border }
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.gapM
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 38
                    radius: Theme.roundingItem
                    color: Theme.bgActive
                    border.color: filterField.activeFocus ? Theme.fg : Theme.border
                    border.width: 1
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.padM
                        Text { text: Icons.search; font.family: Theme.fontFamily; font.pixelSize: 16; color: Theme.fgMuted }
                        TextField {
                            id: filterField
                            Layout.fillWidth: true
                            placeholderText: "Filter keys…"
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            color: Theme.fg
                            placeholderTextColor: Theme.fgDim
                            background: null
                            onTextChanged: listView.model = filtered()
                        }
                    }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.gapL
                Text { text: "KEY"; font.family: Theme.fontFamily; font.pixelSize: 10; color: Theme.fgMuted; font.weight: Theme.fontWeightMedium; Layout.preferredWidth: 150 }
                Text { text: "ACTION"; font.family: Theme.fontFamily; font.pixelSize: 10; color: Theme.fgMuted; font.weight: Theme.fontWeightMedium; Layout.fillWidth: true }
                Text { text: ""; Layout.preferredWidth: 80 }
            }
            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border }
            ListView {
                id: listView
                Layout.fillWidth: true
                Layout.preferredHeight: 360
                clip: true
                spacing: 2
                model: bindings
                currentIndex: 0
                highlight: Rectangle { color: Theme.bgActive; radius: Theme.roundingItem; border.color: Theme.fg; border.width: 1 }
                highlightMoveDuration: Theme.durationFast
                delegate: Rectangle {
                    required property var modelData
                    width: listView.width
                    height: 36
                    radius: Theme.roundingItem
                    color: ListView.isCurrentItem ? Theme.bgActive : "transparent"
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.padM
                        anchors.rightMargin: Theme.padM
                        spacing: Theme.gapM
                        Text {
                            text: modelData.key
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            font.weight: Theme.fontWeightMedium
                            color: Theme.fg
                            Layout.preferredWidth: 150
                        }
                        Text { text: modelData.action; font.family: Theme.fontFamily; font.pixelSize: 13; color: Theme.fg; Layout.fillWidth: true }
                        Text { text: modelData.desc; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fgMuted }
                    }
                }
                Keys.onPressed: (e)=>{
                    if(e.key===Qt.Key_J || e.key===Qt.Key_Down) { currentIndex=Math.min(count-1, currentIndex+1); e.accepted=true }
                    else if(e.key===Qt.Key_K || e.key===Qt.Key_Up) { currentIndex=Math.max(0, currentIndex-1); e.accepted=true }
                    else if(e.key===Qt.Key_Escape) root.close()
                    else if(e.text==="/") { filterField.forceActiveFocus(); e.accepted=true }
                }
            }
            Text { text: "keep in sync with hyprland.lua"; font.family: Theme.fontFamily; font.pixelSize: 10; color: Theme.fgDim; font.italic: true; Layout.alignment: Qt.AlignHCenter }
        }
        Keys.onPressed: (e)=> {
            if(e.key===Qt.Key_Escape) { if(filterField.text.length>0){filterField.text=""; e.accepted=true} else root.close() }
        }
    }
    property var bindings: [
        { key: "SUPER+SPACE", action: "Control Center", desc: "meta" },
        { key: "SUPER+R", action: "App Launcher", desc: "apps" },
        { key: "SUPER+W", action: "Network", desc: "wifi" },
        { key: "SUPER+B", action: "Bluetooth", desc: "bt" },
        { key: "SUPER+A", action: "Audio", desc: "sound" },
        { key: "SUPER+D", action: "Display", desc: "monitors" },
        { key: "SUPER+SHIFT+A", action: "Notifications", desc: "bell" },
        { key: "SUPER+Q", action: "Shutdown", desc: "power" },
        { key: "SUPER+K", action: "Key Hints", desc: "this" },
        { key: "SUPER+P", action: "Perf Drawer", desc: "metrics" },
        { key: "SUPER+1..9", action: "Workspace", desc: "switch" },
        { key: "ALT+SHIFT", action: "Keyboard", desc: "layout" },
        { key: "ESC", action: "Close", desc: "dismiss" }
    ]
    function filtered(){
        const q=filterField.text.toLowerCase()
        if(!q) return bindings
        return bindings.filter(b=> b.key.toLowerCase().indexOf(q)!==-1 || b.action.toLowerCase().indexOf(q)!==-1)
    }
}
