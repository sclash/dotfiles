import QtQuick
import QtQuick.Layouts
import "../../../theme"
import "../../../services"

// Main view: Password, Face, Fingerprint. Enter opens a method, `t` flips
// face/fingerprint when their hardware is present.
Item {
    id: view
    property int sel: 0
    readonly property var methods: ["password", "face", "fingerprint"]
    signal openMethod(string name)
    signal closeRequested()

    implicitHeight: col.implicitHeight

    function stateLabel(state) {
        return state === "enabled" ? "Enabled" : state === "disabled" ? "Disabled" : "Not available"
    }
    function count(n, one, many) { return n + " " + (n === 1 ? one : many) }
    function reset() { sel = 0 }
    function toggleSelected() {
        const m = methods[sel]
        if (m === "face" && IdentityService.faceState !== "unavailable")
            IdentityService.setChoice("face", IdentityService.faceState !== "enabled")
        else if (m === "fingerprint" && IdentityService.fingerprintState !== "unavailable")
            IdentityService.setChoice("fingerprint", IdentityService.fingerprintState !== "enabled")
    }
    function handleKey(e) {
        if (e.key === Qt.Key_Escape) { view.closeRequested(); e.accepted = true }
        else if (e.key === Qt.Key_J || e.key === Qt.Key_Down) { sel = Math.min(methods.length - 1, sel + 1); e.accepted = true }
        else if (e.key === Qt.Key_K || e.key === Qt.Key_Up) { sel = Math.max(0, sel - 1); e.accepted = true }
        else if (e.key === Qt.Key_Home) { sel = 0; e.accepted = true }
        else if (e.key === Qt.Key_End) { sel = methods.length - 1; e.accepted = true }
        else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_L) { view.openMethod(methods[sel]); e.accepted = true }
        else if (e.key === Qt.Key_T || e.key === Qt.Key_Space) { toggleSelected(); e.accepted = true }
        else if (e.key === Qt.Key_R) { IdentityService.refresh(); e.accepted = true }
    }

    ColumnLayout {
        id: col
        width: parent.width
        spacing: Theme.gapM

        MethodRow {
            icon: Icons.key
            title: "Password"
            note: "always on · used everywhere"
            stateText: "Change…"
            selected: view.sel === 0
            onClicked: { view.sel = 0; view.openMethod("password") }
        }
        MethodRow {
            icon: Icons.face
            title: "Face"
            note: "lock screen · IR camera"
            stateText: {
                const s = view.stateLabel(IdentityService.faceState)
                return IdentityService.faceState === "unavailable" ? s
                    : s + " · " + view.count(IdentityService.faceModels.length, "model", "models")
            }
            dim: IdentityService.faceState !== "enabled"
            selected: view.sel === 1
            onClicked: { view.sel = 1; view.openMethod("face") }
        }
        MethodRow {
            icon: Icons.fingerprint
            title: "Fingerprint"
            note: "lock screen · fingerprint reader"
            stateText: {
                const s = view.stateLabel(IdentityService.fingerprintState)
                return IdentityService.fingerprintState === "unavailable" ? s
                    : s + " · " + view.count(IdentityService.enrolled.length, "finger", "fingers")
            }
            dim: IdentityService.fingerprintState !== "enabled"
            selected: view.sel === 2
            onClicked: { view.sel = 2; view.openMethod("fingerprint") }
        }

        Text {
            text: "j/k move · Enter open · t toggle · r refresh · Esc close"
            font.family: Theme.fontFamily
            font.pixelSize: 10
            color: Theme.fgDim
            Layout.alignment: Qt.AlignHCenter
        }
    }
}
