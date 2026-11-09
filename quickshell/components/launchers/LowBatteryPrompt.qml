import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../../theme"
import "../../services"
import "../../services/lowBatteryRule.js" as Rule

// Pops up on its own when the battery is critically low (services/lowBatteryRule.js)
// and suggests hibernating. Enter hibernates, Esc dismisses until the next time
// the machine is on AC. Never shown on machines that can't hibernate.
WlrLayershell {
    id: root

    property bool _dismissed: false
    property bool canHibernate: false
    // Keys are ignored for a moment after the prompt appears, so an Enter typed
    // into another window doesn't hibernate by accident.
    property bool _armed: false
    // Focused button: 0 = Hibernate, 1 = Dismiss.
    property int currentIndex: 0
    function activate(idx) { if (idx === 0) hibernate(); else dismiss() }

    function _inputs() {
        return {
            available: BatteryService.available,
            discharging: BatteryService.discharging,
            minutes: BatteryService.timeLeftMinutes,
            capacity: BatteryService.capacity
        }
    }
    readonly property bool shown: Rule.shown(_inputs(), _dismissed, canHibernate)

    // Re-arm the latch whenever the power source changes.
    property Connections batteryConn: Connections {
        target: BatteryService
        function onDischargingChanged() { root._dismissed = Rule.dismissed(root._inputs(), root._dismissed) }
        function onAvailableChanged()   { root._dismissed = Rule.dismissed(root._inputs(), root._dismissed) }
    }

    function hibernate() {
        if (!canHibernate) return
        console.log("[LowBatteryPrompt] exec: systemctl hibernate")
        _dismissed = true
        hibernateProc.running = true
    }
    function dismiss() { _dismissed = true }

    layer: WlrLayer.Overlay
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    visible: shown
    keyboardFocus: shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    onShownChanged: {
        _armed = false
        currentIndex = 0
        if (shown) { armTimer.restart(); Qt.callLater(() => col.forceActiveFocus()) }
    }
    Timer { id: armTimer; interval: 1000; onTriggered: root._armed = true }

    Rectangle { anchors.fill: parent; color: Theme.overlay; MouseArea { anchors.fill: parent } }

    Rectangle {
        id: card
        width: 460
        height: col.implicitHeight + Theme.padL * 2
        anchors.centerIn: parent
        radius: Theme.roundingLauncher
        color: Theme.bgLauncher
        border.width: 1
        border.color: Theme.critical

        ColumnLayout {
            id: col
            anchors.fill: parent
            anchors.margins: Theme.padL
            spacing: Theme.gapM
            focus: true

            Text {
                text: "Battery critical"
                font.family: Theme.fontFamily
                font.pixelSize: 11
                color: Theme.critical
                font.capitalization: Font.AllUppercase
                font.letterSpacing: 1.2
            }
            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border }

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.gapM
                Text { text: Icons.hibernate; font.family: Theme.fontFamily; font.pixelSize: 26; color: Theme.critical; Layout.alignment: Qt.AlignTop }
                Text {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                    color: Theme.fg
                    text: {
                        const parts = []
                        if (BatteryService.timeLeftMinutes >= 0) parts.push("about " + BatteryService.timeLeftMinutes + " min left")
                        if (BatteryService.capacity >= 0) parts.push(BatteryService.capacity + "%")
                        return (parts.length ? "Battery is almost empty (" + parts.join(", ") + "). " : "Battery is almost empty. ")
                            + "Hibernate now to keep your open windows and work, or plug in the charger."
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.gapS
                Repeater {
                    model: [ { label: "Hibernate", danger: true }, { label: "Dismiss", danger: false } ]
                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        readonly property bool selected: root.currentIndex === index
                        Layout.fillWidth: true
                        Layout.preferredHeight: 40
                        radius: Theme.roundingItem
                        color: selected ? Theme.bgSelected : (btnMA.containsMouse ? Theme.bgHover : "transparent")
                        border.width: 1
                        border.color: selected ? (modelData.danger ? Theme.critical : Theme.borderSelected) : Theme.border
                        Text {
                            anchors.centerIn: parent
                            text: modelData.label
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            font.weight: Theme.fontWeightMedium
                            color: Theme.fg
                        }
                        MouseArea {
                            id: btnMA
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { root.currentIndex = index; root.activate(index) }
                        }
                    }
                }
            }

            Text { text: "← → / h l move · Enter select · Esc dismiss"; font.family: Theme.fontFamily; font.pixelSize: 10; color: Theme.fgDim; Layout.alignment: Qt.AlignHCenter }

            Keys.onPressed: (e) => {
                e.accepted = true
                if (!root._armed) return
                if (e.key === Qt.Key_H || e.key === Qt.Key_Left || e.key === Qt.Key_K || e.key === Qt.Key_Up) root.currentIndex = 0
                else if (e.key === Qt.Key_L || e.key === Qt.Key_Right || e.key === Qt.Key_J || e.key === Qt.Key_Down) root.currentIndex = 1
                else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) root.activate(root.currentIndex)
                else if (e.key === Qt.Key_Escape || e.key === Qt.Key_Q) root.dismiss()
            }
        }
    }

    property Process hibernateProc: Process { command: ["systemctl", "hibernate"] }

    // logind says "yes" only with enough swap and a resume device (machine layer).
    property Process hibernateCheck: Process {
        command: ["busctl", "--system", "call", "org.freedesktop.login1", "/org/freedesktop/login1", "org.freedesktop.login1.Manager", "CanHibernate"]
        running: true
        stdout: StdioCollector { onStreamFinished: root.canHibernate = this.text.trim() === 's "yes"' }
    }
}
