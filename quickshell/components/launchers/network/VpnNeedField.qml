import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../../theme"
import "../../../services/vpnSchema.js" as Schema

// One connect-time field in VpnSecretPrompt. A schema secret (password,
// pre-shared key, ...) is masked with the usual show/hide eye; profile data
// the helper asks for (OpenVPN's username) uses a plain box. Keys with no
// schema stay masked, so an unknown plugin's secrets are never revealed by
// accident.
Rectangle {
    id: box
    property string vpnType: ""
    property string key: ""
    property bool revealed: false
    readonly property bool secret: { const f = Schema.fieldByKey(vpnType, key); return !f || f.kind === "secret" }
    property alias text: input.text
    property alias placeholder: input.placeholderText
    property alias input: input
    signal accepted()
    signal escaped()
    signal revealToggled()
    function focusInput() { input.forceActiveFocus() }
    function clear() { input.text = "" }

    Layout.fillWidth: true
    Layout.preferredHeight: 36
    radius: Theme.roundingItem
    color: Theme.bgActive
    border.color: input.activeFocus ? Theme.borderSelected : Theme.border
    border.width: 1

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Theme.padM
        anchors.rightMargin: Theme.padS
        spacing: Theme.gapS
        TextField {
            id: input
            Layout.fillWidth: true
            echoMode: box.secret && !box.revealed ? TextInput.Password : TextInput.Normal
            font.family: Theme.fontFamily
            font.pixelSize: 13
            color: Theme.fg
            placeholderTextColor: Theme.fgDim
            background: null
            activeFocusOnTab: true
            inputMethodHints: box.secret
                ? (Qt.ImhSensitiveData | Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase)
                : Qt.ImhNoPredictiveText
            cursorDelegate: Rectangle {
                width: Math.max(6, Math.round(input.font.pixelSize * 0.65))
                height: Math.round(input.font.pixelSize * 1.5)
                color: Theme.fg
                opacity: input.activeFocus ? 1 : 0
            }
            onAccepted: box.accepted()
            Keys.onEscapePressed: (e) => { box.escaped(); e.accepted = true }
            Keys.onPressed: (e) => {
                if (box.secret && e.key === Qt.Key_S && (e.modifiers & Qt.ControlModifier)) {
                    box.revealToggled()
                    e.accepted = true
                }
            }
        }
        Rectangle {
            visible: box.secret
            width: 30; height: 30
            radius: Theme.roundingItem
            color: box.revealed ? Theme.bgSelected : "transparent"
            Text {
                anchors.centerIn: parent
                text: box.revealed ? Icons.eyeOff : Icons.eye
                font.family: Theme.fontFamily
                font.pixelSize: 14
                color: box.revealed ? Theme.fg : Theme.fgMuted
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: box.revealToggled()
            }
        }
    }
}
