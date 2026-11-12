import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../theme"

// Masked text field with a show/hide eye (click, or Ctrl+S), matching the
// Network Center's Wi-Fi password field. `revealed` is controlled by the
// parent, so several fields can share one toggle: handle revealToggled.
Rectangle {
    id: box
    property alias text: field.text
    property alias placeholder: field.placeholderText
    property alias input: field
    property bool revealed: false
    property bool fieldEnabled: true
    signal accepted()
    signal escaped()
    signal revealToggled()
    function forceActiveFocus() { field.forceActiveFocus() }

    Layout.fillWidth: true
    Layout.preferredHeight: 36
    radius: Theme.roundingItem
    color: Theme.bgActive
    border.color: field.activeFocus ? Theme.borderSelected : Theme.border
    border.width: 1

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Theme.padM
        anchors.rightMargin: Theme.padS
        spacing: Theme.gapS
        TextField {
            id: field
            Layout.fillWidth: true
            echoMode: box.revealed ? TextInput.Normal : TextInput.Password
            enabled: box.fieldEnabled
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
                opacity: parent.activeFocus ? 1 : 0
            }
            onAccepted: box.accepted()
            Keys.onEscapePressed: (e) => { box.escaped(); e.accepted = true }
            Keys.onPressed: (e) => {
                if (e.key === Qt.Key_S && (e.modifiers & Qt.ControlModifier)) { box.revealToggled(); e.accepted = true }
            }
        }
        Rectangle {
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
