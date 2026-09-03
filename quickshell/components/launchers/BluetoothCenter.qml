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
    property bool filterActive: false
    property bool suppressUpdate: false
    property string view: "nearby"
    property var navItems: []
    property int selIndex: 0
    function open(){ isOpen=true }
    function close(){ isOpen=false; filterActive=false }
    function toggle(){ if(isOpen) close(); else open() }

    readonly property var connectedDevice: BluetoothService.devices.find(d=> d.connected) || null

    anchors { top:true; bottom:true; left:true; right:true }
    color: "transparent"
    visible: isOpen
    keyboardFocus: WlrKeyboardFocus.Exclusive
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
        clip: true
        Flickable {
            id: scrollView
            anchors.fill: parent
            anchors.margins: Theme.padL
            clip: true
            contentWidth: width
            contentHeight: mainCol.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar {
                policy: ScrollBar.AsNeeded
                width: 4
                background: Rectangle { color: "transparent" }
                contentItem: Rectangle { color: Theme.borderActive; radius: 2 }
            }
            ColumnLayout {
                id: mainCol
                width: scrollView.width
                spacing: Theme.gapM
                focus: true
                Text { text: "Bluetooth"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fgMuted; font.capitalization: Font.AllUppercase; font.letterSpacing: 1.2 }
            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border }

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.gapM
                Rectangle {
                    visible: filterActive
                    Layout.fillWidth: true
                    Layout.preferredHeight: 36
                    radius: Theme.roundingItem
                    color: Theme.bgActive
                    border.color: filterField.activeFocus ? Theme.borderSelected : Theme.border
                    border.width: 1
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.padM
                        Text { text: Icons.search; font.family: Theme.fontFamily; font.pixelSize: 14; color: Theme.fgMuted }
                        TextField {
                            id: filterField
                            Layout.fillWidth: true
                            placeholderText: "command (/known) or filter…"
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
                            onTextChanged: if(!suppressUpdate) updateModels()
                            onAccepted: { filterActive=false; updateModels(); Qt.callLater(()=> mainCol.forceActiveFocus()) }
                        }
                    }
                }
                Rectangle {
                    id: powerBtn
                    width: 96; height: 32
                    radius: Theme.roundingItem
                    readonly property bool isSel: root.navItems[root.selIndex] !== undefined && root.navItems[root.selIndex].kind === "power"
                    color: isSel ? Theme.bgSelected : Theme.bgHover
                    border.color: isSel ? Theme.accent : (BluetoothService.powered ? Theme.borderSelected : Theme.border)
                    border.width: 1
                    Text { anchors.centerIn: parent; text: BluetoothService.powered ? "Power Off" : "Power On"; font.family: Theme.fontFamily; font.pixelSize: 11; font.weight: powerBtn.isSel ? Theme.fontWeightMedium : Theme.fontWeightNormal; color: powerBtn.isSel ? Theme.fgBright : (BluetoothService.powered ? Theme.fg : Theme.fgMuted) }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: BluetoothService.togglePower() }
                }
                Rectangle {
                    id: scanBtn
                    width: 80; height: 32
                    radius: Theme.roundingItem
                    readonly property bool isSel: root.navItems[root.selIndex] !== undefined && root.navItems[root.selIndex].kind === "scan"
                    color: isSel ? Theme.bgSelected : Theme.bgHover
                    border.color: isSel ? Theme.accent : Theme.border
                    border.width: 1
                    Text { anchors.centerIn: parent; text: BluetoothService.scanning ? "Stop scan" : "Scan"; font.family: Theme.fontFamily; font.pixelSize: 11; color: scanBtn.isSel ? Theme.fgBright : Theme.fg }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.toggleScan() }
                }
            }

            Text { text: "Current"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fgMuted }
            Rectangle {
                id: currentCard
                Layout.fillWidth: true
                Layout.preferredHeight: root.connectedDevice ? 40 + Theme.padM*2 : curEmpty.implicitHeight + Theme.padM*2
                radius: Theme.roundingItem
                readonly property bool isSel: root.navItems[root.selIndex] !== undefined && root.navItems[root.selIndex].kind === "current"
                color: root.connectedDevice ? Theme.bgActive : (isSel ? Theme.bgSelected : Theme.bgHover)
                border.color: isSel ? Theme.borderSelected : (root.connectedDevice ? Theme.borderSelected : Theme.border)
                border.width: 1
                RowLayout {
                    id: curRow
                    visible: root.connectedDevice !== null
                    anchors.fill: parent
                    anchors.margins: Theme.padM
                    spacing: Theme.gapM
                    Rectangle {
                        width: 40; height: 40
                        radius: 8
                        color: Theme.bgSelected
                        Text { anchors.centerIn: parent; text: Icons.bluetoothOn; font.family: Theme.fontFamily; font.pixelSize: 18; color: Theme.fg }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        Text { text: root.connectedDevice ? root.connectedDevice.alias : ""; font.family: Theme.fontFamily; font.pixelSize: 14; font.weight: Theme.fontWeightMedium; color: Theme.fg; elide: Text.ElideRight; Layout.fillWidth: true }
                        Text { text: root.connectedDevice ? root.connectedDevice.address : ""; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fgMuted; elide: Text.ElideRight; Layout.fillWidth: true }
                    }
                    Rectangle {
                        width: 90; height: 32
                        radius: Theme.roundingItem
                        color: Theme.bgBar
                        border.color: Theme.critical
                        border.width: 1
                        Text { anchors.centerIn: parent; text: "Disconnect"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.critical }
                        MouseArea { anchors.fill: parent; onClicked: root.disconnectCurrent() }
                    }
                }
            }

            Text { visible: root.view === "nearby"; text: "Nearby"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fgMuted }
            Text { visible: root.view === "nearby" && filteredNearby.length === 0; text: BluetoothService.scanning ? "Scanning for nearby devices…" : (BluetoothService.powered ? "Scan to see nearby devices" : "Power on to scan"); font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fgDim; Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter }
            ListView {
                id: nearbyList
                visible: root.view === "nearby"
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(160, contentHeight)
                clip: true
                spacing: 4
                model: filteredNearby
                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    width: parent.width
                    height: 44
                    radius: Theme.roundingItem
                    readonly property bool isSel: { const it = root.navItems[root.selIndex]; return it !== undefined && it.kind === "nearby" && it.idx === index }
                    color: isSel ? Theme.bgSelected : (ma2.containsMouse ? Theme.bgHover : "transparent")
                    border.color: isSel ? Theme.borderSelected : "transparent"
                    border.width: 1
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.padM
                        anchors.rightMargin: Theme.padM
                        spacing: Theme.gapM
                        Text { text: modelData.alias || modelData.address; font.family: Theme.fontFamily; font.pixelSize: 13; color: Theme.fg; Layout.fillWidth: true; elide: Text.ElideRight }
                        Rectangle {
                            visible: modelData.paired
                            width: 54; height: 22
                            radius: 6
                            color: Theme.bgActive
                            border.color: Theme.border
                            border.width: 1
                            Text { anchors.centerIn: parent; text: "Paired"; font.family: Theme.fontFamily; font.pixelSize: 10; color: Theme.fgMuted }
                        }
                        Text { text: modelData.address; font.family: Theme.fontFamily; font.pixelSize: 10; color: Theme.fgMuted }
                        Rectangle {
                            width: 70; height: 28
                            radius: 6
                            color: Theme.bgActive
                            border.color: Theme.borderActive
                            border.width: 1
                            Text { anchors.centerIn: parent; text: modelData.paired ? "Connect" : "Pair"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fg }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.connectNearby(modelData) }
                        }
                    }
                    MouseArea { id: ma2; anchors.fill: parent; hoverEnabled: true; onClicked: root.connectNearby(modelData) }
                }
            }

            Text { visible: root.view === "known"; text: "Known"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fgMuted }
            Text { visible: root.view === "known" && filteredKnown.length === 0; text: "No known devices — scan to discover"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fgDim; Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter }
            ListView {
                id: knownList
                visible: root.view === "known"
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(160, contentHeight)
                clip: true
                spacing: 4
                model: filteredKnown
                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    width: parent.width
                    height: 44
                    radius: Theme.roundingItem
                    readonly property bool isSel: { const it = root.navItems[root.selIndex]; return it !== undefined && it.kind === "known" && it.idx === index }
                    readonly property bool isConnected: modelData.connected
                    color: isSel ? Theme.bgSelected : (ma.containsMouse ? Theme.bgHover : "transparent")
                    border.color: isSel ? Theme.borderSelected : "transparent"
                    border.width: 1
                    MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true }
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.padM
                        anchors.rightMargin: Theme.padM
                        spacing: Theme.gapM
                        Text { text: "●"; font.pixelSize: 8; color: root.isInRange(modelData.address) ? Theme.success : Theme.fgDim }
                        Text { text: modelData.alias || modelData.address; font.family: Theme.fontFamily; font.pixelSize: 13; color: Theme.fg; Layout.fillWidth: true; elide: Text.ElideRight }
                        Text { visible: isConnected; text: "connected"; font.family: Theme.fontFamily; font.pixelSize: 10; color: Theme.success }
                        Text { text: modelData.address; font.family: Theme.fontFamily; font.pixelSize: 10; color: Theme.fgMuted }
                        Rectangle {
                            width: 76; height: 28
                            radius: 6
                            color: Theme.bgActive
                            border.color: isConnected ? Theme.warning : Theme.borderActive
                            border.width: 1
                            Text { anchors.centerIn: parent; text: isConnected ? "Disconnect" : "Connect"; font.family: Theme.fontFamily; font.pixelSize: 11; color: isConnected ? Theme.warning : Theme.fg }
                            MouseArea { anchors.fill: parent; onClicked: root.toggleKnown(modelData) }
                        }
                        Text { text: "Forget"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.critical; MouseArea { anchors.fill: parent; onClicked: root.requestForget(modelData) } }
                    }
                }
            }
            Text {
                visible: BluetoothService.lastError !== ""
                text: Icons.warning + " " + BluetoothService.lastError
                font.family: Theme.fontFamily
                font.pixelSize: 11
                color: Theme.critical
                Layout.fillWidth: true
                wrapMode: Text.Wrap
            }
            Text {
                text: {
                    if (confirmText) return confirmText
                    return "j/k · Enter act · /nearby /known · x forget · d disc · r rescan · Esc back · Esc close"
                }
                font.family: Theme.fontFamily
                font.pixelSize: 10
                color: confirmText ? Theme.critical : Theme.fgDim
                Layout.alignment: Qt.AlignHCenter
            }
        }
        }
        Keys.onPressed: (e)=>{
            if (confirmText !== "") {
                if(e.key===Qt.Key_Y) { confirmYes(); e.accepted=true; return }
                else if(e.key===Qt.Key_N || e.key===Qt.Key_Escape) { confirmText=""; e.accepted=true; return }
            }
            if(e.key===Qt.Key_Escape) {
                if(filterActive){ filterActive=false; clearFilter(); mainCol.forceActiveFocus(); e.accepted=true }
                else if(BluetoothService.scanning){ BluetoothService.stopScan(); e.accepted=true }
                else if(root.view !== "nearby"){ root.view="nearby"; updateModels(); e.accepted=true }
                else root.close()
            }
            else if(e.key===Qt.Key_J || e.key===Qt.Key_Down) { root.moveSel(1); e.accepted=true }
            else if(e.key===Qt.Key_K || e.key===Qt.Key_Up) { root.moveSel(-1); e.accepted=true }
            else if(e.key===Qt.Key_Return || e.key===Qt.Key_Enter) { root.activate(); e.accepted=true }
            else if(e.key===Qt.Key_D) { root.disconnectCurrent(); e.accepted=true }
            else if(e.key===Qt.Key_X) { root.requestForgetFocused(); e.accepted=true }
            else if(e.text==="/") { filterActive=true; filterField.forceActiveFocus(); e.accepted=true }
            else if(e.key===Qt.Key_R) { root.rescan(); e.accepted=true }
        }
    }
    property var filteredNearby: []
    property var filteredKnown: []
    property string confirmText: ""
    property var pendingAction: null
    function clearFilter(){
        suppressUpdate = true
        filterField.text = ""
        suppressUpdate = false
        updateModels()
    }
    function deviceByAddress(addr){
        const devs = BluetoothService.devices
        for (let i = 0; i < devs.length; i++) if (devs[i].address === addr) return devs[i]
        return null
    }
    function isInRange(addr){
        // Scan-confirmed presence this session (paired devices emit [CHG] RSSI
        // without [NEW], so the nearby list alone is not enough).
        const seen = BluetoothService.seenAddrs
        return !!seen && seen[addr] === true
    }
    function toggleScan(){ BluetoothService.scanning ? BluetoothService.stopScan() : BluetoothService.startScan() }
    function rescan(){
        if (BluetoothService.scanning) BluetoothService.stopScan()
        BluetoothService.startScan()
    }
    function disconnectCurrent(){ if (root.connectedDevice) BluetoothService.disconnect(root.connectedDevice.address) }
    function toggleKnown(d){ d.connected ? BluetoothService.disconnect(d.address) : BluetoothService.connect(d.address) }
    // Nearby rows resolve against the paired set: a device BlueZ already knows
    // connects directly, only genuinely new devices go through pair+trust+connect.
    function connectNearby(d){
        if (!d) return
        const dev = deviceByAddress(d.address)
        if (dev && dev.paired) BluetoothService.connect(d.address)
        else BluetoothService.pairAndConnect(d.address)
    }
    function requestForget(d){ confirmText = "Forget \"" + (d.alias || d.address) + "\"?  y / n"; pendingAction = {type:"forget", address:d.address} }
    function requestForgetFocused(){
        const it = navItems[selIndex]
        if(!it) return
        if(it.kind==="known") { const d = filteredKnown[it.idx]; if(d) requestForget(d) }
    }
    function confirmYes(){
        if(!pendingAction){ confirmText=""; return }
        if(pendingAction.type==="forget") BluetoothService.forget(pendingAction.address)
        confirmText=""
        pendingAction=null
    }
    function updateModels(){
        const raw = filterField.text.trim().toLowerCase()
        // Slash commands switch the visible view (default: nearby):
        //   /nearby → live scan results only
        //   /known  → paired devices (connected ones included)
        //   <text>  → filter the currently visible list
        const isKnownCmd = raw === "/known" || raw === "known"
        const isNearbyCmd = raw === "/nearby" || raw === "nearby"
        const isCmd = isKnownCmd || isNearbyCmd
        if (isKnownCmd) { root.view = "known"; clearFilter() }
        else if (isNearbyCmd) { root.view = "nearby"; clearFilter() }
        if (isCmd) {
            filterActive = false
            Qt.callLater(()=> mainCol.forceActiveFocus())
        }
        const q = isCmd ? "" : raw.replace(/^\//, "")
        // Nearby = live scan results only. The BlueZ device cache is deliberately
        // excluded — it keeps entries for devices that are off or out of range,
        // which made stale devices (e.g. an iPhone with BT disabled) appear here.
        let nb = (BluetoothService.nearby || []).filter(d=> d && d.address)
            // Nameless random-addressed gadgets advertise as "Unknown device"
            // until BlueZ resolves a name — hide them until a name arrives.
            .filter(d=> d.alias && d.alias !== "Unknown device")
            .filter(d=> { const dev = deviceByAddress(d.address); return !dev || !dev.connected })
            .map(d=> { const dev = deviceByAddress(d.address); return { address: d.address, alias: d.alias, rssi: d.rssi || 0, paired: !!(dev && dev.paired) } })
        if(q) nb = nb.filter(d=> (d.alias && d.alias.toLowerCase().indexOf(q)!==-1) || d.address.toLowerCase().indexOf(q)!==-1)
        nb.sort((a,b)=> b.rssi - a.rssi)
        filteredNearby = nb.slice(0, 30)
        // Known = every paired device, connected ones included so a fresh
        // connection never disappears from this list.
        let kn = BluetoothService.devices.filter(d=> d.paired)
        if(q) kn = kn.filter(d=> (d.alias && d.alias.toLowerCase().indexOf(q)!==-1) || d.address.toLowerCase().indexOf(q)!==-1)
        kn.sort((a,b)=> (b.connected?1:0) - (a.connected?1:0) || String(a.alias||"").localeCompare(String(b.alias||"")))
        filteredKnown = kn
        const items=[]
        items.push({kind:"current"})
        items.push({kind:"power"})
        items.push({kind:"scan"})
        if(root.view==="nearby"){ for(let i=0;i<filteredNearby.length;i++) items.push({kind:"nearby", idx:i}) }
        else { for(let i=0;i<filteredKnown.length;i++) items.push({kind:"known", idx:i}) }
        navItems=items
        selIndex=Math.max(0, Math.min(selIndex, items.length-1))
        Qt.callLater(()=> ensureVisible(selIndex))
    }
    function moveSel(delta){
        const n = navItems.length
        if(n===0) return
        selIndex = Math.max(0, Math.min(n-1, selIndex+delta))
        ensureVisible(selIndex)
        Qt.callLater(()=> mainCol.forceActiveFocus())
    }
    function ensureVisible(i){
        const it = navItems[i]
        if(!it) return
        if(it.kind==="nearby" && nearbyList) nearbyList.positionViewAtIndex(it.idx, ListView.Contain)
        else if(it.kind==="known" && knownList) knownList.positionViewAtIndex(it.idx, ListView.Contain)
        let anchor = null
        if(it.kind==="current") anchor = currentCard
        else if(it.kind==="power") anchor = powerBtn
        else if(it.kind==="scan") anchor = scanBtn
        if(anchor && scrollView) Qt.callLater(()=> scrollToAnchor(anchor))
    }
    function scrollToAnchor(item){
        if(!item || !item.visible) return
        const targetY = item.mapToItem(mainCol, 0, 0).y
        const viewH = scrollView.height
        const maxY = Math.max(0, scrollView.contentHeight - viewH)
        if(targetY < scrollView.contentY) scrollView.contentY = Math.max(0, targetY - Theme.gapM)
        else if(targetY + item.height > scrollView.contentY + viewH) scrollView.contentY = Math.min(maxY, targetY + item.height + Theme.gapM - viewH)
    }
    function activate(){
        const it = navItems[selIndex]
        if(!it) return
        if(it.kind==="current"){ disconnectCurrent() }
        else if(it.kind==="power"){ BluetoothService.togglePower() }
        else if(it.kind==="scan"){ toggleScan() }
        else if(it.kind==="nearby"){ connectNearby(filteredNearby[it.idx]) }
        else if(it.kind==="known"){ const d=filteredKnown[it.idx]; if(d) toggleKnown(d) }
    }
    Connections { target: BluetoothService; function onDataUpdated(){ updateModels() } }
    Connections { target: BluetoothService; function onDevicesChanged(){ updateModels() } }
    Connections { target: BluetoothService; function onNearbyChanged(){ updateModels() } }
    Component.onCompleted: updateModels()
    onIsOpenChanged: if(isOpen) {
        BluetoothService.lastError = ""
        // Show paired devices straight away when any exist; otherwise scan view.
        root.view = BluetoothService.devices.some(d=> d.paired) ? "known" : "nearby"
        filterField.text=""; selIndex=0; confirmText=""; pendingAction=null
        BluetoothService.pollProc.running = true
        BluetoothService.startScan()
        updateModels()
        Qt.callLater(()=> mainCol.forceActiveFocus())
    } else { BluetoothService.stopScan() }
}
