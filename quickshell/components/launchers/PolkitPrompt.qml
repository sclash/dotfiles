import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../../theme"
import "../../services"

// Polkit password prompt for any app (udisks, pkexec, …): Quickshell is the
// session's authentication agent (PolkitService). Requests the Identity
// Manager's Face view answers inline never show here. Clicking outside does
// nothing on purpose: only Enter or Esc decide.
WlrLayershell {
    id: root
    readonly property bool shown: PolkitService.active && !PolkitService.faceInline
    property bool reveal: false

    layer: WlrLayer.Overlay
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    visible: shown
    keyboardFocus: shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    onShownChanged: {
        field.text = ""
        reveal = false
        if (shown) Qt.callLater(() => field.forceActiveFocus())
    }

    Rectangle { anchors.fill: parent; color: Theme.overlay; MouseArea { anchors.fill: parent } }

    Rectangle {
        id: card
        width: 460
        height: col.implicitHeight + Theme.padL * 2
        anchors.centerIn: parent
        radius: Theme.roundingLauncher
        color: Theme.bgLauncher
        border.width: 1
        border.color: Theme.borderActive

        ColumnLayout {
            id: col
            anchors.fill: parent
            anchors.margins: Theme.padL
            spacing: Theme.gapM

            Text {
                text: "Authentication required"
                font.family: Theme.fontFamily
                font.pixelSize: 11
                color: Theme.fgMuted
                font.capitalization: Font.AllUppercase
                font.letterSpacing: 1.2
            }
            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border }

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.gapM
                Text { text: Icons.lock; font.family: Theme.fontFamily; font.pixelSize: 18; color: Theme.fg; Layout.alignment: Qt.AlignTop }
                Text {
                    text: PolkitService.flow !== null ? PolkitService.flow.message : ""
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                    color: Theme.fg
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                }
            }

            SecretField {
                id: field
                placeholder: PolkitService.flow !== null && PolkitService.flow.inputPrompt !== ""
                    ? PolkitService.flow.inputPrompt.replace(/:\s*$/, "") : "password"
                revealed: root.reveal || (PolkitService.flow !== null && PolkitService.flow.responseVisible)
                fieldEnabled: PolkitService.flow !== null && PolkitService.flow.isResponseRequired
                onRevealToggled: root.reveal = !root.reveal
                onAccepted: { PolkitService.submit(text); text = "" }
                onEscaped: { PolkitService.cancel(); text = "" }
            }

            Text {
                visible: PolkitService.flow !== null && PolkitService.flow.supplementaryMessage !== ""
                text: PolkitService.flow !== null ? PolkitService.flow.supplementaryMessage : ""
                font.family: Theme.fontFamily
                font.pixelSize: 11
                color: PolkitService.flow !== null && PolkitService.flow.supplementaryIsError ? Theme.critical : Theme.fgMuted
                Layout.fillWidth: true
                wrapMode: Text.Wrap
            }

            Text {
                text: "Enter authenticate · Ctrl+s show/hide · Esc cancel"
                font.family: Theme.fontFamily
                font.pixelSize: 10
                color: Theme.fgDim
                Layout.alignment: Qt.AlignHCenter
            }
        }
    }
}
