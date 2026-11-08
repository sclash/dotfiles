import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../../theme"
import "../../../services"

// Face unlock (Howdy, lock screen only): on/off toggle and the user's face
// models. Adding or removing a model asks for the password through polkit
// (Howdy keeps models in /var/lib/howdy, owned by root).
Item {
    id: view
    property string mode: "list"            // list | label
    property int sel: 0                     // 0 = toggle, 1.. = models
    property string confirmText: ""
    property var pendingRemove: null
    signal back()

    readonly property bool available: IdentityService.faceState !== "unavailable"
    readonly property int count: 1 + IdentityService.faceModels.length

    implicitHeight: col.implicitHeight

    function reset() { mode = "list"; sel = 0; confirmText = ""; pendingRemove = null; labelField.text = "" }
    function fmtDate(t) { return t > 0 ? Qt.formatDate(new Date(t * 1000), "yyyy-MM-dd") : "" }
    function toggle() {
        if (available) IdentityService.setChoice("face", IdentityService.faceState !== "enabled")
    }
    function startAdd() {
        if (!available || IdentityService.faceBusy) return
        mode = "label"
        labelField.text = ""
        labelField.forceActiveFocus()
    }
    function confirmAdd() {
        IdentityService.addFace(labelField.text)
        labelField.text = ""
        mode = "list"
    }
    function requestRemove() {
        const m = IdentityService.faceModels[sel - 1]
        if (!m || IdentityService.faceBusy) return
        pendingRemove = m
        confirmText = 'Remove "' + m.label + '"?  y / n'
    }
    function handleKey(e) {
        if (confirmText !== "") {
            if (e.key === Qt.Key_Y) { IdentityService.removeFace(pendingRemove.id); confirmText = ""; pendingRemove = null; e.accepted = true }
            else if (e.key === Qt.Key_N || e.key === Qt.Key_Escape) { confirmText = ""; pendingRemove = null; e.accepted = true }
            return
        }
        if (mode === "label") {
            if (e.key === Qt.Key_Escape) { mode = "list"; labelField.text = ""; e.accepted = true; view.refocus() }
            return
        }
        if (e.key === Qt.Key_Escape || e.key === Qt.Key_H) { view.back(); e.accepted = true }
        else if (e.key === Qt.Key_J || e.key === Qt.Key_Down) { sel = Math.min(count - 1, sel + 1); e.accepted = true }
        else if (e.key === Qt.Key_K || e.key === Qt.Key_Up) { sel = Math.max(0, sel - 1); e.accepted = true }
        else if (e.key === Qt.Key_T || e.key === Qt.Key_Space) { toggle(); e.accepted = true }
        else if (e.key === Qt.Key_A || e.key === Qt.Key_E) { startAdd(); e.accepted = true }
        else if (e.key === Qt.Key_D) { if (sel > 0) requestRemove(); e.accepted = true }
        else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { if (sel === 0) toggle(); else requestRemove(); e.accepted = true }
        else if (e.key === Qt.Key_R) { IdentityService.refresh(); e.accepted = true }
    }
    signal refocus()

    Connections {
        target: IdentityService
        function onDataUpdated() { view.sel = Math.max(0, Math.min(view.sel, view.count - 1)) }
    }

    ColumnLayout {
        id: col
        width: parent.width
        spacing: Theme.gapM

        MethodRow {
            icon: Icons.face
            title: "Unlock with face"
            note: view.available ? "lock screen only · press Enter, then look at the camera" : ""
            stateText: IdentityService.faceState === "enabled" ? "Enabled"
                : IdentityService.faceState === "disabled" ? "Disabled" : "Not available"
            dim: IdentityService.faceState !== "enabled"
            selected: view.sel === 0 && view.mode === "list"
            onClicked: { view.sel = 0; view.toggle() }
        }

        Text {
            visible: view.available
            text: "Face models"
            font.family: Theme.fontFamily
            font.pixelSize: 11
            color: Theme.fgMuted
        }
        Text {
            visible: view.available && IdentityService.faceModels.length === 0
            text: "No face models yet — press a to add one"
            font.family: Theme.fontFamily
            font.pixelSize: 11
            color: Theme.fgMuted
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
        }
        Repeater {
            model: view.available ? IdentityService.faceModels : []
            delegate: Rectangle {
                required property var modelData
                required property int index
                readonly property bool isSel: view.sel === index + 1 && view.mode === "list"
                Layout.fillWidth: true
                implicitHeight: 40
                radius: Theme.roundingItem
                color: isSel ? Theme.bgSelected : (fma.containsMouse ? Theme.bgHover : "transparent")
                border.color: isSel ? Theme.borderSelected : "transparent"
                border.width: 1
                MouseArea { id: fma; anchors.fill: parent; hoverEnabled: true; onClicked: view.sel = index + 1 }
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.padM
                    anchors.rightMargin: Theme.padM
                    spacing: Theme.gapM
                    Text { text: Icons.face; font.family: Theme.fontFamily; font.pixelSize: 16; color: Theme.fg }
                    Text {
                        text: modelData.label
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                        color: Theme.fg
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }
                    Text { text: view.fmtDate(modelData.time); font.family: Theme.fontFamily; font.pixelSize: 10; color: Theme.fgMuted }
                }
            }
        }

        // Label entry for a new model.
        Rectangle {
            visible: view.mode === "label"
            Layout.fillWidth: true
            Layout.preferredHeight: 36
            radius: Theme.roundingItem
            color: Theme.bgActive
            border.color: labelField.activeFocus ? Theme.borderSelected : Theme.border
            border.width: 1
            TextField {
                id: labelField
                anchors.fill: parent
                anchors.leftMargin: Theme.padM
                anchors.rightMargin: Theme.padM
                maximumLength: 24
                placeholderText: "label (e.g. glasses) — Enter to start"
                font.family: Theme.fontFamily
                font.pixelSize: 13
                color: Theme.fg
                placeholderTextColor: Theme.fgDim
                background: null
                cursorDelegate: Rectangle {
                    width: Math.max(6, Math.round(labelField.font.pixelSize * 0.65))
                    height: Math.round(labelField.font.pixelSize * 1.5)
                    color: Theme.fg
                }
                onAccepted: { view.confirmAdd(); view.refocus() }
                Keys.onEscapePressed: (e) => { view.mode = "list"; text = ""; e.accepted = true; view.refocus() }
            }
        }

        // Progress / outcome of the last add or remove.
        Text {
            visible: IdentityService.faceMessage !== ""
            text: (IdentityService.faceBusy ? Icons.face : (IdentityService.faceMessageIsError ? Icons.warning : Icons.check))
                + " " + IdentityService.faceMessage
            font.family: Theme.fontFamily
            font.pixelSize: 11
            color: IdentityService.faceMessageIsError ? Theme.critical : Theme.fg
            Layout.fillWidth: true
            wrapMode: Text.Wrap
        }
        Text {
            visible: IdentityService.faceNeedsEmitter
            text: "The IR light looks off. Run once: sudo linux-enable-ir-emitter configure"
            font.family: Theme.fontFamily
            font.pixelSize: 10
            color: Theme.fgMuted
            Layout.fillWidth: true
            wrapMode: Text.Wrap
        }

        // Why it is unavailable.
        Text {
            visible: !view.available
            text: !IdentityService.howdyAvailable
                ? "Howdy is not installed — run update"
                : "No IR camera detected" + (IdentityService.irDevice !== "" ? " (" + IdentityService.irDevice + ")" : "")
            font.family: Theme.fontFamily
            font.pixelSize: 11
            color: Theme.fgMuted
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
        }

        Text {
            text: view.confirmText !== "" ? view.confirmText
                : view.mode === "label" ? "Enter add · Esc cancel"
                : view.available ? "j/k move · t toggle · a add · d remove · Esc back"
                : "Esc back"
            font.family: Theme.fontFamily
            font.pixelSize: 10
            color: view.confirmText !== "" ? Theme.critical : Theme.fgDim
            Layout.alignment: Qt.AlignHCenter
        }
    }
}
