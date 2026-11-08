import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../../theme"
import "../../services"
import "identity"

// Identity Manager (SUPER+I) — the current user's ways to authenticate:
// password (always on, change it here), face (IR camera, lock screen) and
// fingerprint (reader, lock screen). Main view lists the three methods;
// each opens its own view. Spec: specs/launchers/Identity-Manager.md.
WlrLayershell {
    id: root
    property bool isOpen: false
    property string view: "main"            // main | password | face | fingerprint

    readonly property var current: view === "password" ? passwordView
        : view === "face" ? faceView
        : view === "fingerprint" ? fingerprintView : methodsView

    // While the Face view is open, its own polkit request (pkexec howdy) is
    // answered inline there; otherwise PolkitPrompt shows it.
    Binding { target: PolkitService; property: "faceClaim"; value: root.isOpen && root.view === "face" }

    function open() { isOpen = true }
    function close() {
        passwordView.reset()                 // never keep typed passwords around
        isOpen = false
        view = "main"
    }
    function toggle() { if (isOpen) close(); else open() }
    function refocus() { Qt.callLater(() => viewHost.forceActiveFocus()) }
    function openMethod(name) {
        view = name
        if (name === "password") { passwordView.reset(); Qt.callLater(() => passwordView.focusFirst()) }
        else if (name === "face") { faceView.reset(); refocus() }
        else if (name === "fingerprint") { fingerprintView.reset(); refocus() }
    }
    function backToMain() { view = "main"; refocus() }

    // A view slot: main parks to the left, method views to the right
    // (STYLE.md §2.5 slide + cross-fade).
    component Slide: Item {
        property bool active: false
        property int park: 60
        width: parent ? parent.width : 0
        x: active ? 0 : park
        opacity: active ? 1 : 0
        enabled: active
        visible: opacity > 0.01
        Behavior on x { NumberAnimation { duration: Theme.durationNormal; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: Theme.durationFast } }
    }

    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    visible: isOpen
    keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore
    Rectangle { anchors.fill: parent; color: Theme.overlay; MouseArea { anchors.fill: parent; onClicked: root.close() } }

    Rectangle {
        id: card
        width: 620
        height: Math.min(640, mainCol.implicitHeight + Theme.padL * 2)
        anchors.centerIn: parent
        radius: Theme.roundingLauncher
        color: Theme.bgLauncher
        border.width: 1
        border.color: Theme.borderActive
        clip: true
        Behavior on height { NumberAnimation { duration: Theme.durationNormal; easing.type: Easing.OutCubic } }

        Flickable {
            id: scrollView
            anchors.fill: parent
            anchors.margins: Theme.padL
            clip: true
            contentWidth: width
            contentHeight: mainCol.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar {
                policy: ScrollBar.AsNeeded
                width: 4
                background: Rectangle { color: "transparent" }
                contentItem: Rectangle { color: Theme.borderActive; radius: 2 }
            }

            ColumnLayout {
                id: mainCol
                width: scrollView.width
                spacing: Theme.gapM

                Text {
                    text: "Identity Manager" + (root.view === "password" ? "  ·  Password"
                        : root.view === "face" ? "  ·  Face"
                        : root.view === "fingerprint" ? "  ·  Fingerprint" : "")
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    color: Theme.fgMuted
                    font.capitalization: Font.AllUppercase
                    font.letterSpacing: 1.2
                }
                Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border }

                Item {
                    id: viewHost
                    focus: true
                    Layout.fillWidth: true
                    Layout.preferredHeight: root.current.implicitHeight

                    Slide {
                        active: root.view === "main"; park: -60
                        implicitHeight: methodsView.implicitHeight
                        MethodsView {
                            id: methodsView
                            width: parent.width
                            onOpenMethod: (name) => root.openMethod(name)
                            onCloseRequested: root.close()
                        }
                    }
                    Slide {
                        active: root.view === "password"
                        implicitHeight: passwordView.implicitHeight
                        PasswordView { id: passwordView; width: parent.width; onBack: root.backToMain() }
                    }
                    Slide {
                        active: root.view === "face"
                        implicitHeight: faceView.implicitHeight
                        FaceView { id: faceView; width: parent.width; onBack: root.backToMain(); onRefocus: root.refocus() }
                    }
                    Slide {
                        active: root.view === "fingerprint"
                        implicitHeight: fingerprintView.implicitHeight
                        FingerprintView { id: fingerprintView; width: parent.width; onBack: root.backToMain(); onRefocus: root.refocus() }
                    }
                }
            }
        }

        Keys.onPressed: (e) => root.current.handleKey(e)
    }

    onIsOpenChanged: if (isOpen) {
        root.view = "main"
        methodsView.reset()
        passwordView.reset()
        faceView.reset()
        fingerprintView.reset()
        IdentityService.lastError = ""
        IdentityService.refresh()
        root.refocus()
    }
}
