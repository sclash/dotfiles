import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../../theme"
import "../../services"
import "NotificationToastCard.qml"

PanelWindow {
    id: toastRoot

    // Visible iff the service has opted in AND has at least one live toast.
    // The center is never auto-opened — this is the only transient surface.
    readonly property bool anyVisible: NotifService.toastEnabled && NotifService.toasts.length > 0
    visible: anyVisible

    // Anchored above the bar in the top-right corner of the primary screen.
    margins {
        top: Theme.barHeight + Theme.padM
        right: Theme.padM
    }
    anchors {
        top: true
        right: true
        bottom: false
        left: false
    }

    // No keyboard interaction — toasts are passive and never grab focus.
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    implicitWidth: 360
    // Height must track the stacked cards — the window only clips its own
    // bounds, so without this the second toast is cut off.
    implicitHeight: stack.implicitHeight

    ColumnLayout {
        id: stack
        anchors.fill: parent
        spacing: Theme.gapS

        Repeater {
            model: NotifService.toasts
            delegate: NotificationToastCard {
                required property var modelData
                toastData: modelData
                onDismissRequested: (id) => NotifService.dismissToast(id)
                onPrimaryAction: (n) => {
                    try {
                        const acts = n && n.actions
                        if (acts && acts.length > 0) acts[0].invoke()
                    } catch(e) {}
                    NotifService.dismissToast(modelData._toastId)
                }
            }
        }
    }

    // Reaper — drop expired toasts, then backfill from the queue.
    Timer {
        interval: 250
        running: toastRoot.anyVisible
        repeat: true
        onTriggered: NotifService.reapExpiredToasts()
    }
}