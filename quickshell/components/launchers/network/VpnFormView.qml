import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../../theme"
import "../../../services"
import "../../../services/vpnSchema.js" as Schema

// Add or edit one VPN profile (spec §9). Stops: Name, the type's schema
// fields, Common, then a collapsed Advanced section with every other vpn.data
// key. Saved secrets never come back from nm-vpn: their boxes stay empty
// ("saved · leave empty to keep"). Typed secrets are cleared as soon as they
// are handed to NetworkService.vpnSave, and on reset.
//
// `values`, `modes` and `advanced` are edited in place, so typing never
// rebuilds the stops. The *Rev counters say when a rebuild or re-read is due.
Item {
    id: view
    property string type: ""
    property string uuid: ""                  // "" = new profile
    property string profileName: ""           // name when opened, for the title
    property string name: ""
    property string nameInit: ""
    property var values: ({})
    property var modes: ({})
    property var stored: ({})
    property var absent: ({})                 // schema keys the loaded profile lacks
    property var touched: ({})                // fields edited since opening
    property var advanced: []
    property bool advancedOpen: false
    property int formRev: 0                   // rebuilds every stop
    property int shownRev: 0                  // re-evaluates showIf
    property int modeRev: 0                   // re-reads secret modes
    property int advRev: 0                    // rebuilds the Advanced rows
    property bool dirty: false
    property bool busy: false
    property bool reveal: false
    property string formError: ""
    property string confirmText: ""
    readonly property bool isEdit: uuid !== ""
    readonly property bool isWireGuard: type === "wireguard"
    readonly property int peerCount: { view.formRev; return Number(view.values["peer.count"] || 0) }
    signal back()
    signal saved()
    signal refocus()

    implicitHeight: col.implicitHeight

    function clearSecrets() {
        for (let i = 0; i < rep.count; i++) { const it = rep.itemAt(i); if (it && it.kind === "secret") it.clearSecret() }
        for (let j = 0; j < advanced.length; j++) if (advanced[j].secret) advanced[j].value = ""
        advRev++
    }
    function reset() {
        clearSecrets()
        type = ""; uuid = ""; profileName = ""; name = ""; nameInit = ""
        values = ({}); modes = ({}); stored = ({}); absent = ({}); touched = ({}); advanced = []
        advancedOpen = false; dirty = false; busy = false; reveal = false
        formError = ""; confirmText = ""
        formRev++; advRev++
        syncName()
    }
    function startAdd(t) {
        reset()
        values = Schema.defaults(t)
        modes = Schema.defaultModes(t)
        type = t
        advancedOpen = !Schema.hasSchema(t)
        formRev++; advRev++
        syncName()
        Qt.callLater(focusFirst)
    }
    function startEdit(profile) {
        reset()
        const s = Schema.fromProfile(profile)
        values = s.values; modes = s.modes; stored = s.stored; absent = s.absent; advanced = s.advanced
        uuid = s.uuid; profileName = s.name; name = s.name; nameInit = s.name
        type = s.type
        advancedOpen = !Schema.hasSchema(s.type)
        formRev++; advRev++
        syncName()
        Qt.callLater(focusFirst)
    }
    function syncName() { nameStop.setText(view.name) }
    function focusFirst() { nameStop.focusInput() }
    function next(from) {
        if (!from) return
        const n = from.nextItemInFocusChain(true)
        if (n) n.forceActiveFocus()
    }
    function fieldEdited(field, v) {
        if (field.kind !== "secret") values[field.key] = v
        touched[field.key] = true
        dirty = true
        formError = ""
        if (field.kind === "bool" || field.kind === "choice") shownRev++
    }
    function toggleMode(key) { modes[key] = modes[key] === "ask" ? "save" : "ask"; modeRev++; dirty = true }
    function addRow() {
        advanced.push({ key: "", value: "", secret: false, mode: "save", stored: false, existing: false })
        advRev++
        dirty = true
        Qt.callLater(() => { const r = advRep.itemAt(advRep.count - 1); if (r) r.focusKey() })
    }
    function stopFor(key) {
        if (key === "name") return nameStop
        for (let i = 0; i < rep.count; i++) { const it = rep.itemAt(i); if (it && it.field.key === key) return it }
        return null
    }
    function visibleKeys() {
        const out = []
        for (let i = 0; i < rep.count; i++) { const it = rep.itemAt(i); if (it && it.visible) out.push(it.field.key) }
        return out
    }
    function collectSecrets() {
        const sv = {}
        for (let i = 0; i < rep.count; i++) {
            const it = rep.itemAt(i)
            if (it && it.kind === "secret" && it.visible && !it.asking) sv[it.field.key] = it.secretText()
        }
        return sv
    }
    function save() {
        if (busy || type === "") return
        const st = { type: type, uuid: uuid, name: name, values: values, modes: modes, stored: stored,
                     secretValues: collectSecrets(), advanced: advanced, absent: absent, touched: touched }
        const err = Schema.validate(st)
        if (err) {
            formError = err.message
            if (err.key === "advanced") { advancedOpen = true; advHeader.forceActiveFocus() }
            else { const s = stopFor(err.key); if (s) s.focusInput() }
            return
        }
        const req = Schema.buildRequest(st)
        clearSecrets()
        busy = true
        formError = ""
        NetworkService.vpnSave(req, r => {
            view.busy = false
            if (r.ok) { view.dirty = false; view.saved() }
            else view.formError = r.error || "Could not save the profile"
        })
    }
    function requestBack() {
        if (dirty) { confirmText = "Discard changes?  y / n"; view.refocus() }
        else { reset(); view.back() }
    }
    // Keys the stops do not consume land here.
    function handleKey(e) {
        if (confirmText !== "") {
            if (e.key === Qt.Key_Y) { reset(); view.back() }
            else if (e.key === Qt.Key_N || e.key === Qt.Key_Escape) { confirmText = ""; Qt.callLater(focusFirst) }
            e.accepted = true
            return
        }
        if (e.key === Qt.Key_Escape) { requestBack(); e.accepted = true }
    }

    // A focusable button: Space or Enter activates it.
    component FocusButton: Rectangle {
        id: fb
        property string label: ""
        property bool primary: false
        signal activated()
        Layout.fillWidth: true
        Layout.preferredHeight: 36
        radius: Theme.roundingItem
        color: fb.primary ? Theme.bgSelected : "transparent"
        border.color: fb.activeFocus ? Theme.borderSelected : Theme.border
        border.width: 1
        activeFocusOnTab: true
        Keys.onPressed: (e) => {
            if (e.key === Qt.Key_Space || e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { fb.activated(); e.accepted = true }
        }
        Text {
            anchors.centerIn: parent
            text: fb.label
            font.family: Theme.fontFamily
            font.pixelSize: 12
            font.weight: fb.primary ? Theme.fontWeightMedium : Theme.fontWeightNormal
            color: fb.activeFocus ? Theme.fgBright : Theme.fg
        }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { fb.forceActiveFocus(); fb.activated() } }
    }

    ColumnLayout {
        id: col
        width: parent.width
        spacing: Theme.gapM

        VpnFieldStop {
            id: nameStop
            field: ({ key: "name", label: "Name", kind: "text", required: true, placeholder: "Office VPN" })
            initial: view.nameInit
            onEdited: (v) => { view.name = v; view.dirty = true; view.formError = "" }
            onAdvance: (from) => view.next(from)
            onEscaped: view.requestBack()
        }
        Repeater {
            id: rep
            model: { view.formRev; return Schema.allFields(view.type) }
            delegate: VpnFieldStop {
                required property var modelData
                field: modelData
                visible: { view.shownRev; return Schema.isShown(modelData, view.values) }
                initial: { const v = view.values[modelData.key]; return v === undefined || v === null || typeof v === "boolean" ? "" : String(v) }
                checked: Schema.toBool(view.values[modelData.key])
                mode: { view.modeRev; return view.modes[modelData.key] || "save" }
                stored: !!view.stored[modelData.key]
                revealed: view.reveal
                onEdited: (v) => view.fieldEdited(modelData, v)
                onModeToggled: view.toggleMode(modelData.key)
                onRevealToggled: view.reveal = !view.reveal
                onAdvance: (from) => view.next(from)
                onEscaped: view.requestBack()
            }
        }
        Text {
            visible: view.isWireGuard && view.peerCount > 1
            text: view.peerCount + " peers · re-import to change"
            font.family: Theme.fontFamily
            font.pixelSize: 11
            color: Theme.fgMuted
        }

        FocusButton {
            id: advHeader
            visible: view.type !== "" && !view.isWireGuard
            label: (view.advancedOpen ? Icons.collapse : Icons.expand) + "  Advanced · " + (function () { view.advRev; return view.advanced.length })()
            onActivated: { view.advancedOpen = !view.advancedOpen; view.advRev++ }
        }
        Repeater {
            id: advRep
            model: { view.advRev; return view.advancedOpen ? view.advanced : [] }
            delegate: VpnAdvancedRow {
                required property var modelData
                entry: modelData
                revealed: view.reveal
                onChanged: { view.dirty = true; view.formError = "" }
                onRevealToggled: view.reveal = !view.reveal
                onAdvance: (from) => view.next(from)
                onEscaped: view.requestBack()
            }
        }
        FocusButton {
            visible: view.advancedOpen && !view.isWireGuard
            label: "+ Add row"
            onActivated: view.addRow()
        }

        Text {
            visible: view.formError !== ""
            text: Icons.warning + " " + view.formError
            font.family: Theme.fontFamily
            font.pixelSize: 11
            color: Theme.critical
            wrapMode: Text.Wrap
            Layout.fillWidth: true
        }
        FocusButton {
            id: saveBtn
            primary: true
            label: view.busy ? "Saving…" : (view.isEdit ? "Save changes" : "Add VPN")
            onActivated: view.save()
        }
        Text {
            text: view.confirmText !== "" ? view.confirmText
                : "Tab next · Enter next / save · Space toggle · h/l choose · Ctrl+s show/hide · Esc back"
            font.family: Theme.fontFamily
            font.pixelSize: 10
            color: view.confirmText !== "" ? Theme.critical : Theme.fgDim
            Layout.alignment: Qt.AlignHCenter
        }
    }
}
