import QtQuick
import QtQuick.Layouts
import "../../../theme"
import "../../../services"
import "../../../services/vpnSchema.js" as Schema
import ".."                                   // SecretField

// Connect-time prompt for secrets set to Ask (NetworkService.vpnNeed),
// inline in the /vpn view like the Wi-Fi password box. The values go to
// NetworkService.vpnConnect (→ nm-vpn stdin → nmcli passwd-file pipe), and
// the fields are cleared at once. Spec §9–10.
Rectangle {
    id: prompt
    property bool reveal: false
    readonly property var keys: NetworkService.vpnNeed
    signal done()

    visible: keys.length > 0
    Layout.fillWidth: true
    implicitHeight: col.implicitHeight + Theme.padL * 2
    radius: Theme.roundingItem
    color: Theme.bgActive
    border.color: Theme.borderSelected
    border.width: 1

    function fieldAt(i) { return rep.itemAt(i) }
    function focusFirst() { const f = fieldAt(0); if (f) f.forceActiveFocus() }
    function clear() {
        for (let i = 0; i < rep.count; i++) { const f = fieldAt(i); if (f) f.text = "" }
        reveal = false
    }
    function submit() {
        const secrets = {}
        for (let i = 0; i < rep.count; i++) { const f = fieldAt(i); if (f) secrets[prompt.keys[i]] = f.text }
        const uuid = NetworkService.vpnNeedUuid
        clear()
        NetworkService.vpnConnect(uuid, secrets, NetworkService.vpnNeedMode)
        prompt.done()
    }
    function cancel() { clear(); NetworkService.vpnCancelNeed(); prompt.done() }

    ColumnLayout {
        id: col
        anchors.fill: parent
        anchors.margins: Theme.padL
        spacing: Theme.gapM
        RowLayout {
            spacing: Theme.gapM
            Layout.fillWidth: true
            Text { text: Icons.lock; font.family: Theme.fontFamily; font.pixelSize: 16; color: Theme.fg }
            Text {
                text: "Sign in to " + NetworkService.vpnNeedName
                font.family: Theme.fontFamily
                font.pixelSize: 13
                font.weight: Theme.fontWeightMedium
                color: Theme.fg
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
        }
        Repeater {
            id: rep
            model: prompt.keys
            delegate: SecretField {
                required property var modelData
                required property int index
                placeholder: Schema.labelFor(NetworkService.vpnNeedType, modelData)
                revealed: prompt.reveal
                onRevealToggled: prompt.reveal = !prompt.reveal
                onAccepted: { const next = prompt.fieldAt(index + 1); if (next) next.forceActiveFocus(); else prompt.submit() }
                onEscaped: prompt.cancel()
            }
        }
        Text {
            text: "Ctrl+s show/hide · Enter next / connect · Esc cancel"
            font.family: Theme.fontFamily
            font.pixelSize: 10
            color: Theme.fgDim
            Layout.alignment: Qt.AlignHCenter
        }
    }
}
