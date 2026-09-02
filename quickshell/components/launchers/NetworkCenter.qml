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
    // Known section visible only after the `/known` command
    property var navItems: []
    property int selIndex: 0
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
                Text { text: "Network"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fgMuted; font.capitalization: Font.AllUppercase; font.letterSpacing: 1.2 }
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
                Text {
                    visible: !filterActive
                    text: "Press / for commands (/nearby · /known · /vpn) · j/k to move · Enter to act"
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    color: Theme.fgDim
                    Layout.fillWidth: true
                }
                Rectangle {
                    id: scanBtn
                    width: 80; height: 32
                    radius: Theme.roundingItem
                    readonly property bool isSel: root.navItems[root.selIndex] !== undefined && root.navItems[root.selIndex].kind === "scan"
                    color: isSel ? Theme.bgSelected : Theme.bgHover
                    border.color: isSel ? Theme.borderSelected : Theme.border
                    border.width: 1
                    Text { anchors.centerIn: parent; text: "Scan"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fg }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: NetworkService.rescanWifi() }
                }
            }

            Text { text: "Current"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fgMuted }
            Rectangle {
                id: currentCard
                Layout.fillWidth: true
                height: curCol.implicitHeight + Theme.padM*2
                radius: Theme.roundingItem
                readonly property bool isSel: root.navItems[root.selIndex] !== undefined && root.navItems[root.selIndex].kind === "current"
                readonly property bool isConnecting: NetworkService.connecting
                color: NetworkService.connected ? Theme.bgActive : (isSel ? Theme.bgSelected : Theme.bgHover)
                border.color: isSel ? Theme.borderSelected : (NetworkService.connected ? Theme.borderSelected : Theme.border)
                border.width: 1
                ColumnLayout {
                    id: curCol
                    anchors.fill: parent
                    anchors.margins: Theme.padM
                    spacing: 4
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.gapM
                        Rectangle {
                            width: 40; height: 40
                            radius: 8
                            color: NetworkService.connected ? Theme.bgSelected : Theme.bgBar
                            Text { anchors.centerIn: parent; text: NetworkService.type==="ethernet" ? Icons.wifiEthernet : Icons.wifiConnected; font.family: Theme.fontFamily; font.pixelSize: 18; color: NetworkService.connected ? Theme.fg : Theme.fgDim }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            Text {
                                text: currentCard.isConnecting ? "Connecting to " + (NetworkService.connectingSsid || "network") + "…" : (NetworkService.connected ? NetworkService.essid + " · " + NetworkService.signalStrength + "%" : "Not connected")
                                font.family: Theme.fontFamily
                                font.pixelSize: 14
                                font.weight: Theme.fontWeightMedium
                                color: currentCard.isConnecting ? Theme.fgMuted : (NetworkService.connected ? Theme.fg : Theme.fgDim)
                                elide: Text.ElideRight
                            }
                            Text {
                                visible: NetworkService.connected && !currentCard.isConnecting
                                text: (NetworkService.ipaddr || "") + (NetworkService.vpnActive ? " · via " + NetworkService.vpnName : "")
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                color: Theme.fgMuted
                            }
                        }
                        Rectangle {
                            visible: NetworkService.connected && !currentCard.isConnecting
                            width: 90; height: 32
                            radius: Theme.roundingItem
                            color: Theme.bgBar
                            border.color: Theme.critical
                            border.width: 1
                            Text { anchors.centerIn: parent; text: "Disconnect"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.critical }
                            MouseArea { anchors.fill: parent; onClicked: NetworkService.disconnect() }
                        }
                    }
                    Text { visible: !NetworkService.connected && !currentCard.isConnecting; text: "Pick a known network or scan"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fgDim }
                }
            }

            Text { visible: root.view === "nearby"; text: "Nearby"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fgMuted }
            Text { visible: root.view === "nearby" && filteredScan.length === 0; text: "No networks found — press r to rescan"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fgDim }
            ListView {
                id: nearbyList
                visible: root.view === "nearby"
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(160, contentHeight)
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
                    color: isSel ? Theme.bgSelected : (ma2.containsMouse ? Theme.bgHover : "transparent")
                    border.color: isSel ? Theme.borderSelected : "transparent"
                    border.width: 1
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.padM
                        anchors.rightMargin: Theme.padM
                        spacing: Theme.gapM
                        Text { text: modelData.ssid || "<hidden>"; font.family: Theme.fontFamily; font.pixelSize: 13; color: Theme.fg; Layout.fillWidth: true; elide: Text.ElideRight }
                        Rectangle { width: 60; height: 6; radius: 3; color: Theme.border; Rectangle { width: parent.width * modelData.signal/100; height: parent.height; radius: 3; color: modelData.signal<30 ? Theme.warning : Theme.fg } }
                        Text { text: modelData.signal + "%"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fgMuted; Layout.preferredWidth: 36; horizontalAlignment: Text.AlignRight }
                        Text { text: modelData.security !== "--" ? Icons.lock : ""; font.family: Theme.fontFamily; font.pixelSize: 12; color: Theme.fgMuted }
                    }
                    MouseArea {
                        id: ma2
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: root.connectNearby(modelData)
                    }
                }
            }

            Text { visible: root.view === "known"; text: "Known"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fgMuted }
            Text { visible: root.view === "known" && filteredKnown.length === 0; text: "No known networks — connect from /nearby first"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fgDim }
            ListView {
                id: knownList
                visible: root.view === "known"
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(140, contentHeight)
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
                    color: isSel ? Theme.bgSelected : (ma.containsMouse ? Theme.bgHover : "transparent")
                    border.color: isSel ? Theme.borderSelected : "transparent"
                    border.width: 1
                    MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true }
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.padM
                        anchors.rightMargin: Theme.padM
                        spacing: Theme.gapM
                        Text { text: "●"; font.pixelSize: 8; color: Theme.success }
                        Text { text: modelData.name; font.family: Theme.fontFamily; font.pixelSize: 13; color: Theme.fg; Layout.fillWidth: true; elide: Text.ElideRight }
                        Rectangle {
                            width: 70; height: 28
                            radius: 6
                            color: Theme.bgActive
                            border.color: Theme.borderActive
                            border.width: 1
                            Text { anchors.centerIn: parent; text: "Connect"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fg }
                            MouseArea { anchors.fill: parent; onClicked: NetworkService.connectKnown(modelData.uuid) }
                        }
                        Text { text: "Forget"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.critical; MouseArea { anchors.fill: parent; onClicked: { root.pendingAction = {type:"forget", name:modelData.name, uuid:modelData.uuid}; root.confirmText = "Forget \"" + modelData.name + "\"?  y / n" } } }
                    }
                }
            }

            Text { visible: root.view === "vpn"; text: "VPN"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fgMuted }
            Text { visible: root.view === "vpn" && filteredVpn.length === 0; text: "No VPN connections"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fgDim }
            ListView {
                id: vpnList
                visible: root.view === "vpn"
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(80, contentHeight)
                clip: true
                spacing: 4
                model: filteredVpn
                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    width: parent.width
                    height: 44
                    radius: Theme.roundingItem
                    readonly property bool isSel: { const it = root.navItems[root.selIndex]; return it !== undefined && it.kind === "vpn" && it.idx === index }
                    readonly property bool isActive: NetworkService.vpnActive && NetworkService.vpnName === modelData.name
                    color: isSel ? Theme.bgSelected : (vpnMA.containsMouse ? Theme.bgHover : "transparent")
                    border.color: isSel ? Theme.borderSelected : "transparent"
                    border.width: 1
                    MouseArea {
                        id: vpnMA
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: isActive ? NetworkService.vpnDisconnect(modelData.uuid) : NetworkService.vpnConnect(modelData.uuid)
                    }
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.padM
                        anchors.rightMargin: Theme.padM
                        spacing: Theme.gapM
                        Text { text: Icons.vpn; font.family: Theme.fontFamily; font.pixelSize: 14; color: isActive ? Theme.accent : Theme.fgMuted }
                        Text { text: modelData.name; font.family: Theme.fontFamily; font.pixelSize: 13; color: Theme.fg; Layout.fillWidth: true; elide: Text.ElideRight }
                        Text { visible: isActive; text: "●"; font.pixelSize: 8; color: Theme.success }
                        Text { text: isActive ? "active" : ""; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fgMuted }
                        Text {
                            text: "Delete"
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            color: Theme.critical
                            MouseArea { anchors.fill: parent; onClicked: requestVpnDelete(modelData.name, modelData.uuid) }
                        }
                    }
                }
            }
            Rectangle {
                id: vpnAddRow
                visible: root.view === "vpn"
                Layout.fillWidth: true
                height: 32
                radius: Theme.roundingItem
                readonly property bool isSel: root.navItems[root.selIndex] !== undefined && root.navItems[root.selIndex].kind === "vpnAdd"
                color: isSel ? Theme.bgSelected : Theme.bgHover
                border.color: isSel ? Theme.borderSelected : Theme.border
                border.width: 1
                Text { anchors.centerIn: parent; text: "Add VPN…"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fg }
                MouseArea { anchors.fill: parent; onClicked: NetworkService.vpnAdd() }
            }
            Rectangle {
                id: editorRow
                visible: root.view === "vpn"
                Layout.fillWidth: true
                height: 32
                radius: Theme.roundingItem
                readonly property bool isSel: root.navItems[root.selIndex] !== undefined && root.navItems[root.selIndex].kind === "editor"
                color: isSel ? Theme.bgSelected : Theme.bgHover
                border.color: isSel ? Theme.borderSelected : Theme.border
                border.width: 1
                Text { anchors.centerIn: parent; text: "Open connection editor…"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fg }
                MouseArea { anchors.fill: parent; onClicked: NetworkService.launchEditor() }
            }
            Rectangle {
                id: pwdDialog
                property string ssid: ""
                property string security: ""
                visible: false
                Layout.fillWidth: true
                height: pwdCol.implicitHeight + Theme.padL*2
                radius: Theme.roundingItem
                color: Theme.bgActive
                border.color: Theme.borderSelected
                border.width: 1
                ColumnLayout {
                    id: pwdCol
                    anchors.fill: parent
                    anchors.margins: Theme.padL
                    spacing: Theme.gapM
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.gapM
                        Rectangle {
                            width: 36; height: 36
                            radius: Theme.roundingItem
                            color: Theme.bgBar
                            border.color: Theme.border
                            border.width: 1
                            Text { anchors.centerIn: parent; text: Icons.lock; font.family: Theme.fontFamily; font.pixelSize: 16; color: Theme.fg }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            Text {
                                text: "Password for " + pwdDialog.ssid
                                font.family: Theme.fontFamily
                                font.pixelSize: 13
                                font.weight: Theme.fontWeightMedium
                                color: Theme.fg
                                elide: Text.ElideRight
                            }
                            Text { text: "Enter the password to connect"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fgMuted }
                        }
                        Rectangle {
                            width: 64; height: 24
                            radius: Theme.roundingItem
                            color: Theme.bgCritical
                            Text { anchors.centerIn: parent; text: pwdDialog.security; font.family: Theme.fontFamily; font.pixelSize: 10; color: Theme.critical; font.weight: Theme.fontWeightMedium }
                        }
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        height: 40
                        radius: Theme.roundingItem
                        color: Theme.bgBar
                        border.color: pwdField.activeFocus ? Theme.borderSelected : Theme.border
                        border.width: 1
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Theme.padM
                            anchors.rightMargin: Theme.padS
                            spacing: Theme.gapS
                            TextField {
                                id: pwdField
                                Layout.fillWidth: true
                                placeholderText: "Password…"
                                echoMode: pwdShow.checked ? TextInput.Normal : TextInput.Password
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
                                onAccepted: connectPwd()
                            }
                            Rectangle {
                                id: pwdShow
                                property bool checked: false
                                width: 30; height: 30
                                radius: Theme.roundingItem
                                color: pwdShow.checked ? Theme.bgSelected : "transparent"
                                Text {
                                    anchors.centerIn: parent
                                    text: pwdShow.checked ? Icons.eyeOff : Icons.eye
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 14
                                    color: pwdShow.checked ? Theme.fg : Theme.fgMuted
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: pwdShow.checked = !pwdShow.checked
                                }
                            }
                        }
                    }
                    Text { text: "Ctrl+s show/hide password · Enter connect · Esc cancel"; font.family: Theme.fontFamily; font.pixelSize: 10; color: Theme.fgDim; Layout.alignment: Qt.AlignHCenter }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.gapM
                        Rectangle {
                            Layout.fillWidth: true
                            height: 36
                            radius: Theme.roundingItem
                            color: Theme.bgSelected
                            border.color: Theme.borderSelected
                            border.width: 1
                            Text { anchors.centerIn: parent; text: "Connect"; font.family: Theme.fontFamily; font.pixelSize: 12; color: Theme.fg; font.weight: Theme.fontWeightMedium }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: connectPwd() }
                        }
                        Rectangle {
                            Layout.fillWidth: true
                            height: 36
                            radius: Theme.roundingItem
                            color: Theme.bgHover
                            border.color: Theme.border
                            border.width: 1
                            Text { anchors.centerIn: parent; text: "Cancel"; font.family: Theme.fontFamily; font.pixelSize: 12; color: Theme.fg }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: cancelPwd() }
                        }
                    }
                }
            }
            Text {
                visible: NetworkService.lastError !== ""
                text: Icons.warning + " " + NetworkService.lastError
                font.family: Theme.fontFamily
                font.pixelSize: 11
                color: Theme.critical
                Layout.fillWidth: true
                wrapMode: Text.Wrap
            }
            Text {
                text: {
                    if (confirmText) return confirmText
                    if (NetworkService.busy) return "Working…"
                    return "j/k · Enter act · /nearby /known /vpn · x delete · d disc · r rescan · Esc back · Esc close"
                }
                font.family: Theme.fontFamily
                font.pixelSize: 10
                color: confirmText ? Theme.critical : (NetworkService.busy ? Theme.fgMuted : Theme.fgDim)
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
                if(pwdDialog.visible){ cancelPwd(); e.accepted=true }
                else if(filterActive){ filterActive=false; clearFilter(); mainCol.forceActiveFocus(); e.accepted=true }
                else if(root.view !== "nearby"){ root.view="nearby"; updateModels(); e.accepted=true }
                else root.close()
            }
            else if((e.key===Qt.Key_S) && (e.modifiers & Qt.ControlModifier)) { if(pwdDialog.visible){ pwdShow.checked = !pwdShow.checked; e.accepted=true } }
            else if(e.key===Qt.Key_J || e.key===Qt.Key_Down) { root.moveSel(1); e.accepted=true }
            else if(e.key===Qt.Key_K || e.key===Qt.Key_Up) { root.moveSel(-1); e.accepted=true }
            else if(e.key===Qt.Key_Return || e.key===Qt.Key_Enter) { root.activate(); e.accepted=true }
            else if(e.key===Qt.Key_D) { NetworkService.disconnect(); e.accepted=true }
            else if(e.key===Qt.Key_X) { root.requestDelete(); e.accepted=true }
            else if(e.text==="/") { filterActive=true; filterField.forceActiveFocus(); e.accepted=true }
            else if(e.key===Qt.Key_R) { NetworkService.rescanWifi(); e.accepted=true }
        }
    }
    onIsOpenChanged: if(isOpen) { NetworkService.lastError = ""; NetworkService.refresh(); NetworkService.rescanWifi(); filterField.text=""; root.view="nearby"; selIndex=0; confirmText=""; updateModels(); Qt.callLater(()=> mainCol.forceActiveFocus()) }
    property var filteredKnown: []
    property var filteredScan: []
    property var filteredVpn: []
    property string confirmText: ""
    property var pendingAction: null
    function clearFilter(){
        suppressUpdate = true
        filterField.text = ""
        suppressUpdate = false
        updateModels()
    }
    function requestDelete(){
        const it = navItems[selIndex]
        if(!it) return
        if(it.kind==="known") {
            const n = filteredKnown[it.idx]
            if(n) { pendingAction = {type:"forget", name:n.name, uuid:n.uuid}; confirmText = "Forget \"" + n.name + "\"?  y / n" }
        } else if(it.kind==="vpn") {
            const v = filteredVpn[it.idx]
            if(v) { pendingAction = {type:"vpnDelete", name:v.name, uuid:v.uuid}; confirmText = "Delete VPN \"" + v.name + "\"?  y / n" }
        }
    }
    function requestVpnDelete(name, uuid){ confirmText = "Delete VPN \"" + name + "\"?  y / n"; pendingAction = {type:"vpnDelete", name:name, uuid:uuid} }
    function confirmYes(){
        if(!pendingAction){ confirmText=""; return }
        if(pendingAction.type==="forget") NetworkService.forget(pendingAction.uuid)
        else if(pendingAction.type==="vpnDelete") NetworkService.vpnDelete(pendingAction.uuid)
        confirmText=""
        pendingAction=null
    }
    function openPwd(ssid, security){
        // Guard: an in-flight connect must never re-open the dialog
        if (NetworkService.connecting || NetworkService.busy) return
        pwdDialog.ssid = ssid
        pwdDialog.security = security
        pwdField.text = ""
        pwdShow.checked = false
        pwdDialog.visible = true
        pwdField.forceActiveFocus()
    }
    // Spec §3.3: an SSID with an existing profile connects via its saved credentials —
    // never prompt for a password, even when selected from the nearby view.
    // connectScanned routes known ssids to `connection up` internally (NetworkService §5).
    function knownUuidFor(ssid){
        const k = NetworkService.knownNetworks
        for (let i = 0; i < k.length; i++) if (k[i].name === ssid) return k[i].uuid
        return ""
    }
    function connectNearby(net){
        if (!net) return
        if (net.security !== "--" && knownUuidFor(net.ssid) === "") openPwd(net.ssid, net.security)
        else NetworkService.connectScanned(net.ssid, "")
    }
    function connectPwd(){
        const ssid = pwdDialog.ssid
        const pwd = pwdField.text
        cancelPwd()
        NetworkService.connectScanned(ssid, pwd)
    }
    function cancelPwd(){
        pwdDialog.visible=false
        pwdField.text=""
        pwdShow.checked=false
        mainCol.forceActiveFocus()
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
        if(it.kind==="known" && knownList) knownList.positionViewAtIndex(it.idx, ListView.Contain)
        else if(it.kind==="nearby" && nearbyList) nearbyList.positionViewAtIndex(it.idx, ListView.Contain)
        else if(it.kind==="vpn" && vpnList) vpnList.positionViewAtIndex(it.idx, ListView.Contain)
        let anchor = null
        if(it.kind==="current") anchor = currentCard
        else if(it.kind==="scan") anchor = scanBtn
        else if(it.kind==="vpnAdd") anchor = vpnAddRow
        else if(it.kind==="editor") anchor = editorRow
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
        if(it.kind==="current"){ if(NetworkService.connected) NetworkService.disconnect(); else NetworkService.rescanWifi() }
        else if(it.kind==="scan"){ NetworkService.rescanWifi() }
        else if(it.kind==="known"){ const n=filteredKnown[it.idx]; if(n) NetworkService.connectKnown(n.uuid) }
        else if(it.kind==="nearby"){ const n=filteredScan[it.idx]; if(n) connectNearby(n) }
        else if(it.kind==="vpn"){ const v=filteredVpn[it.idx]; if(v){ if(NetworkService.vpnActive && NetworkService.vpnName===v.name) NetworkService.vpnDisconnect(v.uuid); else NetworkService.vpnConnect(v.uuid) } }
        else if(it.kind==="vpnAdd"){ NetworkService.vpnAdd() }
        else if(it.kind==="editor"){ NetworkService.launchEditor() }
    }
    function updateModels(){
        const raw = filterField.text.trim().toLowerCase()
        // Slash commands switch the visible view (default: nearby):
        //   /nearby → nearby networks only
        //   /known  → known networks only
        //   /vpn    → VPN networks + configuration options
        //   <text>  → filter the currently visible list
        const isKnownCmd = raw === "/known" || raw === "known"
        const isNearbyCmd = raw === "/nearby" || raw === "nearby"
        const isVpnCmd = raw === "/vpn" || raw === "vpn"
        const isCmd = isKnownCmd || isNearbyCmd || isVpnCmd
        if (isKnownCmd) { root.view = "known"; clearFilter() }
        else if (isNearbyCmd) { root.view = "nearby"; clearFilter() }
        else if (isVpnCmd) { root.view = "vpn"; clearFilter() }
        if (isCmd) {
            filterActive = false
            Qt.callLater(()=> mainCol.forceActiveFocus())
        }
        const q = isCmd ? "" : raw.replace(/^\//, "")
        let k = NetworkService.knownNetworks
        let s = NetworkService.scannedNetworks
        let v = NetworkService.vpnConnections
        if(q){ k=k.filter(x=> x.name.toLowerCase().indexOf(q)!==-1); s=s.filter(x=> x.ssid.toLowerCase().indexOf(q)!==-1); v=v.filter(x=> x.name.toLowerCase().indexOf(q)!==-1) }
        filteredKnown=k
        filteredScan=s
        filteredVpn=v
        const items=[]
        items.push({kind:"current"})
        items.push({kind:"scan"})
        if(root.view==="nearby"){ for(let i=0;i<s.length;i++) items.push({kind:"nearby", idx:i}) }
        else if(root.view==="known"){ for(let i=0;i<k.length;i++) items.push({kind:"known", idx:i}) }
        else if(root.view==="vpn"){ for(let i=0;i<v.length;i++) items.push({kind:"vpn", idx:i}); items.push({kind:"vpnAdd"}); items.push({kind:"editor"}) }
        navItems=items
        selIndex=Math.max(0, Math.min(selIndex, items.length-1))
        Qt.callLater(()=> ensureVisible(selIndex))
    }
    Connections { target: NetworkService; function onDataUpdated(){ updateModels() } }
    Component.onCompleted: updateModels()
}
