import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import "../../../theme"
import "../../../services"
import "../../../services/vpnSchema.js" as Schema

// Add VPN → Import from file: config files found in ~/Downloads and
// ~/Documents (NetworkService.importCandidates), or any typed path. The
// extension picks the type; when several installed types claim it, a short
// picker asks. nm-vpn creates the profile at once; the host then opens it in
// the form. No file-picker window. Spec §9.
Item {
    id: view
    property int sel: 0                       // index into files; files.length = the path box
    property string filter: ""
    property string choosingPath: ""          // non-empty: asking which type this file is
    property int typeSel: 0
    property bool busy: false
    property string message: ""
    readonly property string home: Quickshell.env("HOME") || ""
    readonly property var files: {
        const q = view.filter.trim().toLowerCase()
        const all = NetworkService.importCandidates
        return q === "" ? all : all.filter(p => p.toLowerCase().indexOf(q) !== -1)
    }
    readonly property var typeChoices: Schema.pickerTypes(Schema.importableTypes(NetworkService.vpnTypes))
    readonly property string extList: Schema.importExtensions(NetworkService.vpnTypes).join(" ")
    signal imported(string uuid)
    signal back()
    signal refocus()

    implicitHeight: col.implicitHeight

    function shortPath(p) { return home !== "" && p.indexOf(home + "/") === 0 ? "~" + p.slice(home.length) : p }
    function reset() {
        sel = 0; filter = ""; choosingPath = ""; typeSel = 0; busy = false; message = ""
        pathField.text = ""; filterField.text = ""; filterBox.visible = false
    }
    function importPath(p) {
        const path = String(p || "").trim()
        if (path === "" || busy) return
        const t = Schema.typeForPath(path, NetworkService.vpnTypes)
        if (t !== "") doImport(t, path)
        else if (typeChoices.length === 0) message = "No installed VPN type can import files"
        else { choosingPath = path; typeSel = 0; message = ""; view.refocus() }
    }
    function doImport(t, path) {
        busy = true
        message = ""
        NetworkService.vpnImport(t, path, r => {
            view.busy = false
            if (r.ok) { view.choosingPath = ""; view.imported(r.uuid) }
            else view.message = r.error || "Import failed"
        })
    }
    function activate() {
        if (choosingPath !== "") { const t = typeChoices[typeSel]; if (t) doImport(t.name, choosingPath); return }
        if (sel < files.length) importPath(files[sel])
        else pathField.forceActiveFocus()
    }
    // Keys the text fields do not consume land here.
    function handleKey(e) {
        if (e.key === Qt.Key_Escape) {
            if (pathField.activeFocus || filterField.activeFocus) { filterBox.visible = false; view.refocus() }
            else if (choosingPath !== "") { choosingPath = ""; message = "" }
            else if (filter !== "") { filter = ""; filterField.text = "" }
            else view.back()
            e.accepted = true
        } else if (e.key === Qt.Key_J || e.key === Qt.Key_Down) {
            if (choosingPath !== "") typeSel = Math.min(typeChoices.length - 1, typeSel + 1)
            else sel = Math.min(files.length, sel + 1)
            e.accepted = true
        } else if (e.key === Qt.Key_K || e.key === Qt.Key_Up) {
            if (choosingPath !== "") typeSel = Math.max(0, typeSel - 1)
            else sel = Math.max(0, sel - 1)
            e.accepted = true
        } else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { activate(); e.accepted = true }
        else if (e.text === "/" && choosingPath === "") { filterBox.visible = true; filterField.forceActiveFocus(); e.accepted = true }
    }

    ColumnLayout {
        id: col
        width: parent.width
        spacing: Theme.gapS

        // --- which type? ---
        Text {
            visible: view.choosingPath !== ""
            text: "Which type is " + view.shortPath(view.choosingPath) + "?"
            font.family: Theme.fontFamily
            font.pixelSize: 12
            color: Theme.fg
            elide: Text.ElideMiddle
            Layout.fillWidth: true
        }
        Repeater {
            model: view.choosingPath !== "" ? view.typeChoices : []
            delegate: VpnRow {
                required property var modelData
                required property int index
                icon: Icons.vpn
                title: modelData.label
                selected: index === view.typeSel
                onClicked: { view.typeSel = index; view.activate() }
            }
        }

        // --- files ---
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
                    placeholderText: "filter files…"
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                    color: Theme.fg
                    placeholderTextColor: Theme.fgDim
                    background: null
                    cursorDelegate: Rectangle {
                        width: Math.max(6, Math.round(parent.font.pixelSize * 0.65))
                        height: Math.round(parent.font.pixelSize * 1.5)
                        color: Theme.fg
                    }
                    onTextChanged: { view.filter = text; view.sel = 0 }
                    onAccepted: { filterBox.visible = false; view.refocus() }
                }
            }
        }
        Text {
            visible: view.choosingPath === "" && view.files.length === 0
            text: view.extList === "" ? "No installed VPN type can import files"
                : "No " + view.extList + " files in ~/Downloads or ~/Documents"
            font.family: Theme.fontFamily
            font.pixelSize: 11
            color: Theme.fgDim
        }
        Repeater {
            model: view.choosingPath === "" ? view.files : []
            delegate: VpnRow {
                required property var modelData
                required property int index
                icon: Icons.download
                title: view.shortPath(modelData)
                selected: index === view.sel
                onClicked: { view.sel = index; view.activate() }
            }
        }
        Rectangle {
            visible: view.choosingPath === ""
            Layout.fillWidth: true
            Layout.preferredHeight: 36
            radius: Theme.roundingItem
            color: Theme.bgActive
            border.color: (pathField.activeFocus || view.sel === view.files.length) ? Theme.borderSelected : Theme.border
            border.width: 1
            TextField {
                id: pathField
                anchors.fill: parent
                anchors.leftMargin: Theme.padM
                anchors.rightMargin: Theme.padM
                placeholderText: "or type a path: ~/vpn/office.ovpn"
                font.family: Theme.fontFamily
                font.pixelSize: 13
                color: Theme.fg
                placeholderTextColor: Theme.fgDim
                background: null
                cursorDelegate: Rectangle {
                    width: Math.max(6, Math.round(parent.font.pixelSize * 0.65))
                    height: Math.round(parent.font.pixelSize * 1.5)
                    color: Theme.fg
                }
                onAccepted: view.importPath(text)
            }
        }

        Text {
            visible: view.message !== "" || view.busy
            text: view.busy ? "Importing…" : Icons.warning + " " + view.message
            font.family: Theme.fontFamily
            font.pixelSize: 11
            color: view.busy ? Theme.fgMuted : Theme.critical
            wrapMode: Text.Wrap
            Layout.fillWidth: true
        }
        Text {
            text: view.choosingPath !== "" ? "j/k · Enter import as · Esc back" : "j/k · Enter import · / filter · Esc back"
            font.family: Theme.fontFamily
            font.pixelSize: 10
            color: Theme.fgDim
            Layout.alignment: Qt.AlignHCenter
        }
    }
}
