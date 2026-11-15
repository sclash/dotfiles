import QtQuick
import Quickshell
import Quickshell.Wayland
import "../../theme"
import "../../services"
import "airpods"

// Overlay for the AirPods launcher: the full-screen dim and the 620 px card.
// The card content, the rows and the key routing live in AirPodsView.qml, so
// the same view can be created on its own by the offscreen smoke test.
//
// Opening tells the service the panel is open (which may start librepods),
// which is also why close() must always report the panel closed: a card left
// open would keep the daemon alive in the background.
WlrLayershell {
    id: root
    property bool isOpen: false

    function open() {
        isOpen = true
        AirPodsService.notePanelOpen()
        view.selIndex = 0
        view.clearFilter()
        view.forceActiveFocus()
        AirPodsService.refresh()
    }
    function close() {
        isOpen = false
        AirPodsService.notePanelClosed()
    }
    function toggle() {
        if (isOpen) close()
        else open()
    }

    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    visible: isOpen
    keyboardFocus: WlrKeyboardFocus.Exclusive
    layer: WlrLayer.Overlay
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
        anchors.fill: parent
        color: Theme.overlay
        MouseArea { anchors.fill: parent; onClicked: root.close() }
    }

    Rectangle {
        id: card
        width: 620
        height: Math.min(640, view.implicitHeight)
        anchors.centerIn: parent
        radius: Theme.roundingLauncher
        color: Theme.bgLauncher
        border.width: 1
        border.color: Theme.borderActive
        clip: true

        AirPodsView {
            id: view
            anchors.fill: parent
            onCloseRequested: root.close()
        }

        // The view is the focus item; its keys bubble up to the card and are
        // routed back through the one handleKey() every other caller uses.
        Keys.onPressed: (e) => {
            if (e.key === Qt.Key_Q) { root.close(); e.accepted = true; return }
            if (view.handleKey(e)) e.accepted = true
        }
    }

    onIsOpenChanged: if (isOpen) {
        AirPodsService.refresh()
        Qt.callLater(() => view.forceActiveFocus())
    }
}
