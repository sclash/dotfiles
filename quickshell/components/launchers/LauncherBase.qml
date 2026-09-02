import QtQuick
import "../../theme"
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

WlrLayershell {
    id: root
    property int cardWidth: 600
    property string launcherName: ""
    property bool isOpen: false
    signal closed()

    function open() { isOpen = true; visible = true }
    function close() { isOpen = false; visible = false; closed() }
    function toggle() { if (isOpen) close(); else open() }

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    color: "transparent"
    visible: isOpen
    keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore
    // WlrLayershell full-screen overlay: keyboardFocus Exclusive grabs keys when mapped; Ignore avoids reserving space.

    // Dim overlay
    Rectangle {
        anchors.fill: parent
        color: Theme.overlay
        visible: root.isOpen
        MouseArea {
            anchors.fill: parent
            onClicked: root.close()
        }
    }

    // Centered card
    Rectangle {
        id: card
        width: root.cardWidth
        anchors.centerIn: parent
        radius: Theme.roundingLauncher
        color: Theme.bgLauncher
        border.width: Theme.borderWidth
        border.color: Theme.borderActive
        clip: true
        focus: true

        // Content slot — children will reparent via default property
        default property alias _content: innerLayout.data

        ColumnLayout {
            id: innerLayout
            anchors.fill: parent
            anchors.margins: Theme.padM
            spacing: Theme.gapM
        }

        Keys.onEscapePressed: root.close()
    }

    onIsOpenChanged: {
        if (isOpen) card.forceActiveFocus()
    }
}
