import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../../theme"
import "../../../services"
import "../../../services/vpnSchema.js" as Schema

// Add VPN, step 1: import a file, or pick one of the installed VPN types
// (NetworkManager plugins plus WireGuard, NetworkService.vpnTypes).
// Spec: docs/superpowers/specs/2026-11-09-native-vpn-design.md §9.
Item {
    id: view
    property int sel: 0
    property string filter: ""
    readonly property var rows: {
        const all = [{ kind: "import", name: "", title: "Import from file…", note: "" }]
        Schema.pickerTypes(NetworkService.vpnTypes).forEach(t =>
            all.push({ kind: "type", name: t.name, title: t.label, note: t.advancedOnly ? "advanced" : "" }))
        const q = view.filter.trim().toLowerCase()
        return q === "" ? all : all.filter(r => r.title.toLowerCase().indexOf(q) !== -1)
    }
    signal pickType(string name)
    signal importRequested()
    signal back()
    signal refocus()

    implicitHeight: col.implicitHeight
    onRowsChanged: sel = Math.max(0, Math.min(sel, rows.length - 1))

    function reset() { sel = 0; filter = ""; filterField.text = ""; filterBox.visible = false }
    function activate() {
        const r = rows[sel]
        if (!r) return
        if (r.kind === "import") view.importRequested()
        else view.pickType(r.name)
    }
    // Keys the filter field does not consume land here.
    function handleKey(e) {
        if (e.key === Qt.Key_Escape) {
            if (filterBox.visible || filter !== "") { reset(); view.refocus() }
            else view.back()
            e.accepted = true
        } else if (e.key === Qt.Key_J || e.key === Qt.Key_Down) { sel = Math.min(rows.length - 1, sel + 1); e.accepted = true }
        else if (e.key === Qt.Key_K || e.key === Qt.Key_Up) { sel = Math.max(0, sel - 1); e.accepted = true }
        else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_L) { activate(); e.accepted = true }
        else if (e.text === "/") { filterBox.visible = true; filterField.forceActiveFocus(); e.accepted = true }
    }

    ColumnLayout {
        id: col
        width: parent.width
        spacing: Theme.gapS

        Rectangle {
            id: filterBox
            visible: false
            Layout.fillWidth: true
            Layout.preferredHeight: 36
            radius: Theme.roundingItem
            color: Theme.bgActive
            border.color: filterField.activeFocus ? Theme.borderSelected : Theme.border
            border.width: 1
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Theme.padM
                Text { text: Icons.search; font.family: Theme.fontFamily; font.pixelSize: 14; color: Theme.fgMuted }
                TextField {
                    id: filterField
                    Layout.fillWidth: true
                    placeholderText: "filter types…"
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                    color: Theme.fg
                    placeholderTextColor: Theme.fgDim
                    background: null
                    onTextChanged: view.filter = text
                    onAccepted: { filterBox.visible = false; view.refocus() }
                }
            }
        }
        Repeater {
            model: view.rows
            delegate: VpnRow {
                required property var modelData
                required property int index
                icon: modelData.kind === "import" ? Icons.download : Icons.vpn
                title: modelData.title
                note: modelData.note
                selected: index === view.sel
                onClicked: { view.sel = index; view.activate() }
            }
        }
        Text {
            visible: NetworkService.vpnTypes.length <= 1
            text: "More types: networking.networkmanager.plugins"
            font.family: Theme.fontFamily
            font.pixelSize: 11
            color: Theme.fgDim
        }
        Text {
            text: "j/k · Enter choose · / filter · Esc back"
            font.family: Theme.fontFamily
            font.pixelSize: 10
            color: Theme.fgDim
            Layout.alignment: Qt.AlignHCenter
        }
    }
}
