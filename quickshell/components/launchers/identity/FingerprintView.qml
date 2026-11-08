import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../../theme"
import "../../../services"
import "../../../services/identityParse.js" as Parse

// Fingerprint unlock (hyprlock's native fprintd path): toggle, enrolled
// fingers, enrollment and deletion. Without a reader the toggle shows
// "Not available" and does nothing.
Item {
    id: view
    property string mode: "list"            // list | enroll
    property bool filterActive: false
    property var navItems: []               // [{ kind: "toggle" } | { kind: "finger", idx }]
    property int selIndex: 0
    property var filteredFingers: []
    property string confirmText: ""
    property string pendingDelete: ""
    property int enrollIndex: 0
    property var pickerFingers: Parse.FINGERS
    property bool enrollActive: false       // an attempt ran; the result may be on screen
    property bool enrollCancelled: false
    property string lastEnrollFinger: ""
    readonly property bool available: IdentityService.fingerprintState !== "unavailable"
    signal back()
    signal refocus()

    implicitHeight: mode === "list" ? listLayout.implicitHeight : enrollLayout.implicitHeight

    function reset() {
        mode = "list"
        filterActive = false
        filterField.text = ""
        selIndex = 0
        confirmText = ""
        pendingDelete = ""
        enrollActive = false
        enrollCancelled = false
        enrollIndex = 0
        updateRows()
    }
    function enrolledNames() { return (IdentityService.enrolled || []).map(f => f.name) }
    function updateRows() {
        const q = filterField.text.trim().toLowerCase().replace(/^\//, "")
        let fs = (IdentityService.enrolled || []).slice()
        if (q) fs = fs.filter(f => f.label.toLowerCase().indexOf(q) !== -1 || f.name.toLowerCase().indexOf(q) !== -1)
        filteredFingers = fs
        const items = [{ kind: "toggle" }]
        for (let i = 0; i < fs.length; i++) items.push({ kind: "finger", idx: i })
        navItems = items
        selIndex = Math.max(0, Math.min(selIndex, items.length - 1))
        Qt.callLater(() => ensureVisible())
    }
    function clearFilter() { filterField.text = ""; updateRows() }
    function moveSel(delta) {
        const n = navItems.length
        if (n === 0) return
        selIndex = Math.max(0, Math.min(n - 1, selIndex + delta))
        ensureVisible()
    }
    function ensureVisible() {
        const it = navItems[selIndex]
        if (it && it.kind === "finger") fingerList.positionViewAtIndex(it.idx, ListView.Contain)
    }
    function selectRow(idx) {
        for (let i = 0; i < navItems.length; i++) {
            if (navItems[i].kind === "finger" && navItems[i].idx === idx) { selIndex = i; break }
        }
    }
    function toggle() {
        if (available) IdentityService.setChoice("fingerprint", IdentityService.fingerprintState !== "enabled")
    }
    function activate() {
        const it = navItems[selIndex]
        if (!it) return
        if (it.kind === "toggle") toggle()
        else deleteSelected()
    }
    function requestDelete(name) {
        confirmText = "Delete " + name + "?  y / n"
        pendingDelete = name
    }
    function confirmYes() {
        if (pendingDelete && IdentityService.fprintdAvailable) IdentityService.deleteFinger(pendingDelete)
        confirmText = ""
        pendingDelete = ""
    }
    function deleteSelected() {
        const it = navItems[selIndex]
        if (it && it.kind === "finger") {
            const f = filteredFingers[it.idx]
            if (f && IdentityService.fprintdAvailable) requestDelete(f.name)
        }
    }
    function openEnroll() {
        if (!IdentityService.fprintdAvailable || !IdentityService.devicePresent) return
        mode = "enroll"
        enrollIndex = 0
        enrollActive = false
        enrollCancelled = false
    }
    function backToList() {
        mode = "list"
        enrollActive = false
        enrollCancelled = false
        updateRows()
    }
    function startEnroll(finger) {
        const f = String(finger || "")
        if (f === "" || !IdentityService.fprintdAvailable || !IdentityService.devicePresent) return
        lastEnrollFinger = f
        enrollCancelled = false
        IdentityService.enroll(f)
        enrollActive = IdentityService.enrolling
    }

    function handleKey(e) {
        if (confirmText !== "") {
            if (e.key === Qt.Key_Y) { confirmYes(); e.accepted = true }
            else if (e.key === Qt.Key_N || e.key === Qt.Key_Escape) { confirmText = ""; pendingDelete = ""; e.accepted = true }
            return
        }
        if (mode === "enroll") { handleEnrollKey(e); return }
        if (e.key === Qt.Key_Escape || e.key === Qt.Key_H) {
            if (filterActive) { filterActive = false; clearFilter(); view.refocus() }
            else view.back()
            e.accepted = true
        }
        else if (e.key === Qt.Key_J || e.key === Qt.Key_Down) { moveSel(1); e.accepted = true }
        else if (e.key === Qt.Key_K || e.key === Qt.Key_Up) { moveSel(-1); e.accepted = true }
        else if (e.key === Qt.Key_Home) { selIndex = 0; ensureVisible(); e.accepted = true }
        else if (e.key === Qt.Key_End) { selIndex = Math.max(0, navItems.length - 1); ensureVisible(); e.accepted = true }
        else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Space) { activate(); e.accepted = true }
        else if (e.key === Qt.Key_T) { toggle(); e.accepted = true }
        else if (e.key === Qt.Key_E || e.key === Qt.Key_A) { openEnroll(); e.accepted = true }
        else if (e.key === Qt.Key_D) { deleteSelected(); e.accepted = true }
        else if (e.key === Qt.Key_R) { IdentityService.refresh(); e.accepted = true }
        else if (e.text === "/") { filterActive = true; filterField.forceActiveFocus(); e.accepted = true }
    }
    function handleEnrollKey(e) {
        if (IdentityService.enrolling) {
            if (e.key === Qt.Key_Escape) { enrollCancelled = true; IdentityService.cancelEnroll(); enrollActive = false; e.accepted = true }
            return
        }
        if (enrollActive) {
            if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                if (IdentityService.enrollDone) backToList()
                else startEnroll(lastEnrollFinger)
                e.accepted = true
            } else if (e.key === Qt.Key_Escape || e.key === Qt.Key_H) {
                backToList()
                e.accepted = true
            }
            return
        }
        if (e.key === Qt.Key_Escape || e.key === Qt.Key_H) { backToList(); e.accepted = true }
        else if (e.key === Qt.Key_J || e.key === Qt.Key_Down) {
            enrollIndex = Math.min(pickerFingers.length - 1, enrollIndex + 1)
            pickerList.positionViewAtIndex(enrollIndex, ListView.Contain)
            e.accepted = true
        } else if (e.key === Qt.Key_K || e.key === Qt.Key_Up) {
            enrollIndex = Math.max(0, enrollIndex - 1)
            pickerList.positionViewAtIndex(enrollIndex, ListView.Contain)
            e.accepted = true
        } else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
            startEnroll(pickerFingers[enrollIndex])
            e.accepted = true
        }
    }

    Connections {
        target: IdentityService
        function onDataUpdated() { view.updateRows() }
    }

    // ------------------------- list -------------------------
    ColumnLayout {
        id: listLayout
        visible: view.mode === "list"
        width: parent.width
        spacing: Theme.gapM

        Rectangle {
            visible: view.filterActive
            Layout.fillWidth: true
            Layout.preferredHeight: 36
            radius: Theme.roundingItem
            color: Theme.bgActive
            border.color: filterField.activeFocus ? Theme.borderSelected : Theme.border
            border.width: 1
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Theme.padM
                anchors.rightMargin: Theme.padM
                spacing: Theme.gapS
                Text { text: Icons.search; font.family: Theme.fontFamily; font.pixelSize: 14; color: Theme.fgMuted }
                TextField {
                    id: filterField
                    Layout.fillWidth: true
                    placeholderText: "filter by finger"
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                    color: Theme.fg
                    placeholderTextColor: Theme.fgDim
                    background: null
                    cursorDelegate: Rectangle {
                        width: Math.max(6, Math.round(filterField.font.pixelSize * 0.65))
                        height: Math.round(filterField.font.pixelSize * 1.5)
                        color: Theme.fg
                    }
                    onTextChanged: view.updateRows()
                    onAccepted: { view.filterActive = false; view.updateRows(); view.refocus() }
                    Keys.onEscapePressed: { view.filterActive = false; view.clearFilter(); view.refocus() }
                }
            }
        }

        MethodRow {
            icon: Icons.fingerprint
            title: "Unlock with fingerprint"
            note: view.available ? "lock screen only · applies to the next lock" : ""
            stateText: IdentityService.fingerprintState === "enabled" ? "Enabled"
                : IdentityService.fingerprintState === "disabled" ? "Disabled" : "Not available"
            dim: IdentityService.fingerprintState !== "enabled"
            selected: { const it = view.navItems[view.selIndex]; return it !== undefined && it.kind === "toggle" }
            onClicked: { view.selIndex = 0; view.toggle() }
        }

        Text {
            visible: view.available
            text: "Enrolled fingers"
            font.family: Theme.fontFamily
            font.pixelSize: 11
            color: Theme.fgMuted
        }
        Text {
            visible: view.available && view.filteredFingers.length === 0
            text: "No fingerprints enrolled — press e to enroll one"
            font.family: Theme.fontFamily
            font.pixelSize: 11
            color: Theme.fgMuted
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
        }
        ListView {
            id: fingerList
            visible: view.available
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(230, contentHeight)
            clip: true
            spacing: 4
            model: view.filteredFingers
            delegate: Rectangle {
                required property var modelData
                required property int index
                width: fingerList.width
                height: 40
                radius: Theme.roundingItem
                readonly property bool isSel: { const it = view.navItems[view.selIndex]; return it !== undefined && it.kind === "finger" && it.idx === index }
                color: isSel ? Theme.bgSelected : (fma.containsMouse ? Theme.bgHover : "transparent")
                border.color: isSel ? Theme.borderSelected : "transparent"
                border.width: 1
                MouseArea { id: fma; anchors.fill: parent; hoverEnabled: true; onClicked: view.selectRow(index) }
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.padM
                    anchors.rightMargin: Theme.padM
                    spacing: Theme.gapM
                    Text { text: Icons.fingerprint; font.family: Theme.fontFamily; font.pixelSize: 16; color: Theme.fg }
                    Text {
                        text: modelData.label
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                        color: Theme.fg
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }
                    Text { text: modelData.name; font.family: Theme.fontFamily; font.pixelSize: 10; color: Theme.fgMuted }
                }
            }
        }

        Text {
            visible: !IdentityService.fprintdAvailable
            text: "fprintd unavailable"
            font.family: Theme.fontFamily
            font.pixelSize: 11
            color: Theme.warning
            Layout.fillWidth: true
        }
        Text {
            visible: IdentityService.fprintdAvailable && !IdentityService.devicePresent
            text: "No fingerprint reader detected"
            font.family: Theme.fontFamily
            font.pixelSize: 11
            color: Theme.fgMuted
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
        }
        Text {
            visible: view.available && IdentityService.lastError !== ""
            text: Icons.warning + " " + IdentityService.lastError
            font.family: Theme.fontFamily
            font.pixelSize: 11
            color: Theme.critical
            Layout.fillWidth: true
            wrapMode: Text.Wrap
        }
        Text {
            text: view.confirmText !== "" ? view.confirmText
                : view.available ? "j/k move · Enter act · e enroll · d delete · t toggle · / filter · Esc back"
                : "Esc back"
            font.family: Theme.fontFamily
            font.pixelSize: 10
            color: view.confirmText !== "" ? Theme.critical : Theme.fgDim
            Layout.alignment: Qt.AlignHCenter
        }
    }

    // ------------------------ enroll ------------------------
    ColumnLayout {
        id: enrollLayout
        visible: view.mode === "enroll"
        width: parent.width
        spacing: Theme.gapM

        Text {
            text: "Enroll fingerprint"
            font.family: Theme.fontFamily
            font.pixelSize: 11
            color: Theme.fgMuted
        }

        ListView {
            id: pickerList
            visible: !IdentityService.enrolling && !view.enrollActive
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(300, contentHeight)
            clip: true
            spacing: 4
            model: view.pickerFingers
            delegate: Rectangle {
                required property var modelData
                required property int index
                width: pickerList.width
                height: 34
                radius: Theme.roundingItem
                readonly property bool isSel: index === view.enrollIndex
                readonly property bool done: view.enrolledNames().indexOf(modelData) !== -1
                color: isSel ? Theme.bgSelected : (pma.containsMouse ? Theme.bgHover : "transparent")
                border.color: isSel ? Theme.borderSelected : "transparent"
                border.width: 1
                MouseArea { id: pma; anchors.fill: parent; hoverEnabled: true; onClicked: { view.enrollIndex = index; view.startEnroll(modelData) } }
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.padM
                    anchors.rightMargin: Theme.padM
                    spacing: Theme.gapM
                    Text {
                        text: Parse.fingerLabel(String(modelData))
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                        color: Theme.fg
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }
                    Text { visible: done; text: "(enrolled)"; font.family: Theme.fontFamily; font.pixelSize: 10; color: Theme.fgMuted }
                }
            }
        }

        Rectangle {
            visible: IdentityService.enrolling || view.enrollActive
            Layout.fillWidth: true
            implicitHeight: progCol.implicitHeight + Theme.padL * 2
            radius: Theme.roundingItem
            color: Theme.bgActive
            border.color: Theme.border
            border.width: 1
            ColumnLayout {
                id: progCol
                anchors.fill: parent
                anchors.margins: Theme.padL
                spacing: Theme.gapM
                Text {
                    text: Icons.fingerprint
                    font.family: Theme.fontFamily
                    font.pixelSize: 34
                    color: (view.enrollActive && !IdentityService.enrolling && !IdentityService.enrollDone) ? Theme.critical : Theme.fg
                    Layout.alignment: Qt.AlignHCenter
                }
                Text {
                    text: {
                        if (IdentityService.enrolling)
                            return IdentityService.enrollMessage !== "" ? IdentityService.enrollMessage : "Place your finger on the reader"
                        if (IdentityService.enrollDone) return "Enrolled"
                        return IdentityService.enrollMessage !== "" ? IdentityService.enrollMessage : "Enrollment failed"
                    }
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                    font.weight: Theme.fontWeightMedium
                    color: Theme.fg
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                }
                Text {
                    visible: IdentityService.enrolling && IdentityService.enrollPasses > 0
                    text: IdentityService.enrollPasses + " stage(s) passed"
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    color: Theme.fgMuted
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                }
                Text {
                    visible: IdentityService.lastError !== "" && view.enrollActive && !IdentityService.enrolling
                    text: IdentityService.lastError
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    color: Theme.critical
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                }
            }
        }

        Text {
            text: {
                if (IdentityService.enrolling) return "Esc cancel"
                if (view.enrollActive) return IdentityService.enrollDone ? "Enter/Esc back" : "Enter retry · Esc back"
                return "j/k move · Enter enroll · Esc back"
            }
            font.family: Theme.fontFamily
            font.pixelSize: 10
            color: Theme.fgDim
            Layout.alignment: Qt.AlignHCenter
        }
    }
}
