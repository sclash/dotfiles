import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../../theme"
import "../../../services/vpnSchema.js" as Schema
import ".."                                   // SecretField

// One stop of VpnFormView, drawn from a vpnSchema.js field:
//   text | file | number → text box     secret → SecretField + Save | Ask chip
//   bool → toggle (Space)               choice → value cycled with Space / h / l
// Enter emits advance(from) so the form moves on; Tab follows the focus chain.
// A secret's value stays in its SecretField until the form collects it.
ColumnLayout {
    id: stop
    property var field: ({ key: "", label: "", kind: "text" })
    property string initial: ""          // text / file / number / choice value
    property bool checked: false         // bool value
    property string mode: "save"         // secret: save | ask
    property bool stored: false          // secret already saved in the profile
    property bool revealed: false
    readonly property string kind: field.kind || "text"
    readonly property bool askable: field.askable !== false
    readonly property bool asking: kind === "secret" && askable && mode === "ask"
    signal edited(var value)             // secrets emit null: their value stays here
    signal modeToggled()
    signal revealToggled()
    signal advance(var from)
    signal escaped()

    function focusInput() {
        if (kind === "secret") { if (asking) chip.forceActiveFocus(); else secret.forceActiveFocus() }
        else if (kind === "bool") toggle.forceActiveFocus()
        else if (kind === "choice") choice.forceActiveFocus()
        else box.forceActiveFocus()
    }
    function boxText() { return box.text }
    function setText(t) { box.text = t }
    onAskingChanged: if (asking) secret.text = ""
    function secretText() { return secret.text }
    function clearSecret() { secret.text = "" }
    function setChoice(step) {
        const v = Schema.cycleChoice(stop.field, stop.initial, step)
        stop.initial = v
        stop.edited(v)
    }
    function flip() { stop.checked = !stop.checked; stop.edited(stop.checked) }

    Layout.fillWidth: true
    spacing: 2

    Text {
        visible: stop.kind !== "bool"
        text: stop.field.label + (stop.field.required ? " *" : "")
        font.family: Theme.fontFamily
        font.pixelSize: 10
        color: Theme.fgMuted
    }

    // text / file / number
    Rectangle {
        visible: stop.kind === "text" || stop.kind === "file" || stop.kind === "number"
        Layout.fillWidth: true
        Layout.preferredHeight: 36
        radius: Theme.roundingItem
        color: Theme.bgActive
        border.color: box.activeFocus ? Theme.borderSelected : Theme.border
        border.width: 1
        TextField {
            id: box
            anchors.fill: parent
            anchors.leftMargin: Theme.padM
            anchors.rightMargin: Theme.padM
            text: stop.initial
            placeholderText: stop.field.placeholder || (stop.kind === "file" ? "~/path/to/file" : "")
            inputMethodHints: stop.kind === "number" ? Qt.ImhDigitsOnly : Qt.ImhNone
            font.family: Theme.fontFamily
            font.pixelSize: 13
            color: Theme.fg
            placeholderTextColor: Theme.fgDim
            background: null
            cursorDelegate: Rectangle {
                width: Math.max(6, Math.round(parent.font.pixelSize * 0.65))
                height: Math.round(parent.font.pixelSize * 1.5)
                color: Theme.fg
                // Qt leaves the delegate visible after focus moves to another field.
                opacity: parent.activeFocus ? 1 : 0
            }
            activeFocusOnTab: true
            onTextEdited: stop.edited(text)
            onAccepted: stop.advance(box)
        }
    }

    // secret
    RowLayout {
        visible: stop.kind === "secret"
        Layout.fillWidth: true
        spacing: Theme.gapS
        SecretField {
            id: secret
            revealed: stop.revealed
            fieldEnabled: !stop.asking
            placeholder: stop.asking ? "asked when you connect"
                : (stop.stored ? "saved · leave empty to keep" : "")
            onRevealToggled: stop.revealToggled()
            onAccepted: stop.advance(secret.input)
            onEscaped: stop.escaped()
            onTextChanged: if (text !== "") stop.edited(null)
        }
        VpnChip {
            id: chip
            visible: stop.askable
            first: "Save"
            second: "Ask"
            isSecond: stop.mode === "ask"
            onToggled: stop.modeToggled()
            onAdvance: (from) => stop.advance(from)
        }
    }

    // bool
    Rectangle {
        id: toggle
        visible: stop.kind === "bool"
        Layout.fillWidth: true
        Layout.preferredHeight: 36
        radius: Theme.roundingItem
        color: "transparent"
        border.color: toggle.activeFocus ? Theme.borderSelected : Theme.border
        border.width: 1
        activeFocusOnTab: true
        Keys.onPressed: (e) => {
            if (e.key === Qt.Key_Space) { stop.flip(); e.accepted = true }
            else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { stop.advance(toggle); e.accepted = true }
        }
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Theme.padM
            anchors.rightMargin: Theme.padM
            spacing: Theme.gapM
            Text { text: stop.checked ? Icons.check : ""; font.family: Theme.fontFamily; font.pixelSize: 13; color: Theme.fg; Layout.preferredWidth: 16 }
            Text { text: stop.field.label; font.family: Theme.fontFamily; font.pixelSize: 13; color: Theme.fg; elide: Text.ElideRight; Layout.fillWidth: true }
            Text { text: stop.checked ? "on" : "off"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fgMuted }
        }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { toggle.forceActiveFocus(); stop.flip() } }
    }

    // choice
    Rectangle {
        id: choice
        visible: stop.kind === "choice"
        Layout.fillWidth: true
        Layout.preferredHeight: 36
        radius: Theme.roundingItem
        color: "transparent"
        border.color: choice.activeFocus ? Theme.borderSelected : Theme.border
        border.width: 1
        activeFocusOnTab: true
        Keys.onPressed: (e) => {
            if (e.key === Qt.Key_Space || e.key === Qt.Key_L || e.key === Qt.Key_Right) { stop.setChoice(1); e.accepted = true }
            else if (e.key === Qt.Key_H || e.key === Qt.Key_Left) { stop.setChoice(-1); e.accepted = true }
            else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { stop.advance(choice); e.accepted = true }
        }
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Theme.padM
            anchors.rightMargin: Theme.padM
            Text { text: Icons.chevronLeft; font.family: Theme.fontFamily; font.pixelSize: 12; color: Theme.fgMuted }
            Text {
                text: Schema.choiceLabel(stop.field, stop.initial)
                font.family: Theme.fontFamily
                font.pixelSize: 13
                color: Theme.fg
                horizontalAlignment: Text.AlignHCenter
                Layout.fillWidth: true
            }
            Text { text: Icons.chevronRight; font.family: Theme.fontFamily; font.pixelSize: 12; color: Theme.fgMuted }
        }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { choice.forceActiveFocus(); stop.setChoice(1) } }
    }
}
