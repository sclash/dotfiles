import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import "../../theme"
import "../../services"

PanelWindow {
    id: root
    property bool isOpen: false
    property var navItems: []
    property int selIndex: 0
    function open(){ isOpen=true }
    function close(){ isOpen=false }
    function toggle(){ if(isOpen) close(); else open() }

    anchors { top:true; bottom:true; left:true; right:true }
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
            Text { text: "Bluetooth"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fgMuted; font.capitalization: Font.AllUppercase; font.letterSpacing: 1.2 }
            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border }

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.gapM
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 36
                    radius: Theme.roundingItem
                    color: Theme.bgActive
                    border.color: Theme.border
                    border.width: 1
                    visible: filterActive
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.padM
                        Text { text: Icons.search; font.family: Theme.fontFamily; font.pixelSize: 14; color: Theme.fgMuted }
                        TextField {
                            id: filterField
                            Layout.fillWidth: true
                            placeholderText: "Filter…"
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            color: Theme.fg
                            placeholderTextColor: Theme.fgDim
                            background: null
                            onTextChanged: updateFilter()
                        }
                    }
                }
                Rectangle {
                    width: 110; height: 36
                    radius: Theme.roundingItem
                    readonly property bool isSel: root.navItems[root.selIndex] !== undefined && root.navItems[root.selIndex].kind === "power"
                    color: BluetoothService.powered ? Theme.bgSelected : Theme.bgHover
                    border.color: isSel ? Theme.accent : (BluetoothService.powered ? Theme.borderSelected : Theme.border)
                    border.width: isSel ? 2 : 1
                    Text { anchors.centerIn: parent; text: BluetoothService.powered ? "Power Off" : "Power On"; font.family: Theme.fontFamily; font.pixelSize: 12; color: BluetoothService.powered ? Theme.fg : Theme.fgMuted; font.weight: Theme.fontWeightMedium }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: BluetoothService.togglePower() }
                }
            }

            Text { text: "Connected"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fgMuted }
            ListView {
                id: connectedList
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(140, contentHeight)
                clip: true
                spacing: 4
                model: BluetoothService.devices.filter(d=> d.connected)
                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    width: parent.width
                    height: 48
                    radius: Theme.roundingItem
                    readonly property bool isSel: { const it = root.navItems[root.selIndex]; return it !== undefined && it.kind === "connected" && it.idx === index }
                    color: isSel ? Theme.bgSelected : Theme.bgActive
                    border.color: isSel ? Theme.accent : (BluetoothService.connectedCount>0 ? Theme.borderSelected : Theme.border)
                    border.width: isSel ? 2 : 1
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.padM
                        anchors.rightMargin: Theme.padM
                        spacing: Theme.gapM
                        Rectangle {
                            width: 32; height: 32
                            radius: 8
                            color: Theme.bgBar
                            Text { anchors.centerIn: parent; text: Icons.bluetoothOn; font.family: Theme.fontFamily; font.pixelSize: 16; color: Theme.fg }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            Text { text: modelData.alias; font.family: Theme.fontFamily; font.pixelSize: 13; font.weight: Theme.fontWeightMedium; color: Theme.fg }
                            Text { text: modelData.address; font.family: Theme.fontFamily; font.pixelSize: 10; color: Theme.fgMuted }
                        }
                        Rectangle {
                            width: 80; height: 28
                            radius: 6
                            color: Theme.bgBar
                            border.color: Theme.warning
                            border.width: 1
                            Text { anchors.centerIn: parent; text: "Disconnect"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.warning }
                            MouseArea { anchors.fill: parent; onClicked: BluetoothService.disconnect(modelData.address) }
                        }
                    }
                }
            }
            Text { visible: BluetoothService.devices.filter(d=> d.connected).length===0; text: "No connected devices"; font.family: Theme.fontFamily; font.pixelSize: 12; color: Theme.fgDim; horizontalAlignment: Text.AlignHCenter; Layout.fillWidth: true }

            Text { text: "Known"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fgMuted }
            ListView {
                id: knownList
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(140, contentHeight)
                clip: true
                spacing: 4
                model: BluetoothService.devices.filter(d=> d.paired && !d.connected)
                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    width: parent.width
                    height: 44
                    radius: Theme.roundingItem
                    readonly property bool isSel: { const it = root.navItems[root.selIndex]; return it !== undefined && it.kind === "known" && it.idx === index }
                    color: isSel ? Theme.bgActive : (ma.containsMouse ? Theme.bgHover : "transparent")
                    border.color: isSel ? Theme.accent : "transparent"
                    border.width: 1
                    MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true }
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.padM
                        anchors.rightMargin: Theme.padM
                        spacing: Theme.gapM
                        Text { text: "●"; font.pixelSize: 8; color: Theme.success }
                        ColumnLayout {
                            Layout.fillWidth: true
                            Text { text: modelData.alias || modelData.address; font.family: Theme.fontFamily; font.pixelSize: 13; color: Theme.fg; elide: Text.ElideRight }
                            Text { text: modelData.address; font.family: Theme.fontFamily; font.pixelSize: 10; color: Theme.fgMuted }
                        }
                        Rectangle {
                            width: 70; height: 28
                            radius: 6
                            color: Theme.bgActive
                            border.color: Theme.borderActive
                            border.width: 1
                            Text { anchors.centerIn: parent; text: "Connect"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fg }
                            MouseArea { anchors.fill: parent; onClicked: BluetoothService.connect(modelData.address) }
                        }
                        Text { text: "Forget"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.critical; MouseArea { anchors.fill: parent; onClicked: BluetoothService.forget(modelData.address) } }
                    }
                }
            }
            Text { visible: BluetoothService.devices.filter(d=> d.paired).length===0; text: "No known devices — scan to discover"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fgDim; Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter }

            RowLayout {
                Layout.fillWidth: true
                Text { text: "Nearby"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fgMuted; Layout.fillWidth: true }
                Rectangle {
                    width: 90; height: 32
                    radius: Theme.roundingItem
                    readonly property bool isSel: root.navItems[root.selIndex] !== undefined && root.navItems[root.selIndex].kind === "scan"
                    color: BluetoothService.scanning ? Theme.bgActive : Theme.bgHover
                    border.color: isSel ? Theme.accent : Theme.border
                    border.width: isSel ? 2 : 1
                    Text { anchors.centerIn: parent; text: BluetoothService.scanning ? "Stop scan" : "Scan"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fg }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: BluetoothService.scanning ? BluetoothService.stopScan() : BluetoothService.startScan() }
                }
            }
            ListView {
                id: nearbyList
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(140, contentHeight)
                clip: true
                spacing: 4
                model: filteredScan
                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    width: parent.width
                    height: 44
                    radius: Theme.roundingItem
                    readonly property bool isSel: { const it = root.navItems[root.selIndex]; return it !== undefined && it.kind === "nearby" && it.idx === index }
                    color: isSel ? Theme.bgActive : (ma2.containsMouse ? Theme.bgHover : "transparent")
                    border.color: isSel ? Theme.accent : "transparent"
                    border.width: 1
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.padM
                        anchors.rightMargin: Theme.padM
                        spacing: Theme.gapM
                        Text { text: modelData.alias || modelData.address; font.family: Theme.fontFamily; font.pixelSize: 13; color: Theme.fg; Layout.fillWidth: true; elide: Text.ElideRight }
                        Text { text: modelData.address; font.family: Theme.fontFamily; font.pixelSize: 10; color: Theme.fgMuted }
                        Rectangle {
                            width: 64; height: 26
                            radius: 6
                            color: Theme.bgActive
                            border.color: Theme.borderActive
                            border.width: 1
                            Text { anchors.centerIn: parent; text: "Pair"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fg }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: BluetoothService.pairAndConnect(modelData.address) }
                        }
                    }
                    MouseArea { id: ma2; anchors.fill: parent; hoverEnabled: true; onClicked: BluetoothService.pairAndConnect(modelData.address) }
                }
            }
            Text { visible: filteredScan.length===0; text: BluetoothService.scanning ? "Scanning for nearby devices…" : "Nothing discovered yet — press Scan"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fgDim; Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter }
            Text { text: "/ filter · j/k move · Enter act · d disconnect · r rescan · Esc close"; font.family: Theme.fontFamily; font.pixelSize: 10; color: Theme.fgDim; Layout.alignment: Qt.AlignHCenter }
        }
        Keys.onPressed: (e)=>{
            if(e.key===Qt.Key_Escape) {
                if(filterActive){ filterActive=false; filterField.text=""; mainCol.forceActiveFocus(); e.accepted=true }
                else root.close()
            }
            else if(e.key===Qt.Key_J || e.key===Qt.Key_Down) { root.moveSel(1); e.accepted=true }
            else if(e.key===Qt.Key_K || e.key===Qt.Key_Up) { root.moveSel(-1); e.accepted=true }
            else if(e.key===Qt.Key_Return || e.key===Qt.Key_Enter) { root.activate(); e.accepted=true }
            else if(e.key===Qt.Key_D) { root.disconnectFocused(); e.accepted=true }
            else if(e.text==="/") { filterActive=true; filterField.forceActiveFocus(); e.accepted=true }
            else if(e.key===Qt.Key_R) { BluetoothService.scanning ? BluetoothService.stopScan() : BluetoothService.startScan(); e.accepted=true }
        }
    }
    property bool filterActive: false
    property var filteredScan: []
    function updateFilter(){
        const q = filterField ? filterField.text.toLowerCase() : ""
        // Nearby = live scan results + known-but-unpaired devices
        const seen = {}
        let avail = []
        BluetoothService.nearby.concat(BluetoothService.devices.filter(d=> !d.paired && !d.connected)).forEach(d=>{
            if (!d || seen[d.address]) return
            seen[d.address] = 1
            avail.push(d)
        })
        if (q) avail = avail.filter(d=> (d.alias && d.alias.toLowerCase().indexOf(q)!==-1) || d.address.toLowerCase().indexOf(q)!==-1)
        filteredScan = avail.slice(0, 20)
        updateNav()
    }
    function updateNav(){
        const items=[]
        items.push({kind:"power"})
        const devs = BluetoothService.devices
        const connected = devs.filter(d=> d.connected)
        const known = devs.filter(d=> d.paired && !d.connected)
        const nearby = filteredScan
        for(let i=0;i<connected.length;i++) items.push({kind:"connected", idx:i})
        for(let i=0;i<known.length;i++) items.push({kind:"known", idx:i})
        items.push({kind:"scan"})
        for(let i=0;i<nearby.length;i++) items.push({kind:"nearby", idx:i})
        navItems=items
        selIndex=Math.max(0, Math.min(selIndex, items.length-1))
    }
    function moveSel(delta){
        const n = navItems.length
        if(n===0) return
        selIndex = Math.max(0, Math.min(n-1, selIndex+delta))
        ensureVisible()
        Qt.callLater(()=> mainCol.forceActiveFocus())
    }
    function ensureVisible(){
        const it = navItems[selIndex]
        if(!it) return
        if(it.kind==="connected" && connectedList) connectedList.positionViewAtIndex(it.idx, ListView.Contain)
        else if(it.kind==="known" && knownList) knownList.positionViewAtIndex(it.idx, ListView.Contain)
        else if(it.kind==="nearby" && nearbyList) nearbyList.positionViewAtIndex(it.idx, ListView.Contain)
    }
    function disconnectFocused(){
        const it = navItems[selIndex]
        if(it && it.kind==="connected") {
            const d = BluetoothService.devices.filter(x=> x.connected)[it.idx]
            if(d) BluetoothService.disconnect(d.address)
        }
    }
    function activate(){
        const it = navItems[selIndex]
        if(!it) return
        if(it.kind==="power") BluetoothService.togglePower()
        else if(it.kind==="scan") { BluetoothService.scanning ? BluetoothService.stopScan() : BluetoothService.startScan() }
        else if(it.kind==="connected") disconnectFocused()
        else if(it.kind==="known") { const d = BluetoothService.devices.filter(x=> x.paired && !x.connected)[it.idx]; if(d) BluetoothService.connect(d.address) }
        else if(it.kind==="nearby") { const d = filteredScan[it.idx]; if(d) BluetoothService.pairAndConnect(d.address) }
    }
    Connections { target: BluetoothService; function onDataUpdated(){ updateFilter() } }
    Connections { target: BluetoothService; function onDevicesChanged(){ updateFilter() } }
    Component.onCompleted: updateFilter()
    onIsOpenChanged: if(isOpen) { selIndex=0; BluetoothService.startScan(); updateFilter(); Qt.callLater(()=> mainCol.forceActiveFocus()) } else { BluetoothService.stopScan() }
}
