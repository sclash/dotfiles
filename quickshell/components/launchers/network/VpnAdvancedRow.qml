import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../../theme"
import ".."                                   // SecretField

// One Advanced row of VpnFormView: `key = value`. Edits write straight into
// `entry` (an element of VpnFormView.advanced). Rows read from the profile
// keep their kind; a new row has a Data | Secret chip. A secret row masks its
// value and has a Save | Ask chip. Clearing the key removes the row on save.
RowLayout {
    id: row
    property var entry: ({ key: "", value: "", secret: false, mode: "save", stored: false, existing: false })
    property bool revealed: false
    property bool isSecret: entry.secret === true
    property string mode: entry.mode || "save"
    signal changed()
    signal revealToggled()
    signal advance(var from)
    signal escaped()

    function focusKey() { keyBox.forceActiveFocus() }
    Component.onCompleted: if (row.isSecret) secretBox.text = row.entry.value || ""

    Layout.fillWidth: true
    spacing: Theme.gapS

    Rectangle {
        Layout.preferredWidth: 170
        Layout.preferredHeight: 36
        radius: Theme.roundingItem
        color: Theme.bgActive
        border.color: keyBox.activeFocus ? Theme.borderSelected : Theme.border
        border.width: 1
        TextField {
            id: keyBox
            anchors.fill: parent
            anchors.leftMargin: Theme.padM
            anchors.rightMargin: Theme.padM
            text: row.entry.key
            placeholderText: "key"
            font.family: Theme.fontFamily
            font.pixelSize: 12
            color: Theme.fg
            placeholderTextColor: Theme.fgDim
            background: null
            cursorDelegate: Rectangle {
                width: Math.max(6, Math.round(parent.font.pixelSize * 0.65))
                height: Math.round(parent.font.pixelSize * 1.5)
                color: Theme.fg
                opacity: parent.activeFocus ? 1 : 0
            }
            activeFocusOnTab: true
            onTextEdited: { row.entry.key = text; row.changed() }
            onAccepted: row.advance(keyBox)
        }
    }
    Text { text: "="; font.family: Theme.fontFamily; font.pixelSize: 12; color: Theme.fgDim }
    VpnChip {
        visible: !row.entry.existing
        first: "Data"
        second: "Secret"
        isSecond: row.isSecret
        onToggled: {
            row.entry.secret = !row.isSecret
            row.isSecret = row.entry.secret
            row.entry.value = ""
            valueBox.text = ""
            secretBox.text = ""
            row.changed()
        }
        onAdvance: (from) => row.advance(from)
    }
    Rectangle {
        visible: !row.isSecret
        Layout.fillWidth: true
        Layout.preferredHeight: 36
        radius: Theme.roundingItem
        color: Theme.bgActive
        border.color: valueBox.activeFocus ? Theme.borderSelected : Theme.border
        border.width: 1
        TextField {
            id: valueBox
            anchors.fill: parent
            anchors.leftMargin: Theme.padM
            anchors.rightMargin: Theme.padM
            text: row.isSecret ? "" : row.entry.value
            placeholderText: "value"
            font.family: Theme.fontFamily
            font.pixelSize: 12
            color: Theme.fg
            placeholderTextColor: Theme.fgDim
            background: null
            cursorDelegate: Rectangle {
                width: Math.max(6, Math.round(parent.font.pixelSize * 0.65))
                height: Math.round(parent.font.pixelSize * 1.5)
                color: Theme.fg
                opacity: parent.activeFocus ? 1 : 0
            }
            activeFocusOnTab: true
            onTextEdited: { row.entry.value = text; row.changed() }
            onAccepted: row.advance(valueBox)
        }
    }
    SecretField {
        id: secretBox
        visible: row.isSecret
        revealed: row.revealed
        fieldEnabled: row.mode !== "ask"
        placeholder: row.mode === "ask" ? "asked when you connect" : (row.entry.stored ? "saved · leave empty to keep" : "value")
        onTextChanged: if (row.isSecret) { row.entry.value = text; if (text !== "") row.changed() }
        onRevealToggled: row.revealToggled()
        onAccepted: row.advance(secretBox.input)
        onEscaped: row.escaped()
    }
    VpnChip {
        visible: row.isSecret
        first: "Save"
        second: "Ask"
        isSecond: row.mode === "ask"
        onToggled: {
            row.entry.mode = row.mode === "ask" ? "save" : "ask"
            row.mode = row.entry.mode
            if (row.mode === "ask") { row.entry.value = ""; secretBox.text = "" }
            row.changed()
        }
        onAdvance: (from) => row.advance(from)
    }
}
