import QtQuick
import QtQuick.Layouts
import "../../../theme"
import "../../../services"

// Connect-time route choice for the /vpn list, inline like VpnSecretPrompt.
// All traffic is preselected; j/k choose, Enter connects, Esc cancels.
// Spec: docs/superpowers/specs/2026-11-09-vpn-connect-mode-design.md.
Rectangle {
    id: prompt
    objectName: "vpnModePrompt"
    property string uuid: ""
    property string vpnName: ""
    property int sel: 0
    readonly property var modes: [
        { mode: "full", label: "All traffic through the VPN" },
        { mode: "split", label: "Only the VPN's own network" }
    ]
    readonly property string selectedMode: modes[sel].mode
    signal picked(string uuid, string mode)
    signal cancelled()

    visible: uuid !== ""
    Layout.fillWidth: true
    implicitHeight: col.implicitHeight + Theme.padL * 2
    radius: Theme.roundingItem
    color: Theme.bgActive
    border.color: Theme.borderSelected
    border.width: 1
    focus: true

    function open(id, name) {
        uuid = id; vpnName = name; sel = 0
        forceActiveFocus()
    }
    function close() { uuid = ""; vpnName = ""; sel = 0 }
    function move(d) { sel = Math.max(0, Math.min(modes.length - 1, sel + d)) }
    function choose() {
        const id = uuid, m = selectedMode
        close(); picked(id, m)
    }
    function cancel() { close(); cancelled() }
    function handleKey(e) {
        if (e.key === Qt.Key_J || e.key === Qt.Key_Down) { move(1); e.accepted = true; return true }
        if (e.key === Qt.Key_K || e.key === Qt.Key_Up) { move(-1); e.accepted = true; return true }
        if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { choose(); e.accepted = true; return true }
        if (e.key === Qt.Key_Escape) { cancel(); e.accepted = true; return true }
        return false
    }
    Keys.onPressed: (e) => { handleKey(e) }

    ColumnLayout {
        id: col
        anchors.fill: parent
        anchors.margins: Theme.padL
        spacing: Theme.gapM

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.gapM
            Text { text: Icons.vpn; font.family: Theme.fontFamily; font.pixelSize: 16; color: Theme.fg }
            Text {
                text: "Connect to " + prompt.vpnName
                font.family: Theme.fontFamily
                font.pixelSize: 13
                font.weight: Theme.fontWeightMedium
                color: Theme.fg
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
        }

        Repeater {
            model: prompt.modes
            delegate: Rectangle {
                required property var modelData
                required property int index
                Layout.fillWidth: true
                height: 28
                radius: Theme.roundingItem
                color: prompt.sel === index ? Theme.bgSelected : (ma.containsMouse ? Theme.bgHover : "transparent")
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.padM
                    anchors.rightMargin: Theme.padM
                    spacing: Theme.gapM
                    Text {
                        text: prompt.sel === index ? Icons.chevronRight : " "
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        color: Theme.fgBright
                    }
                    Text {
                        text: modelData.label
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        color: prompt.sel === index ? Theme.fgBright : Theme.fg
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                }
                MouseArea {
                    id: ma
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: { prompt.sel = index; prompt.choose() }
                }
            }
        }

        Text {
            text: "j/k choose · Enter connect · Esc cancel"
            font.family: Theme.fontFamily
            font.pixelSize: 10
            color: Theme.fgDim
            Layout.alignment: Qt.AlignHCenter
        }
    }
}
