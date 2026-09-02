import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../../theme"

WlrLayershell {
    id: root
    property bool isOpen: false
    property bool filterActive: false
    signal requestToggle(string name)
    function open(){ isOpen=true }
    function close(){ isOpen=false; filterActive=false }
    function toggle(){ if(isOpen) close(); else open() }

    anchors { top:true; bottom:true; left:true; right:true }
    color: "transparent"
    visible: isOpen
    keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore
    Rectangle { anchors.fill: parent; color: Theme.overlay; MouseArea { anchors.fill: parent; onClicked: root.close() } }

    Rectangle {
        width: 600
        height: Math.min(560, mainCol.implicitHeight + Theme.padL * 2)
        anchors.centerIn: parent
        radius: Theme.roundingLauncher
        color: Theme.bgLauncher
        border.width: 1
        border.color: Theme.borderActive
        clip: true
        ColumnLayout {
            id: mainCol
            anchors.fill: parent
            anchors.margins: Theme.padL
            spacing: Theme.gapM
            Text { text: "Control Center"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fgMuted; font.capitalization: Font.AllUppercase; font.letterSpacing: 1.2 }
            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border }

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.gapM
                Rectangle {
                    visible: root.filterActive
                    Layout.fillWidth: true
                    Layout.preferredHeight: 40
                    radius: Theme.roundingItem
                    color: Theme.bgActive
                    border.color: filterField.activeFocus ? Theme.borderSelected : Theme.border
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
                            cursorDelegate: Rectangle {
                                width: Math.max(6, Math.round(parent.font.pixelSize * 0.65))
                                height: Math.round(parent.font.pixelSize * 1.5)
                                color: Theme.fg
                            }
                            onTextChanged: { root.filteredModel = root.filteredEntries(); gridView.currentIndex = 0; gridView.positionViewAtIndex(0, GridView.Contain) }
                            Keys.onEscapePressed: { root.filterActive = false; Qt.callLater(()=> gridView.forceActiveFocus()) }
                            Keys.onReturnPressed: root.dispatch()
                            Keys.onEnterPressed: root.dispatch()
                        }
                    }
                }
                Text {
                    visible: !root.filterActive
                    text: "j/k h/l move · Enter open · / filter · Esc close"
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    color: Theme.fgDim
                    Layout.fillWidth: true
                }
            }

            GridView {
                id: gridView
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(4, Math.max(1, Math.ceil(root.filteredModel.length / 2))) * 84
                cellWidth: Math.floor(gridView.width / 2)
                cellHeight: 84
                clip: true
                model: root.filteredModel
                currentIndex: 0
                focus: true
                delegate: Item {
                    required property var modelData
                    required property int index
                    width: gridView.cellWidth
                    height: gridView.cellHeight
                    Rectangle {
                        anchors.centerIn: parent
                        width: gridView.cellWidth - Theme.gapM
                        height: gridView.cellHeight - 10
                        radius: Theme.roundingItem
                        color: index === gridView.currentIndex ? Theme.bgSelected : (ma.containsMouse ? Theme.bgHover : "transparent")
                        border.color: index === gridView.currentIndex ? Theme.borderSelected : Theme.border
                        border.width: index === gridView.currentIndex ? 2 : 1
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Theme.padM
                            anchors.rightMargin: Theme.padM
                            spacing: Theme.gapM
                            Rectangle {
                                width: 40; height: 40
                                radius: 8
                                color: Theme.bgBar
                                Text { anchors.centerIn: parent; text: modelData.icon; font.family: Theme.fontFamily; font.pixelSize: 18; color: Theme.fg }
                            }
                            Text {
                                text: modelData.label
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeLauncher
                                font.weight: Theme.fontWeightMedium
                                color: Theme.fg
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                            }
                            Text {
                                text: modelData.key
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.fgMuted
                                horizontalAlignment: Text.AlignRight
                            }
                        }
                    }
                    MouseArea {
                        id: ma
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { gridView.currentIndex=index; root.dispatch() }
                    }
                }
                Keys.onPressed: (e)=>{
                    if(e.key===Qt.Key_Escape) { root.close(); e.accepted=true }
                    else if(e.key===Qt.Key_J || e.key===Qt.Key_Down) { currentIndex=Math.min(count-1, currentIndex+2); positionViewAtIndex(currentIndex, GridView.Contain); e.accepted=true }
                    else if(e.key===Qt.Key_K || e.key===Qt.Key_Up) { currentIndex=Math.max(0, currentIndex-2); positionViewAtIndex(currentIndex, GridView.Contain); e.accepted=true }
                    else if(e.key===Qt.Key_H || e.key===Qt.Key_Left) { currentIndex=Math.max(0, currentIndex-1); positionViewAtIndex(currentIndex, GridView.Contain); e.accepted=true }
                    else if(e.key===Qt.Key_L || e.key===Qt.Key_Right) { currentIndex=Math.min(count-1, currentIndex+1); positionViewAtIndex(currentIndex, GridView.Contain); e.accepted=true }
                    else if(e.key===Qt.Key_Home) { currentIndex=0; positionViewAtIndex(0, GridView.Contain); e.accepted=true }
                    else if(e.key===Qt.Key_End) { currentIndex=count-1; positionViewAtIndex(count-1, GridView.Contain); e.accepted=true }
                    else if(e.key===Qt.Key_Return || e.key===Qt.Key_Enter) { root.dispatch(); e.accepted=true }
                    else if(e.text==="/") { root.filterActive=true; Qt.callLater(()=> filterField.forceActiveFocus()); e.accepted=true }
                }
            }
        }
    }
    onIsOpenChanged: {
        if(isOpen) { root.filterActive=false; filterField.text=""; root.filteredModel = entries; gridView.currentIndex=0; Qt.callLater(()=> gridView.forceActiveFocus()) }
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
    function fuzzyMatch(text, q){
        let i = 0
        for (const ch of q) {
            i = text.indexOf(ch, i)
            if (i === -1) return false
            i++
        }
        return true
    }
    function score(e, q){
        const label = e.label.toLowerCase()
        const key = e.key.toLowerCase()
        if (label.indexOf(q) === 0) return 3
        if (label.indexOf(q) !== -1 || key.indexOf(q) !== -1) return 2
        if (fuzzyMatch(label, q)) return 1
        return -1
    }
    function filteredEntries(){
        const q = filterField ? filterField.text.trim().toLowerCase() : ""
        if(!q) return entries
        const scored = []
        for (const e of entries) {
            const s = score(e, q)
            if (s > 0) scored.push({ label: e.label, key: e.key, icon: e.icon, target: e.target, score: s })
        }
        scored.sort((a, b) => b.score - a.score)
        return scored
    }
    function dispatch(){
        const m = root.filteredModel[gridView.currentIndex]
        if(!m) return
        root.close()
        root.requestToggle(m.target)
    }
}