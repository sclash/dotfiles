import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../../theme"
import "../../services"
import "../../services/identityParse.js" as Parse

// Identity Manager (SUPER+I) — fingerprint auth toggle, enrolled-finger list,
// enrollment and deletion for the current user. Spec:
// specs/launchers/Identity-Manager.md (normative).
WlrLayershell {
    id: root
    property bool isOpen: false
    property bool filterActive: false
    property string view: "main"            // main | enroll
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

    function open() { isOpen = true }
    function close() {
        isOpen = false
        filterActive = false
        confirmText = ""
        pendingDelete = ""
        view = "main"
        enrollActive = false
        enrollCancelled = false
    }
    function toggle() { if (isOpen) close(); else open() }

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
                    text: "Identity Manager"
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
                    Layout.preferredHeight: root.view === "main" ? mainView.implicitHeight : enrollView.implicitHeight

                    // ------------------------- main view -------------------------
                    Item {
                        id: mainView
                        width: viewHost.width
                        implicitHeight: mainLayout.implicitHeight
                        x: root.view === "main" ? 0 : -60
                        opacity: root.view === "main" ? 1 : 0
                        enabled: root.view === "main"
                        visible: opacity > 0.01
                        Behavior on x { NumberAnimation { duration: Theme.durationNormal; easing.type: Easing.OutCubic } }
                        Behavior on opacity { NumberAnimation { duration: Theme.durationFast } }

                        ColumnLayout {
                            id: mainLayout
                            width: parent.width
                            spacing: Theme.gapM

                            Rectangle {
                                visible: root.filterActive
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
                                            width: Math.max(6, Math.round(parent.font.pixelSize * 0.65))
                                            height: Math.round(parent.font.pixelSize * 1.5)
                                            color: Theme.fg
                                        }
                                        onTextChanged: root.updateRows()
                                        onAccepted: { root.filterActive = false; root.updateRows(); Qt.callLater(() => viewHost.forceActiveFocus()) }
                                        Keys.onEscapePressed: { root.filterActive = false; root.clearFilter(); Qt.callLater(() => viewHost.forceActiveFocus()) }
                                    }
                                }
                            }

                            // Toggle row — always first in the nav order.
                            Rectangle {
                                id: toggleRow
                                Layout.fillWidth: true
                                implicitHeight: 46
                                radius: Theme.roundingItem
                                readonly property bool isSel: { const it = root.navItems[root.selIndex]; return it !== undefined && it.kind === "toggle" }
                                color: isSel ? Theme.bgSelected : (toggleMa.containsMouse ? Theme.bgHover : "transparent")
                                border.color: isSel ? Theme.borderSelected : Theme.border
                                border.width: 1
                                MouseArea { id: toggleMa; anchors.fill: parent; hoverEnabled: true; onClicked: root.activateToggle() }
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: Theme.padM
                                    anchors.rightMargin: Theme.padM
                                    spacing: Theme.gapM
                                    Text {
                                        text: Icons.fingerprint
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 18
                                        color: IdentityService.authEnabled ? Theme.fg : Theme.fgDim
                                    }
                                    ColumnLayout {
                                        spacing: 1
                                        Text {
                                            text: "Unlock with fingerprint"
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 13
                                            font.weight: Theme.fontWeightMedium
                                            color: Theme.fg
                                        }
                                        Text {
                                            text: "applies to the next lock"
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 10
                                            color: Theme.fgDim
                                        }
                                    }
                                    Item { Layout.fillWidth: true }
                                    Text {
                                        text: IdentityService.authEnabled ? "Enabled" : "Disabled"
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSizeSmall
                                        color: IdentityService.authEnabled ? Theme.fg : Theme.fgDim
                                    }
                                }
                            }

                            Text {
                                text: "Enrolled fingers"
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                color: Theme.fgMuted
                            }
                            Text {
                                visible: IdentityService.fprintdAvailable && root.filteredFingers.length === 0
                                text: "No fingerprints enrolled"
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                color: Theme.fgMuted
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                            }
                            ListView {
                                id: fingerList
                                Layout.fillWidth: true
                                Layout.preferredHeight: Math.min(230, contentHeight)
                                clip: true
                                spacing: 4
                                model: root.filteredFingers
                                delegate: Rectangle {
                                    required property var modelData
                                    required property int index
                                    width: parent.width
                                    height: 40
                                    radius: Theme.roundingItem
                                    readonly property bool isSel: { const it = root.navItems[root.selIndex]; return it !== undefined && it.kind === "finger" && it.idx === index }
                                    color: isSel ? Theme.bgSelected : (fma.containsMouse ? Theme.bgHover : "transparent")
                                    border.color: isSel ? Theme.borderSelected : "transparent"
                                    border.width: 1
                                    MouseArea { id: fma; anchors.fill: parent; hoverEnabled: true; onClicked: root.selectRow(index) }
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
                                        Text {
                                            text: modelData.name
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 10
                                            color: Theme.fgMuted
                                        }
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
                                visible: IdentityService.lastError !== ""
                                text: Icons.warning + " " + IdentityService.lastError
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                color: Theme.critical
                                Layout.fillWidth: true
                                wrapMode: Text.Wrap
                            }

                            Text {
                                text: root.confirmText !== ""
                                    ? root.confirmText
                                    : "j/k move · Enter act · e enroll · d delete · t toggle · / filter · Esc close"
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                                color: root.confirmText !== "" ? Theme.critical : Theme.fgDim
                                Layout.alignment: Qt.AlignHCenter
                            }
                        }
                    }

                    // ------------------------ enroll view ------------------------
                    Item {
                        id: enrollView
                        width: viewHost.width
                        implicitHeight: enrollLayout.implicitHeight
                        x: root.view === "enroll" ? 0 : 60
                        opacity: root.view === "enroll" ? 1 : 0
                        enabled: root.view === "enroll"
                        visible: opacity > 0.01
                        Behavior on x { NumberAnimation { duration: Theme.durationNormal; easing.type: Easing.OutCubic } }
                        Behavior on opacity { NumberAnimation { duration: Theme.durationFast } }

                        ColumnLayout {
                            id: enrollLayout
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
                                visible: !IdentityService.enrolling && !root.enrollActive
                                Layout.fillWidth: true
                                Layout.preferredHeight: Math.min(300, contentHeight)
                                clip: true
                                spacing: 4
                                model: root.pickerFingers
                                delegate: Rectangle {
                                    required property var modelData
                                    required property int index
                                    width: pickerList.width
                                    height: 34
                                    radius: Theme.roundingItem
                                    readonly property bool isSel: index === root.enrollIndex
                                    readonly property bool done: root.enrolledNames().indexOf(modelData) !== -1
                                    color: isSel ? Theme.bgSelected : (pma.containsMouse ? Theme.bgHover : "transparent")
                                    border.color: isSel ? Theme.borderSelected : "transparent"
                                    border.width: 1
                                    MouseArea { id: pma; anchors.fill: parent; hoverEnabled: true; onClicked: { root.enrollIndex = index; root.startEnroll(modelData) } }
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
                                        Text {
                                            visible: done
                                            text: "(enrolled)"
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 10
                                            color: Theme.fgMuted
                                        }
                                    }
                                }
                            }

                            Rectangle {
                                visible: IdentityService.enrolling || root.enrollActive
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
                                        color: (root.enrollActive && !IdentityService.enrolling && !IdentityService.enrollDone) ? Theme.critical : Theme.fg
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
                                        visible: IdentityService.lastError !== "" && root.enrollActive && !IdentityService.enrolling
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
                                    if (root.enrollActive) return IdentityService.enrollDone ? "Enter/Esc back" : "Enter retry · Esc back"
                                    return "j/k move · Enter enroll · Esc back"
                                }
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                                color: Theme.fgDim
                                Layout.alignment: Qt.AlignHCenter
                            }
                        }
                    }
                }
            }
        }

        Keys.onPressed: (e)=>{
            if (root.confirmText !== "") {
                if (e.key === Qt.Key_Y) { root.confirmYes(); e.accepted = true; return }
                if (e.key === Qt.Key_N || e.key === Qt.Key_Escape) { root.confirmText = ""; root.pendingDelete = ""; e.accepted = true; return }
            }
            if (root.view === "enroll") { root.handleEnrollKey(e); return }
            if (e.key === Qt.Key_Escape) {
                if (root.filterActive) { root.filterActive = false; root.clearFilter(); Qt.callLater(() => viewHost.forceActiveFocus()); e.accepted = true }
                else root.close()
            }
            else if (e.key === Qt.Key_J || e.key === Qt.Key_Down) { root.moveSel(1); e.accepted = true }
            else if (e.key === Qt.Key_K || e.key === Qt.Key_Up) { root.moveSel(-1); e.accepted = true }
            else if (e.key === Qt.Key_Home) { root.selIndex = 0; root.ensureVisible(); e.accepted = true }
            else if (e.key === Qt.Key_End) { root.selIndex = Math.max(0, root.navItems.length - 1); root.ensureVisible(); e.accepted = true }
            else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Space) { root.activate(); e.accepted = true }
            else if (e.key === Qt.Key_T) { root.activateToggle(); e.accepted = true }
            else if (e.key === Qt.Key_E || e.key === Qt.Key_A) { root.openEnroll(); e.accepted = true }
            else if (e.key === Qt.Key_D) { root.deleteSelected(); e.accepted = true }
            else if (e.key === Qt.Key_R) { IdentityService.refresh(); e.accepted = true }
            else if (e.text === "/") { root.filterActive = true; filterField.forceActiveFocus(); e.accepted = true }
        }
    }

    onIsOpenChanged: if (isOpen) {
        root.view = "main"
        root.filterActive = false
        if (filterField) filterField.text = ""
        root.selIndex = 0
        root.confirmText = ""
        root.pendingDelete = ""
        root.enrollActive = false
        root.enrollCancelled = false
        root.enrollIndex = 0
        IdentityService.lastError = ""
        IdentityService.refresh()
        root.updateRows()
        Qt.callLater(() => viewHost.forceActiveFocus())
    }

    function enrolledNames() {
        return (IdentityService.enrolled || []).map(f => f.name)
    }
    function updateRows() {
        const raw = filterField ? filterField.text.trim().toLowerCase() : ""
        const q = raw.replace(/^\//, "")
        let fs = (IdentityService.enrolled || []).slice()
        if (q) fs = fs.filter(f => f.label.toLowerCase().indexOf(q) !== -1 || f.name.toLowerCase().indexOf(q) !== -1)
        filteredFingers = fs
        const items = [{ kind: "toggle" }]
        for (let i = 0; i < fs.length; i++) items.push({ kind: "finger", idx: i })
        navItems = items
        selIndex = Math.max(0, Math.min(selIndex, items.length - 1))
        Qt.callLater(() => ensureVisible())
    }
    function clearFilter() {
        if (filterField) filterField.text = ""
        updateRows()
    }
    function moveSel(delta) {
        const n = navItems.length
        if (n === 0) return
        selIndex = Math.max(0, Math.min(n - 1, selIndex + delta))
        ensureVisible()
    }
    function ensureVisible() {
        const it = navItems[selIndex]
        if (it && it.kind === "finger" && fingerList) fingerList.positionViewAtIndex(it.idx, ListView.Contain)
    }
    function selectRow(idx) {
        for (let i = 0; i < navItems.length; i++) {
            if (navItems[i].kind === "finger" && navItems[i].idx === idx) { selIndex = i; break }
        }
    }
    function activate() {
        const it = navItems[selIndex]
        if (!it) return
        if (it.kind === "toggle") activateToggle()
        else if (it.kind === "finger") {
            const f = filteredFingers[it.idx]
            if (f && IdentityService.fprintdAvailable) requestDelete(f.name)
        }
    }
    function activateToggle() {
        IdentityService.setAuthEnabled(!IdentityService.authEnabled)
    }
    function requestDelete(name) {
        confirmText = "Delete " + name + "?  y / n"
        pendingDelete = name
    }
    function confirmYes() {
        if (pendingDelete && IdentityService.fprintdAvailable) IdentityService.deleteFinger(pendingDelete)
        confirmText = ""
        pendingDelete = ""
        Qt.callLater(() => viewHost.forceActiveFocus())
    }
    function deleteSelected() {
        const it = navItems[selIndex]
        if (it && it.kind === "finger") {
            const f = filteredFingers[it.idx]
            if (f && IdentityService.fprintdAvailable) requestDelete(f.name)
        }
    }
    function openEnroll() {
        root.view = "enroll"
        root.enrollIndex = 0
        root.enrollActive = false
        root.enrollCancelled = false
        Qt.callLater(() => viewHost.forceActiveFocus())
    }
    function backToMain() {
        root.view = "main"
        root.enrollActive = false
        root.enrollCancelled = false
        root.updateRows()
        Qt.callLater(() => viewHost.forceActiveFocus())
    }
    function startEnroll(finger) {
        const f = String(finger || "")
        if (f === "" || !IdentityService.fprintdAvailable || !IdentityService.devicePresent) return
        root.lastEnrollFinger = f
        root.enrollCancelled = false
        IdentityService.enroll(f)
        root.enrollActive = IdentityService.enrolling
    }
    function handleEnrollKey(e) {
        if (IdentityService.enrolling) {
            if (e.key === Qt.Key_Escape) { root.enrollCancelled = true; IdentityService.cancelEnroll(); root.enrollActive = false; Qt.callLater(() => viewHost.forceActiveFocus()); e.accepted = true }
            return
        }
        if (root.enrollActive) {
            if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                if (IdentityService.enrollDone) root.backToMain()
                else root.startEnroll(root.lastEnrollFinger)
                e.accepted = true
            } else if (e.key === Qt.Key_Escape || e.key === Qt.Key_H) {
                root.backToMain()
                e.accepted = true
            }
            return
        }
        if (e.key === Qt.Key_Escape || e.key === Qt.Key_H) {
            root.backToMain()
            e.accepted = true
        } else if (e.key === Qt.Key_J || e.key === Qt.Key_Down) {
            root.enrollIndex = Math.min(root.pickerFingers.length - 1, root.enrollIndex + 1)
            if (pickerList) pickerList.positionViewAtIndex(root.enrollIndex, ListView.Contain)
            e.accepted = true
        } else if (e.key === Qt.Key_K || e.key === Qt.Key_Up) {
            root.enrollIndex = Math.max(0, root.enrollIndex - 1)
            if (pickerList) pickerList.positionViewAtIndex(root.enrollIndex, ListView.Contain)
            e.accepted = true
        } else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
            root.startEnroll(root.pickerFingers[root.enrollIndex])
            e.accepted = true
        }
    }

    Connections {
        target: IdentityService
        function onDataUpdated() { root.updateRows() }
    }
}
