import QtQuick
import QtQuick.Layouts
import "../../../theme"
import "../../../services"
import "../../../services/vpnSchema.js" as Schema

// Connect-time prompt for secrets set to Ask (NetworkService.vpnNeed) and for
// profile data the helper needs but the profile lacks, such as OpenVPN's
// username. Values go to NetworkService.vpnConnect (→ nm-vpn stdin; secrets
// then through nmcli's passwd-file pipe), and the fields are cleared at once.
// Spec §9–10.
Rectangle {
    id: prompt
    property bool reveal: false
    readonly property var keys: NetworkService.vpnNeed
    readonly property bool hasSecret: {
        for (let i = 0; i < keys.length; i++) {
            const f = Schema.fieldByKey(NetworkService.vpnNeedType, keys[i])
            if (!f || f.kind === "secret") return true
        }
        return false
    }
    signal done()

    visible: keys.length > 0
    Layout.fillWidth: true
    implicitHeight: col.implicitHeight + Theme.padL * 2
    radius: Theme.roundingItem
    color: Theme.bgActive
    border.color: Theme.borderSelected
    border.width: 1

    function fieldAt(i) { return rep.itemAt(i) }
    function focusFirst() { const f = fieldAt(0); if (f) f.focusInput() }
    function clear() {
        for (let i = 0; i < rep.count; i++) { const f = fieldAt(i); if (f) f.clear() }
        reveal = false
    }
    function submit() {
        const secrets = {}, data = {}
        for (let i = 0; i < rep.count; i++) {
            const f = fieldAt(i)
            if (!f) continue
            const key = prompt.keys[i]
            const field = Schema.fieldByKey(NetworkService.vpnNeedType, key)
            if (field && field.kind !== "secret") data[key] = f.text
            else secrets[key] = f.text
        }
        const uuid = NetworkService.vpnNeedUuid
        clear()
        NetworkService.vpnConnect(uuid, secrets, NetworkService.vpnNeedMode, data)
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
            delegate: VpnNeedField {
                required property var modelData
                required property int index
                vpnType: NetworkService.vpnNeedType
                key: modelData
                placeholder: Schema.labelFor(NetworkService.vpnNeedType, modelData)
                revealed: prompt.reveal
                onRevealToggled: prompt.reveal = !prompt.reveal
                onAccepted: { const next = prompt.fieldAt(index + 1); if (next) next.focusInput(); else prompt.submit() }
                onEscaped: prompt.cancel()
            }
        }
        Text {
            text: (prompt.hasSecret ? "Ctrl+s show/hide · " : "") + "Enter next / connect · Esc cancel"
            font.family: Theme.fontFamily
            font.pixelSize: 10
            color: Theme.fgDim
            Layout.alignment: Qt.AlignHCenter
        }
    }
}
