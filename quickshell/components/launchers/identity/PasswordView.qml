import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../../theme"
import "../../../services"
import "../../../services/identityParse.js" as Parse

// Change the account password. The password is always on and cannot be
// disabled. Fields are cleared on submit and whenever the view is left;
// the values go only to IdentityService.changePassword (→ identity-passwd
// stdin).
Item {
    id: view
    property string formError: ""
    signal back()

    implicitHeight: col.implicitHeight

    function reset() {
        currentField.text = ""
        newField.text = ""
        confirmField.text = ""
        formError = ""
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

    component PwField: Rectangle {
        id: box
        property alias text: field.text
        property alias placeholder: field.placeholderText
        property alias input: field
        signal accepted()
        signal escaped()
        function forceActiveFocus() { field.forceActiveFocus() }
        Layout.fillWidth: true
        Layout.preferredHeight: 36
        radius: Theme.roundingItem
        color: Theme.bgActive
        border.color: field.activeFocus ? Theme.borderSelected : Theme.border
        border.width: 1
        TextField {
            id: field
            anchors.fill: parent
            anchors.leftMargin: Theme.padM
            anchors.rightMargin: Theme.padM
            echoMode: TextInput.Password
            enabled: !IdentityService.passwordBusy && IdentityService.passwordAvailable
            font.family: Theme.fontFamily
            font.pixelSize: 13
            color: Theme.fg
            placeholderTextColor: Theme.fgDim
            background: null
            activeFocusOnTab: true
            inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
            cursorDelegate: Rectangle {
                width: Math.max(6, Math.round(field.font.pixelSize * 0.65))
                height: Math.round(field.font.pixelSize * 1.5)
                color: Theme.fg
            }
            onAccepted: box.accepted()
            Keys.onEscapePressed: (e) => { box.escaped(); e.accepted = true }
        }
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

        PwField {
            id: currentField
            placeholder: "current password"
            onAccepted: newField.forceActiveFocus()
            onEscaped: { view.reset(); view.back() }
        }
        PwField {
            id: newField
            placeholder: "new password"
            onAccepted: confirmField.forceActiveFocus()
            onEscaped: { view.reset(); view.back() }
        }
        PwField {
            id: confirmField
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
            text: "Tab next field · Enter next / change · Esc back"
            font.family: Theme.fontFamily
            font.pixelSize: 10
            color: Theme.fgDim
            Layout.alignment: Qt.AlignHCenter
        }
    }
}
