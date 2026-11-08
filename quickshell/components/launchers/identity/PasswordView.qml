import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../../theme"
import "../../../services"
import "../../../services/identityParse.js" as Parse
import ".."                                   // SecretField

// Change the account password. The password is always on and cannot be
// disabled. Fields are cleared on submit and whenever the view is left;
// the values go only to IdentityService.changePassword (→ identity-passwd
// stdin).
Item {
    id: view
    property string formError: ""
    property bool reveal: false                  // one eye toggle for all three fields
    signal back()

    implicitHeight: col.implicitHeight

    function reset() {
        currentField.text = ""
        newField.text = ""
        confirmField.text = ""
        formError = ""
        reveal = false
        IdentityService.clearPasswordMessage()
    }
    function focusFirst() { currentField.forceActiveFocus() }
    function submit() {
        if (IdentityService.passwordBusy || !IdentityService.passwordAvailable) return
        const err = Parse.validatePasswordForm(currentField.text, newField.text, confirmField.text)
        formError = err
        if (err !== "") {
            if (err.indexOf("match") !== -1) { confirmField.text = ""; confirmField.forceActiveFocus() }
            return
        }
        IdentityService.changePassword(currentField.text, newField.text)
        currentField.text = ""
        newField.text = ""
        confirmField.text = ""
        currentField.forceActiveFocus()
    }
    // Keys that the text fields do not consume land here.
    function handleKey(e) {
        if (e.key === Qt.Key_Escape) { view.reset(); view.back(); e.accepted = true }
    }

    Connections {
        target: IdentityService
        function onDataUpdated() { if (IdentityService.passwordMessage !== "") view.formError = "" }
    }

    ColumnLayout {
        id: col
        width: parent.width
        spacing: Theme.gapM

        RowLayout {
            spacing: Theme.gapM
            Text { text: Icons.key; font.family: Theme.fontFamily; font.pixelSize: 16; color: Theme.fg }
            Text { text: "Change password"; font.family: Theme.fontFamily; font.pixelSize: 13; font.weight: Theme.fontWeightMedium; color: Theme.fg }
            Item { Layout.fillWidth: true }
            Text { text: "always on"; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; color: Theme.fgMuted }
        }

        SecretField {
            id: currentField
            revealed: view.reveal
            fieldEnabled: !IdentityService.passwordBusy && IdentityService.passwordAvailable
            onRevealToggled: view.reveal = !view.reveal
            placeholder: "current password"
            onAccepted: newField.forceActiveFocus()
            onEscaped: { view.reset(); view.back() }
        }
        SecretField {
            id: newField
            revealed: view.reveal
            fieldEnabled: !IdentityService.passwordBusy && IdentityService.passwordAvailable
            onRevealToggled: view.reveal = !view.reveal
            placeholder: "new password"
            onAccepted: confirmField.forceActiveFocus()
            onEscaped: { view.reset(); view.back() }
        }
        SecretField {
            id: confirmField
            revealed: view.reveal
            fieldEnabled: !IdentityService.passwordBusy && IdentityService.passwordAvailable
            onRevealToggled: view.reveal = !view.reveal
            placeholder: "repeat new password"
            onAccepted: view.submit()
            onEscaped: { view.reset(); view.back() }
        }

        Text {
            readonly property string msg: view.formError !== "" ? view.formError : IdentityService.passwordMessage
            visible: msg !== "" || !IdentityService.passwordAvailable
            text: !IdentityService.passwordAvailable
                ? Icons.warning + " identity-passwd is not installed — run update"
                : (view.formError !== "" || (!IdentityService.passwordOk && !IdentityService.passwordBusy) ? Icons.warning + " " : "") + msg
            font.family: Theme.fontFamily
            font.pixelSize: 11
            color: (view.formError !== "" || !IdentityService.passwordAvailable || (!IdentityService.passwordOk && !IdentityService.passwordBusy))
                ? Theme.critical : Theme.fg
            Layout.fillWidth: true
            wrapMode: Text.Wrap
        }

        Text {
            text: "Tab next field · Enter next / change · Ctrl+s show/hide · Esc back"
            font.family: Theme.fontFamily
            font.pixelSize: 10
            color: Theme.fgDim
            Layout.alignment: Qt.AlignHCenter
        }
    }
}
