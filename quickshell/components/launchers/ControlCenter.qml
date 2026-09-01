import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import "../../theme"

PanelWindow {
    id: root
    property bool isOpen: false
    signal requestToggle(string name)
    function open(){ isOpen=true }
    function close(){ isOpen=false }
    function toggle(){ if(isOpen) close(); else open() }

    anchors { top:true; bottom:true; left:true; right:true }
    color: "transparent"
    visible: isOpen
    focusable: true
    exclusionMode: ExclusionMode.Ignore
    Rectangle { anchors.fill: parent; color: Theme.overlay; MouseArea { anchors.fill: parent; onClicked: root.close() } }
    onIsOpenChanged: if(isOpen) { filterField.text=""; root.filteredModel = entries; gridView.currentIndex=0; Qt.callLater(()=> filterField.forceActiveFocus()) }

    Rectangle {
        width: 600
        anchors.centerIn: parent
        radius: Theme.roundingLauncher
        color: Theme.bgLauncher
        border.width: 1
        border.color: Theme.borderActive
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Theme.padL
            spacing: Theme.gapM
            Text { text: "Control Center"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fgMuted; font.capitalization: Font.AllUppercase; font.letterSpacing: 1.2 }
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.gapM
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 40
                    radius: Theme.roundingItem
                    color: Theme.bgActive
                    border.color: filterField.activeFocus ? Theme.fg : Theme.border
                    border.width: 1
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.padM
                        anchors.rightMargin: Theme.padM
                        Text { text: Icons.search; font.family: Theme.fontFamily; font.pixelSize: 16; color: Theme.fgMuted }
                        TextField {
                            id: filterField
                            Layout.fillWidth: true
                            placeholderText: "Type to filter…"
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            color: Theme.fg
                            placeholderTextColor: Theme.fgDim
                            background: null
                            onTextChanged: { root.filteredModel = root.filteredEntries(); gridView.currentIndex = 0 }
                            Keys.onEscapePressed: root.close()
                            Keys.onPressed: (e)=>{
                                if(e.key===Qt.Key_Down || e.key===Qt.Key_J) { gridView.forceActiveFocus(); gridView.currentIndex = Math.min(gridView.count-1, gridView.currentIndex+2); e.accepted=true }
                                else if(e.key===Qt.Key_Up || e.key===Qt.Key_K) { gridView.forceActiveFocus(); gridView.currentIndex = Math.max(0, gridView.currentIndex-2); e.accepted=true }
                                else if(e.key===Qt.Key_Return || e.key===Qt.Key_Enter) { root.dispatch(); e.accepted=true }
                            }
                        }
                    }
                }
            }
            GridView {
                id: gridView
                Layout.fillWidth: true
                Layout.preferredHeight: 340
                cellWidth: 304
                cellHeight: 86
                clip: true
                model: root.filteredModel
                currentIndex: 0
                focus: true
                highlight: Rectangle { color: Theme.bgActive; radius: Theme.roundingItem; border.color: Theme.fg; border.width: 2 }
                highlightMoveDuration: Theme.durationFast
                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    width: 294
                    height: 78
                    radius: Theme.roundingItem
                    color: GridView.isCurrentItem ? Theme.bgActive : (ma.containsMouse ? Theme.bgHover : "transparent")
                    border.color: GridView.isCurrentItem ? Theme.fg : Theme.border
                    border.width: GridView.isCurrentItem ? 2 : 1
                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: Theme.padM
                        spacing: Theme.gapM
                        Rectangle {
                            width: 44; height: 44
                            radius: 10
                            color: Theme.bgBar
                            Text { anchors.centerIn: parent; text: modelData.icon; font.family: Theme.fontFamily; font.pixelSize: 22; color: GridView.isCurrentItem ? Theme.fg : Theme.fg }
                        }
                        ColumnLayout {
                            spacing: 2
                            Layout.fillWidth: true
                            Text { text: modelData.label; font.family: Theme.fontFamily; font.pixelSize: 14; font.weight: Theme.fontWeightMedium; color: Theme.fg }
                            Text { text: modelData.key; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fgMuted }
                        }
                    }
                    MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { gridView.currentIndex=index; root.dispatch() } }
                }
                Keys.onPressed: (e)=>{
                    if(e.key===Qt.Key_J || e.key===Qt.Key_Down) { currentIndex=Math.min(count-1, currentIndex+2); e.accepted=true }
                    else if(e.key===Qt.Key_K || e.key===Qt.Key_Up) { currentIndex=Math.max(0, currentIndex-2); e.accepted=true }
                    else if(e.key===Qt.Key_H || e.key===Qt.Key_Left) { currentIndex=Math.max(0, currentIndex-1); e.accepted=true }
                    else if(e.key===Qt.Key_L || e.key===Qt.Key_Right) { currentIndex=Math.min(count-1, currentIndex+1); e.accepted=true }
                    else if(e.key===Qt.Key_Return || e.key===Qt.Key_Enter) { root.dispatch(); e.accepted=true }
                    else if(e.key===Qt.Key_Escape) root.close()
                    else if(e.text==="/") { filterField.forceActiveFocus(); e.accepted=true }
                }
            }
            Text { text: "j/k/h/l to move · Enter to open · / to filter · Esc to close"; font.family: Theme.fontFamily; font.pixelSize: 10; color: Theme.fgDim; Layout.alignment: Qt.AlignHCenter }
        }
        Keys.onEscapePressed: root.close()
    }

    property var entries: [
        { label: "Network", key: "SUPER+w", icon: Icons.network, target: "network" },
        { label: "Bluetooth", key: "SUPER+b", icon: Icons.bluetoothOn, target: "bluetooth" },
        { label: "Audio", key: "SUPER+a", icon: Icons.audioVolume, target: "audio" },
        { label: "Display", key: "SUPER+d", icon: Icons.display, target: "display" },
        { label: "Notifications", key: "SUPER+SHIFT+A", icon: Icons.notification, target: "notification" },
        { label: "App Launcher", key: "SUPER+r", icon: Icons.search, target: "app" },
        { label: "Shutdown", key: "SUPER+q", icon: Icons.power, target: "shutdown" },
        { label: "Key Hints", key: "SUPER+k", icon: Icons.key, target: "keys" }
    ]
    property var filteredModel: entries
    function filteredEntries(){
        const q = filterField ? filterField.text.toLowerCase() : ""
        if(!q) return entries
        return entries.filter(e=> e.label.toLowerCase().indexOf(q)!==-1 || e.key.toLowerCase().indexOf(q)!==-1)
    }
    function dispatch(){
        const list = root.filteredModel
        const m = list[gridView.currentIndex]
        if(!m) return
        root.close()
        root.requestToggle(m.target)
    }
}
