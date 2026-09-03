import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../../theme"
import "../../services"

WlrLayershell {
    id: root
    property bool isOpen: false
    property bool filterActive: false
    property bool suppressUpdate: false
    property var navItems: []
    property int selIndex: 0
    property bool passphraseActive: false
    property string passphraseNode: ""
    property string passphraseLabel: ""
    property string confirmText: ""
    property var pendingAction: null
    property var filteredStorage: []
    property var filteredDevices: []

    function open() { isOpen = true }
    function close() { isOpen = false; filterActive = false; passphraseActive = false; confirmText = "" }
    function toggle() { if (isOpen) close(); else open() }

    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    visible: isOpen
    keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore
    Rectangle { anchors.fill: parent; color: Theme.overlay; MouseArea { anchors.fill: parent; onClicked: root.close() } }

    Rectangle {
        width: 640
        height: Math.min(640, mainCol.implicitHeight + Theme.padL * 2)
        anchors.centerIn: parent
        radius: Theme.roundingLauncher
        color: Theme.bgLauncher
        border.width: 1
        border.color: Theme.borderActive
        clip: true
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
                focus: true
                Text { text: "USB"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fgMuted; font.capitalization: Font.AllUppercase; font.letterSpacing: 1.2 }
                Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.gapM
                    Rectangle {
                        visible: filterActive
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
                            Text { text: Icons.search; font.family: Theme.fontFamily; font.pixelSize: 14; color: Theme.fgMuted }
                            TextField {
                                id: filterField
                                Layout.fillWidth: true
                                placeholderText: "filter by label, name, node, vid:pid…"
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
                                onTextChanged: if (!suppressUpdate) updateModels()
                                onAccepted: { filterActive = false; updateModels(); Qt.callLater(() => mainCol.forceActiveFocus()) }
                            }
                        }
                    }
                }

                Text { text: "Storage"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fgMuted }
                Text {
                    visible: !UsbService.udisksAvailable
                    text: "udisks2 unavailable — mounting disabled"
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    color: Theme.warning
                    Layout.fillWidth: true
                }
                Text {
                    visible: UsbService.udisksAvailable && filteredStorage.length === 0
                    text: "No USB storage devices"
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    color: Theme.fgMuted
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                }
                ListView {
                    id: storageList
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(230, contentHeight)
                    clip: true
                    spacing: 4
                    model: root.filteredStorage
                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        width: parent.width
                        height: 52
                        radius: Theme.roundingItem
                        readonly property bool isSel: { const it = root.navItems[root.selIndex]; return it !== undefined && it.kind === "storage" && it.idx === index }
                        readonly property bool rowBusy: UsbService.busyNode === modelData.node
                        color: isSel ? Theme.bgSelected : (sma.containsMouse ? Theme.bgHover : "transparent")
                        border.color: isSel ? Theme.borderSelected : "transparent"
                        border.width: 1
                        MouseArea { id: sma; anchors.fill: parent; hoverEnabled: true; onClicked: root.selectRow("storage", index) }
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Theme.padM
                            anchors.rightMargin: Theme.padM
                            spacing: Theme.gapM
                            Text {
                                text: modelData.encrypted ? Icons.lock : Icons.usbDrive
                                font.family: Theme.fontFamily
                                font.pixelSize: 18
                                color: modelData.encrypted ? Theme.warning : Theme.fg
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: Theme.gapM
                                    Text {
                                        text: modelData.label
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 13
                                        font.weight: Theme.fontWeightMedium
                                        color: Theme.fg
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                    Text {
                                        text: modelData.size + (modelData.fstype ? " · " + modelData.fstype : "")
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 10
                                        color: Theme.fgMuted
                                    }
                                }
                                Text {
                                    text: rowBusy ? root.busyLabel() : (modelData.mountPoint ? modelData.mountPoint : "Not mounted")
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    color: rowBusy ? Theme.fgMuted : (modelData.mountPoint ? Theme.fg : Theme.fgDim)
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                            }
                            RowLayout {
                                spacing: Theme.gapS
                                visible: UsbService.udisksAvailable
                                Rectangle {
                                    visible: !rowBusy
                                    width: 72; height: 26
                                    radius: 6
                                    color: Theme.bgActive
                                    border.color: modelData.locked ? Theme.warning : Theme.borderActive
                                    border.width: 1
                                    Text {
                                        anchors.centerIn: parent
                                        text: root.primaryActionLabel(modelData)
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 11
                                        color: Theme.fg
                                    }
                                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.primaryStorageAction(modelData) }
                                }
                                Rectangle {
                                    visible: !rowBusy && !!modelData.mountPoint
                                    width: 52; height: 26
                                    radius: 6
                                    color: Theme.bgActive
                                    border.color: Theme.borderActive
                                    border.width: 1
                                    Text { anchors.centerIn: parent; text: "Open"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fg }
                                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.openStorage(modelData) }
                                }
                                Text {
                                    visible: !rowBusy
                                    text: "eject"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    color: Theme.critical
                                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.requestPowerOff(modelData) }
                                }
                            }
                        }
                    }
                }

                Text { text: "All USB Devices"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fgMuted }
                Text {
                    visible: !UsbService.lsusbAvailable
                    text: "usbutils unavailable"
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    color: Theme.fgDim
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                }
                Text {
                    visible: UsbService.lsusbAvailable && filteredDevices.length === 0
                    text: "No other USB devices"
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    color: Theme.fgMuted
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                }
                ListView {
                    id: devicesList
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(180, contentHeight)
                    clip: true
                    spacing: 4
                    model: root.filteredDevices
                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        width: parent.width
                        height: 34
                        radius: Theme.roundingItem
                        readonly property bool isSel: { const it = root.navItems[root.selIndex]; return it !== undefined && it.kind === "device" && it.idx === index }
                        color: isSel ? Theme.bgSelected : (dma.containsMouse ? Theme.bgHover : "transparent")
                        border.color: isSel ? Theme.borderSelected : "transparent"
                        border.width: 1
                        MouseArea { id: dma; anchors.fill: parent; hoverEnabled: true; onClicked: root.selectRow("device", index) }
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Theme.padM
                            anchors.rightMargin: Theme.padM
                            spacing: Theme.gapM
                            Text { text: root.deviceGlyph(modelData); font.family: Theme.fontFamily; font.pixelSize: 16; color: Theme.fg }
                            Text {
                                text: modelData.name
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                                color: Theme.fg
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                            Text {
                                visible: modelData.isStorage
                                text: root.deviceState(modelData)
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                                color: Theme.fgMuted
                                elide: Text.ElideRight
                                Layout.maximumWidth: 190
                            }
                            Text {
                                text: modelData.bus + ":" + modelData.dev + " · " + modelData.vid + ":" + modelData.pid
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                                color: Theme.fgMuted
                            }
                        }
                    }
                }

                Text {
                    visible: UsbService.lastError !== ""
                    text: Icons.warning + " " + UsbService.lastError
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    color: Theme.critical
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                }

                Rectangle {
                    visible: root.passphraseActive
                    Layout.fillWidth: true
                    Layout.preferredHeight: 36
                    radius: Theme.roundingItem
                    color: Theme.bgActive
                    border.color: passField.activeFocus ? Theme.borderSelected : Theme.border
                    border.width: 1
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.padM
                        anchors.rightMargin: Theme.padM
                        spacing: Theme.gapM
                        Text { text: Icons.lock; font.family: Theme.fontFamily; font.pixelSize: 14; color: Theme.warning }
                        TextField {
                            id: passField
                            Layout.fillWidth: true
                            echoMode: TextInput.Password
                            placeholderText: "Passphrase for " + root.passphraseLabel
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
                            Keys.onPressed: (e)=>{
                                if ((e.modifiers & Qt.ControlModifier) && e.key === Qt.Key_S) { passField.echoMode = passField.echoMode === TextInput.Password ? TextInput.Normal : TextInput.Password; e.accepted = true }
                                else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { root.submitPassphrase(); e.accepted = true }
                                else if (e.key === Qt.Key_Escape) { root.closePassphrase(); e.accepted = true }
                            }
                        }
                        Text {
                            text: passField.echoMode === TextInput.Password ? Icons.eye : Icons.eyeOff
                            font.family: Theme.fontFamily
                            font.pixelSize: 14
                            color: Theme.fgMuted
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: passField.echoMode = passField.echoMode === TextInput.Password ? TextInput.Normal : TextInput.Password }
                        }
                    }
                }

                Text {
                    text: {
                        if (confirmText) return confirmText
                        if (!UsbService.monitoring) return "device monitoring lost — press r to refresh · / filter · Esc close"
                        return "j/k · Enter act · m u o e · / filter · r refresh · Esc close"
                    }
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    color: confirmText ? Theme.critical : Theme.fgDim
                    Layout.alignment: Qt.AlignHCenter
                }
            }
        }
        Keys.onPressed: (e)=>{
            if (confirmText !== "") {
                if (e.key === Qt.Key_Y) { confirmYes(); e.accepted = true; return }
                else if (e.key === Qt.Key_N || e.key === Qt.Key_Escape) { confirmText = ""; e.accepted = true; return }
            }
            if (e.key === Qt.Key_Escape) {
                if (passphraseActive) { closePassphrase(); e.accepted = true }
                else if (filterActive) { filterActive = false; clearFilter(); mainCol.forceActiveFocus(); e.accepted = true }
                else root.close()
            }
            else if (passphraseActive) { /* passField owns input while the dialog is open */ }
            else if (e.key === Qt.Key_J || e.key === Qt.Key_Down) { root.moveSel(1); e.accepted = true }
            else if (e.key === Qt.Key_K || e.key === Qt.Key_Up) { root.moveSel(-1); e.accepted = true }
            else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { root.activate(); e.accepted = true }
            else if (e.key === Qt.Key_M) { storageAction("mount"); e.accepted = true }
            else if (e.key === Qt.Key_U) { storageAction("unmount"); e.accepted = true }
            else if (e.key === Qt.Key_O) { storageAction("open"); e.accepted = true }
            else if (e.key === Qt.Key_E) { storageAction("poweroff"); e.accepted = true }
            else if (e.text === "/") { filterActive = true; filterField.forceActiveFocus(); e.accepted = true }
            else if (e.key === Qt.Key_R) { UsbService.refresh(); e.accepted = true }
        }
    }

    function clearFilter() {
        suppressUpdate = true
        filterField.text = ""
        suppressUpdate = false
        updateModels()
    }
    function busyLabel() {
        if (UsbService.busyOp === "mount") return "Mounting…"
        if (UsbService.busyOp === "unmount") return "Unmounting…"
        if (UsbService.busyOp === "poweroff") return "Powering off…"
        if (UsbService.busyOp === "unlock") return "Unlocking…"
        return "Working…"
    }
    function primaryActionLabel(r) {
        if (r.locked) return "Unlock"
        return r.mountPoint ? "Unmount" : "Mount"
    }
    function deviceGlyph(d) {
        if (d.isStorage) return Icons.usbDrive
        if (/hub/i.test(d.name)) return Icons.usbPort
        return Icons.usb
    }
    function deviceState(d) {
        if (!d.isStorage) return ""
        const match = (UsbService.storage || []).find(r => r.vid === d.vid && r.pid === d.pid) || null
        if (!match) return "storage"
        return match.mountPoint ? "mounted · " + match.mountPoint : "storage — not mounted"
    }
    function updateModels() {
        const raw = filterField.text.trim().toLowerCase()
        const q = raw.replace(/^\//, "")
        let st = (UsbService.storage || []).filter(r => r && r.node)
        if (q) st = st.filter(r =>
            (r.label && r.label.toLowerCase().indexOf(q) !== -1) ||
            r.node.toLowerCase().indexOf(q) !== -1 ||
            (r.fstype && r.fstype.toLowerCase().indexOf(q) !== -1) ||
            (r.vid && (r.vid + ":" + r.pid).indexOf(q) !== -1))
        st.sort((a, b) => String(a.label).localeCompare(String(b.label)))
        filteredStorage = st
        let dv = (UsbService.allDevices || []).filter(d => d && d.vid)
        if (q) dv = dv.filter(d =>
            d.name.toLowerCase().indexOf(q) !== -1 ||
            (d.vid + ":" + d.pid).indexOf(q) !== -1 ||
            d.bus.indexOf(q) !== -1 || d.dev.indexOf(q) !== -1)
        dv.sort((a, b) => (parseInt(a.bus) - parseInt(b.bus)) || (parseInt(a.dev) - parseInt(b.dev)))
        filteredDevices = dv
        const items = []
        for (let i = 0; i < st.length; i++) items.push({ kind: "storage", idx: i })
        for (let i = 0; i < dv.length; i++) items.push({ kind: "device", idx: i })
        navItems = items
        selIndex = Math.max(0, Math.min(selIndex, items.length - 1))
        Qt.callLater(() => ensureVisible(selIndex))
    }
    function moveSel(delta) {
        const n = navItems.length
        if (n === 0) return
        selIndex = Math.max(0, Math.min(n - 1, selIndex + delta))
        ensureVisible(selIndex)
        Qt.callLater(() => mainCol.forceActiveFocus())
    }
    function ensureVisible(i) {
        const it = navItems[i]
        if (!it) return
        if (it.kind === "storage" && storageList) storageList.positionViewAtIndex(it.idx, ListView.Contain)
        else if (it.kind === "device" && devicesList) devicesList.positionViewAtIndex(it.idx, ListView.Contain)
    }
    function selectRow(kind, idx) {
        for (let i = 0; i < navItems.length; i++) {
            if (navItems[i].kind === kind && navItems[i].idx === idx) { selIndex = i; break }
        }
        activate()
    }
    function activate() {
        const it = navItems[selIndex]
        if (!it) return
        if (it.kind === "storage") {
            const r = filteredStorage[it.idx]
            if (r) primaryStorageAction(r)
        }
    }
    function isBusy(r) { return UsbService.busyNode === r.node }
    function primaryStorageAction(r) {
        if (!r || !UsbService.udisksAvailable || isBusy(r)) return
        if (r.locked) openPassphrase(r)
        else if (r.mountPoint) UsbService.unmount(r.node)
        else UsbService.mount(r.node)
    }
    function storageAction(op) {
        const it = navItems[selIndex]
        if (!it || it.kind !== "storage") return
        const r = filteredStorage[it.idx]
        if (!r || !UsbService.udisksAvailable || isBusy(r)) return
        if (op === "mount") {
            if (r.locked) openPassphrase(r)
            else if (!r.mountPoint) UsbService.mount(r.node)
        }
        else if (op === "unmount" && r.mountPoint) UsbService.unmount(r.node)
        else if (op === "open" && r.mountPoint) UsbService.openInFileManager(r.mountPoint)
        else if (op === "poweroff") requestPowerOff(r)
    }
    function openStorage(r) {
        if (r && r.mountPoint && !isBusy(r)) UsbService.openInFileManager(r.mountPoint)
    }
    function requestPowerOff(r) {
        if (!r || isBusy(r)) return
        confirmText = "Power off \"" + r.label + "\"?  y / n"
        pendingAction = { type: "poweroff", node: r.diskNode }
    }
    function confirmYes() {
        if (!pendingAction) { confirmText = ""; return }
        if (pendingAction.type === "poweroff") UsbService.powerOff(pendingAction.node)
        confirmText = ""
        pendingAction = null
    }
    function openPassphrase(r) {
        passphraseNode = r.node
        passphraseLabel = r.label
        passphraseActive = true
        passField.text = ""
        Qt.callLater(() => passField.forceActiveFocus())
    }
    function submitPassphrase() {
        UsbService.unlock(passphraseNode, passField.text)
        closePassphrase()
    }
    function closePassphrase() {
        passphraseActive = false
        passField.text = ""
        mainCol.forceActiveFocus()
    }

    Connections { target: UsbService; function onDataUpdated() { updateModels() } }
    Component.onCompleted: updateModels()
    onIsOpenChanged: if (isOpen) {
        filterActive = false
        suppressUpdate = true
        filterField.text = ""
        suppressUpdate = false
        selIndex = 0
        confirmText = ""
        pendingAction = null
        passphraseActive = false
        UsbService.lastError = ""
        UsbService.refresh()
        updateModels()
        Qt.callLater(() => mainCol.forceActiveFocus())
    }
}
