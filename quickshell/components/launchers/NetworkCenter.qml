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
    property bool filterActive: false
    function open(){ isOpen=true }
    function close(){ isOpen=false; filterActive=false }
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
                    border.color: filterField.activeFocus ? Theme.fg : Theme.border
                    border.width: 1
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
                            onTextChanged: updateModels()
                        }
                    }
                }
                Text {
                    visible: !filterActive
                    text: "Press / to filter · r to rescan"
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    color: Theme.fgDim
                    Layout.fillWidth: true
                }
                Rectangle {
                    width: 80; height: 32
                    radius: Theme.roundingItem
                    color: Theme.bgHover
                    border.color: Theme.border
                    border.width: 1
                    Text { anchors.centerIn: parent; text: "Scan"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fg }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: NetworkService.rescanWifi() }
                }
            }

            Text { text: "Current"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fgMuted }
            Rectangle {
                Layout.fillWidth: true
                height: curCol.implicitHeight + Theme.padM*2
                radius: Theme.roundingItem
                color: NetworkService.connected ? Theme.bgActive : Theme.bgHover
                border.color: NetworkService.connected ? Theme.fg : Theme.border
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
                            color: NetworkService.connected ? Theme.fg : Theme.bgBar
                            Text { anchors.centerIn: parent; text: NetworkService.type==="ethernet" ? Icons.wifiEthernet : Icons.wifiConnected; font.family: Theme.fontFamily; font.pixelSize: 18; color: NetworkService.connected ? Theme.bgBar : Theme.fgDim }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            Text {
                                text: NetworkService.connected ? NetworkService.essid + " · " + NetworkService.signalStrength + "%" : "Not connected"
                                font.family: Theme.fontFamily
                                font.pixelSize: 14
                                font.weight: Theme.fontWeightMedium
                                color: NetworkService.connected ? Theme.fg : Theme.fgDim
                            }
                            Text {
                                visible: NetworkService.connected
                                text: (NetworkService.ipaddr || "") + (NetworkService.vpnActive ? " · via " + NetworkService.vpnName : "")
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                color: Theme.fgMuted
                            }
                        }
                        Rectangle {
                            visible: NetworkService.connected
                            width: 90; height: 32
                            radius: Theme.roundingItem
                            color: Theme.bgBar
                            border.color: Theme.critical
                            border.width: 1
                            Text { anchors.centerIn: parent; text: "Disconnect"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.critical }
                            MouseArea { anchors.fill: parent; onClicked: NetworkService.disconnect() }
                        }
                    }
                    Text { visible: !NetworkService.connected; text: "Pick a known network or scan"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fgDim }
                }
            }

            Text { text: "Known"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fgMuted }
            ListView {
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(140, contentHeight)
                clip: true
                spacing: 4
                model: filteredKnown
                delegate: Rectangle {
                    required property var modelData
                    width: parent.width
                    height: 44
                    radius: Theme.roundingItem
                    color: ma.containsMouse ? Theme.bgHover : "transparent"
                    border.color: "transparent"
                    border.width: 1
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
                            border.color: Theme.fg
                            border.width: 1
                            Text { anchors.centerIn: parent; text: "Connect"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fg }
                            MouseArea { anchors.fill: parent; onClicked: NetworkService.connectKnown(modelData.name) }
                        }
                        Text { text: "Forget"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.critical; MouseArea { anchors.fill: parent; onClicked: NetworkService.forget(modelData.name) } }
                    }
                    MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true }
                }
            }

            Text { text: "Nearby"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fgMuted }
            ListView {
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(160, contentHeight)
                clip: true
                spacing: 4
                model: filteredScan
                delegate: Rectangle {
                    required property var modelData
                    width: parent.width
                    height: 44
                    radius: Theme.roundingItem
                    color: ma2.containsMouse ? Theme.bgHover : "transparent"
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.padM
                        anchors.rightMargin: Theme.padM
                        spacing: Theme.gapM
                        Text { text: modelData.ssid || "<hidden>"; font.family: Theme.fontFamily; font.pixelSize: 13; color: Theme.fg; Layout.fillWidth: true; elide: Text.ElideRight }
                        Rectangle { width: 60; height: 6; radius: 3; color: Theme.border; Rectangle { width: parent.width * modelData.signal/100; height: parent.height; radius: 3; color: modelData.signal<30 ? Theme.warning : Theme.fg } }
                        Text { text: modelData.signal + "%"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fgMuted; Layout.preferredWidth: 36; horizontalAlignment: Text.AlignRight }
                        Text { text: modelData.security !== "--" ? "🔒" : ""; font.pixelSize: 12 }
                    }
                    MouseArea {
                        id: ma2
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            if (modelData.security !== "--") { pwdDialog.ssid=modelData.ssid; pwdDialog.visible=true; pwdField.forceActiveFocus() }
                            else NetworkService.connectScanned(modelData.ssid, "")
                        }
                    }
                }
            }

            Text { text: "VPN"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fgMuted }
            ListView {
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(80, contentHeight)
                clip: true
                spacing: 4
                model: NetworkService.vpnConnections
                delegate: Rectangle {
                    required property var modelData
                    width: parent.width
                    height: 36
                    radius: Theme.roundingItem
                    color: Theme.bgHover
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.padM
                        Text { text: Icons.vpn; font.family: Theme.fontFamily; font.pixelSize: 14; color: Theme.fg }
                        Text { text: modelData.name; font.family: Theme.fontFamily; font.pixelSize: 13; color: Theme.fg; Layout.fillWidth: true }
                        Rectangle {
                            width: 70; height: 26
                            radius: 6
                            color: Theme.bgActive
                            border.color: Theme.fg
                            border.width: 1
                            Text { anchors.centerIn: parent; text: "Connect"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fg }
                            MouseArea { anchors.fill: parent; onClicked: NetworkService.vpnConnect(modelData.name) }
                        }
                    }
                }
            }
            Rectangle {
                Layout.fillWidth: true
                height: 32
                radius: Theme.roundingItem
                color: Theme.bgHover
                border.color: Theme.border
                border.width: 1
                Text { anchors.centerIn: parent; text: "Open nm-connection-editor…"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fgMuted }
                MouseArea { anchors.fill: parent; onClicked: NetworkService.launchEditor() }
            }

            Rectangle {
                id: pwdDialog
                property string ssid: ""
                visible: false
                Layout.fillWidth: true
                height: pwdCol.implicitHeight + Theme.padM*2
                radius: Theme.roundingItem
                color: Theme.bgActive
                border.color: Theme.fg
                border.width: 2
                ColumnLayout {
                    id: pwdCol
                    anchors.fill: parent
                    anchors.margins: Theme.padM
                    spacing: Theme.gapS
                    Text { text: "Password for " + pwdDialog.ssid; font.family: Theme.fontFamily; font.pixelSize: 13; color: Theme.fg; font.weight: Theme.fontWeightMedium }
                    TextField {
                        id: pwdField
                        Layout.fillWidth: true
                        placeholderText: "Password…"
                        echoMode: TextInput.Password
                        font.family: Theme.fontFamily
                        background: Rectangle { radius: Theme.roundingItem; color: Theme.bgBar; border.color: Theme.border }
                        color: Theme.fg
                        onAccepted: { NetworkService.connectScanned(pwdDialog.ssid, text); pwdDialog.visible=false; text="" }
                    }
                    RowLayout {
                        spacing: Theme.gapM
                        Rectangle {
                            Layout.fillWidth: true
                            height: 32
                            radius: Theme.roundingItem
                            color: Theme.fg
                            Text { anchors.centerIn: parent; text: "Connect"; font.family: Theme.fontFamily; font.pixelSize: 12; color: Theme.bgBar; font.weight: Theme.fontWeightMedium }
                            MouseArea { anchors.fill: parent; onClicked: { NetworkService.connectScanned(pwdDialog.ssid, pwdField.text); pwdDialog.visible=false; pwdField.text="" } }
                        }
                        Rectangle {
                            Layout.fillWidth: true
                            height: 32
                            radius: Theme.roundingItem
                            color: Theme.bgHover
                            border.color: Theme.border
                            border.width: 1
                            Text { anchors.centerIn: parent; text: "Cancel"; font.family: Theme.fontFamily; font.pixelSize: 12; color: Theme.fg }
                            MouseArea { anchors.fill: parent; onClicked: { pwdDialog.visible=false; pwdField.text="" } }
                        }
                    }
                }
            }
            Text { text: "/ filter · r rescan · Enter connect · Esc close"; font.family: Theme.fontFamily; font.pixelSize: 10; color: Theme.fgDim; Layout.alignment: Qt.AlignHCenter }
        }
        Keys.onPressed: (e)=>{
            if(e.key===Qt.Key_Escape) { if(pwdDialog.visible){pwdDialog.visible=false; e.accepted=true} else if(filterActive){filterActive=false; e.accepted=true} else root.close() }
            else if(e.text==="/") { filterActive=true; filterField.forceActiveFocus(); e.accepted=true }
            else if(e.key===Qt.Key_R) { NetworkService.rescanWifi(); e.accepted=true }
        }
    }
    onIsOpenChanged: if(isOpen) { NetworkService.refresh(); filterField.text=""; updateModels(); Qt.callLater(()=> mainCol.forceActiveFocus()) }
    property var filteredKnown: []
    property var filteredScan: []
    function updateModels(){
        const q = filterField.text.toLowerCase()
        let k = NetworkService.knownNetworks
        let s = NetworkService.scannedNetworks
        if(q){ k=k.filter(x=> x.name.toLowerCase().indexOf(q)!==-1); s=s.filter(x=> x.ssid.toLowerCase().indexOf(q)!==-1) }
        filteredKnown=k
        filteredScan=s
    }
    Connections { target: NetworkService; function onDataUpdated(){ updateModels() } }
    Component.onCompleted: updateModels()
}
