import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../../theme"
import "../../services"

// Screen-Cast — SUPER+SHIFT+K. Scans for network displays through the GNOME Network
// Displays daemon, connects, and exposes the cast output's settings.
// Spec: specs/launchers/Screen-Cast.md
WlrLayershell {
    id: root

    property bool isOpen: false
    property bool filterActive: false
    property bool suppressUpdate: false
    property string view: "main"          // main | settings
    property var navItems: []
    property int selIndex: 0
    property var filteredSinks: []

    // Settings picker state (resolution / scale)
    property bool pickerOpen: false
    property string pickerKind: ""
    property var pickerOptions: []

    readonly property var scales: [0.5, 0.75, 1, 1.25, 1.5, 1.75, 2, 2.5, 3]
    readonly property bool active: ScreenCastService.active !== null
    readonly property string effectiveMode: root.active ? ScreenCastService.active.mode : ScreenCastService.mode

    function open() { isOpen = true }
    function close() { isOpen = false; filterActive = false; pickerOpen = false; ScreenCastService.close() }
    function toggle() { if (isOpen) close(); else open() }

    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    visible: isOpen
    keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
        anchors.fill: parent
        color: Theme.overlay
        MouseArea { anchors.fill: parent; onClicked: root.close() }
    }

    Rectangle {
        width: 640
        height: Math.min(660, column.implicitHeight + Theme.padL * 2)
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
            contentHeight: column.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar {
                policy: ScrollBar.AsNeeded
                width: 4
                background: Rectangle { color: "transparent" }
                contentItem: Rectangle { color: Theme.borderActive; radius: 2 }
            }

            ColumnLayout {
                id: column
                width: scrollView.width
                spacing: Theme.gapM
                focus: true

                Text {
                    text: root.view === "settings" ? "Session settings" : "Cast"
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    color: Theme.fgMuted
                    font.capitalization: Font.AllUppercase
                    font.letterSpacing: 1.2
                }
                Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.border }

                // ---- Main view ------------------------------------------------
                ColumnLayout {
                    visible: root.view === "main"
                    Layout.fillWidth: true
                    spacing: Theme.gapM

                    // Mode chips
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.gapS
                        Repeater {
                            model: [
                                { value: "duplicate", label: "Duplicate" },
                                { value: "extend", label: "Extend" },
                                { value: "only-remote", label: "Only remote" }
                            ]
                            delegate: Rectangle {
                                required property var modelData
                                required property int index
                                Layout.fillWidth: true
                                Layout.preferredHeight: 32
                                radius: Theme.roundingItem
                                readonly property bool isMode: root.effectiveMode === modelData.value
                                readonly property bool isSel: {
                                    const it = root.navItems[root.selIndex]
                                    return it !== undefined && it.kind === "mode" && it.value === modelData.value
                                }
                                color: isSel ? Theme.bgSelected : (isMode ? Theme.bgActive : Theme.bgHover)
                                border.width: 1
                                border.color: isSel ? Theme.accent : (isMode ? Theme.borderSelected : Theme.border)
                                opacity: root.active ? 0.6 : 1
                                Text {
                                    anchors.centerIn: parent
                                    text: modelData.label
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    color: parent.isSel || parent.isMode ? Theme.fg : Theme.fgMuted
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    enabled: !root.active
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: { ScreenCastService.mode = modelData.value; root.selIndex = index; root.updateNav() }
                                }
                            }
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        color: Theme.fgMuted
                        text: {
                            if (root.active) return "A session is active — disconnect to change mode."
                            if (ScreenCastService.mode === "extend")
                                return "Connect, then pick \"" + ScreenCastService.extendOutput + "\" in the share dialog. It becomes a second desktop."
                            if (ScreenCastService.mode === "only-remote")
                                return "Connect and pick your built-in display; once streaming, press s to turn the panel off."
                            return "Connect, then pick your built-in display in the share dialog."
                        }
                    }

                    // Filter + scan
                    RowLayout {
                        Layout.fillWidth: true
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
                                Text { text: Icons.search; font.family: Theme.fontFamily; font.pixelSize: 14; color: Theme.fgMuted }
                                TextField {
                                    id: filterField
                                    Layout.fillWidth: true
                                    placeholderText: "filter displays…"
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
                                    onTextChanged: if (!root.suppressUpdate) root.updateNav()
                                    onAccepted: { root.filterActive = false; root.clearFilter(); Qt.callLater(() => column.forceActiveFocus()) }
                                }
                            }
                        }
                        Rectangle {
                            Layout.preferredWidth: 80
                            Layout.preferredHeight: 32
                            radius: Theme.roundingItem
                            readonly property bool isSel: {
                                const it = root.navItems[root.selIndex]
                                return it !== undefined && it.kind === "scan"
                            }
                            color: isSel ? Theme.bgSelected : Theme.bgHover
                            border.width: 1
                            border.color: isSel ? Theme.accent : Theme.border
                            Text {
                                anchors.centerIn: parent
                                text: ScreenCastService.scanning ? "Scanning…" : "Scan"
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                color: Theme.fg
                            }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: ScreenCastService.rescan() }
                        }
                    }

                    Text { text: "Displays"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fgMuted }

                    Text {
                        visible: root.filteredSinks.length === 0
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        color: Theme.fgDim
                        text: {
                            if (!ScreenCastService.available)
                                return "Network Displays unavailable — run `update` to install the daemon."
                            if (!ScreenCastService.daemonRunning || ScreenCastService.scanning)
                                return "Scanning for displays…"
                            if (ScreenCastService.sinks.length === 0)
                                return "No displays found — put the TV in Screen Mirroring / Wireless Display mode and press r."
                            return "No display matches the filter."
                        }
                    }

                    ListView {
                        id: sinkList
                        visible: root.filteredSinks.length > 0
                        Layout.fillWidth: true
                        Layout.preferredHeight: Math.min(180, contentHeight)
                        clip: true
                        spacing: 4
                        model: root.filteredSinks
                        delegate: Rectangle {
                            required property var modelData
                            required property int index
                            width: parent.width
                            height: 44
                            radius: Theme.roundingItem
                            readonly property bool isSel: {
                                const it = root.navItems[root.selIndex]
                                return it !== undefined && it.kind === "sink" && it.idx === index
                            }
                            color: isSel ? Theme.bgSelected : (sinkMouse.containsMouse ? Theme.bgHover : "transparent")
                            border.width: 1
                            border.color: isSel ? Theme.borderSelected : "transparent"
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: Theme.padM
                                anchors.rightMargin: Theme.padM
                                spacing: Theme.gapM
                                Text {
                                    text: Icons.monitor
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 16
                                    color: Theme.fg
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2
                                    Text {
                                        Layout.fillWidth: true
                                        text: modelData.name
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 13
                                        color: Theme.fg
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: ScreenCastService.protocolLabel(modelData.protocol) + " · " + ScreenCastService.stateLabel(modelData.state)
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 10
                                        color: Theme.fgMuted
                                        elide: Text.ElideRight
                                    }
                                }
                            }
                            MouseArea {
                                id: sinkMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: ScreenCastService.connectSink(modelData)
                            }
                        }
                    }

                    // Active session
                    Rectangle {
                        visible: root.active
                        Layout.fillWidth: true
                        implicitHeight: sessionColumn.implicitHeight + Theme.padM * 2
                        radius: Theme.roundingItem
                        color: Theme.bgActive
                        border.width: 1
                        border.color: Theme.borderSelected
                        ColumnLayout {
                            id: sessionColumn
                            anchors.fill: parent
                            anchors.margins: Theme.padM
                            spacing: 6
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Theme.gapM
                                Text {
                                    text: ScreenCastService.sessionState === "streaming" ? Icons.display : Icons.monitor
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 16
                                    color: Theme.fg
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2
                                    Text {
                                        Layout.fillWidth: true
                                        text: ScreenCastService.active ? ScreenCastService.active.name : ""
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 13
                                        font.weight: Theme.fontWeightMedium
                                        color: Theme.fg
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: {
                                            if (!ScreenCastService.active) return ""
                                            const mode = ScreenCastService.modeLabel(ScreenCastService.active.mode)
                                            const proto = ScreenCastService.protocolLabel(ScreenCastService.active.protocol)
                                            if (ScreenCastService.sessionState === "connecting")
                                                return mode + " · " + proto + " · waiting for the share dialog…"
                                            if (ScreenCastService.sessionState === "streaming")
                                                return mode + " · " + proto + " · streaming"
                                            if (ScreenCastService.sessionState === "error")
                                                return mode + " · " + proto + " · error"
                                            return mode + " · " + proto
                                        }
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 11
                                        color: Theme.fgMuted
                                        elide: Text.ElideRight
                                    }
                                }
                            }
                            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.border }
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Theme.gapM
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 30
                                    radius: Theme.roundingItem
                                    readonly property bool isSel: {
                                        const it = root.navItems[root.selIndex]
                                        return it !== undefined && it.kind === "settings"
                                    }
                                    color: isSel ? Theme.bgSelected : Theme.bgHover
                                    border.width: 1
                                    border.color: isSel ? Theme.accent : Theme.border
                                    Text { anchors.centerIn: parent; text: "Settings"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fg }
                                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.openSettings() }
                                }
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 30
                                    radius: Theme.roundingItem
                                    readonly property bool isSel: {
                                        const it = root.navItems[root.selIndex]
                                        return it !== undefined && it.kind === "disconnect"
                                    }
                                    color: isSel ? Theme.bgSelected : Theme.bgHover
                                    border.width: 1
                                    border.color: isSel ? Theme.critical : Theme.border
                                    Text { anchors.centerIn: parent; text: "Disconnect"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.critical }
                                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: ScreenCastService.disconnect() }
                                }
                            }
                        }
                    }
                }

                // ---- Settings view -------------------------------------------
                ColumnLayout {
                    visible: root.view === "settings"
                    Layout.fillWidth: true
                    spacing: Theme.gapM

                    Text {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        color: Theme.fg
                        text: ScreenCastService.active ? ScreenCastService.active.name : ""
                    }
                    Text {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        color: Theme.fgMuted
                        text: {
                            if (!ScreenCastService.castOutput) return "The cast output is not visible yet."
                            const name = ScreenCastService.castOutput.name
                            const size = ScreenCastService.castOutput.w + "×" + ScreenCastService.castOutput.h
                                + " @ " + Math.round(ScreenCastService.castOutput.refreshRate) + " Hz"
                                + " · scale " + ScreenCastService.castOutput.scale
                            return name + " · " + size
                        }
                    }

                    Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.border }

                    // Resolution (extend only — the output is ours to size)
                    Rectangle {
                        visible: ScreenCastService.active !== null && ScreenCastService.active.mode === "extend"
                        Layout.fillWidth: true
                        Layout.preferredHeight: 36
                        radius: Theme.roundingItem
                        readonly property bool isSel: {
                            const it = root.navItems[root.selIndex]
                            return it !== undefined && it.kind === "sres"
                        }
                        color: isSel ? Theme.bgSelected : Theme.bgHover
                        border.width: 1
                        border.color: isSel ? Theme.borderSelected : Theme.border
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Theme.padM
                            anchors.rightMargin: Theme.padM
                            Text { Layout.fillWidth: true; text: "Resolution"; font.family: Theme.fontFamily; font.pixelSize: 12; color: Theme.fg }
                            Text {
                                text: ScreenCastService.castOutput ? root.resolutionLabel(ScreenCastService.castOutput.mode) : "—"
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                color: Theme.fgMuted
                            }
                        }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.openPicker("mode") }
                    }
                    Text {
                        visible: ScreenCastService.active !== null && ScreenCastService.active.mode === "extend"
                            && (!ScreenCastService.castOutput || !ScreenCastService.castOutput.availableModes
                                || ScreenCastService.castOutput.availableModes.length === 0)
                        Layout.fillWidth: true
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        color: Theme.fgDim
                        text: "No modes reported for this output"
                    }

                    // Scale (extend only)
                    Rectangle {
                        visible: ScreenCastService.active !== null && ScreenCastService.active.mode === "extend"
                        Layout.fillWidth: true
                        Layout.preferredHeight: 36
                        radius: Theme.roundingItem
                        readonly property bool isSel: {
                            const it = root.navItems[root.selIndex]
                            return it !== undefined && it.kind === "sscale"
                        }
                        color: isSel ? Theme.bgSelected : Theme.bgHover
                        border.width: 1
                        border.color: isSel ? Theme.borderSelected : Theme.border
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Theme.padM
                            anchors.rightMargin: Theme.padM
                            Text { Layout.fillWidth: true; text: "Scale"; font.family: Theme.fontFamily; font.pixelSize: 12; color: Theme.fg }
                            Text {
                                text: ScreenCastService.castOutput ? String(ScreenCastService.castOutput.scale) : "—"
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                color: Theme.fgMuted
                            }
                        }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.openPicker("scale") }
                    }

                    // Local panel (only-remote)
                    Rectangle {
                        visible: ScreenCastService.active !== null && ScreenCastService.active.mode === "only-remote"
                        Layout.fillWidth: true
                        Layout.preferredHeight: 36
                        radius: Theme.roundingItem
                        readonly property bool isSel: {
                            const it = root.navItems[root.selIndex]
                            return it !== undefined && it.kind === "spanel"
                        }
                        color: isSel ? Theme.bgSelected : Theme.bgHover
                        border.width: 1
                        border.color: isSel ? Theme.borderSelected : Theme.border
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Theme.padM
                            anchors.rightMargin: Theme.padM
                            Text { Layout.fillWidth: true; text: "Local panel"; font.family: Theme.fontFamily; font.pixelSize: 12; color: Theme.fg }
                            Text {
                                text: ScreenCastService.localPanelOff ? "Off" : "On"
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                color: ScreenCastService.localPanelOff ? Theme.fgMuted : Theme.fg
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: ScreenCastService.setLocalPanel(ScreenCastService.localPanelOff)
                        }
                    }

                    Text {
                        visible: ScreenCastService.active !== null && ScreenCastService.active.mode !== "extend"
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        color: Theme.fgDim
                        text: "Resolution and scale follow the built-in panel in this mode."
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 32
                        radius: Theme.roundingItem
                        readonly property bool isSel: {
                            const it = root.navItems[root.selIndex]
                            return it !== undefined && it.kind === "sback"
                        }
                        color: isSel ? Theme.bgSelected : Theme.bgHover
                        border.width: 1
                        border.color: isSel ? Theme.borderSelected : Theme.border
                        Text { anchors.centerIn: parent; text: "Back"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fg }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.showMain() }
                    }
                }

                // ---- Picker --------------------------------------------------
                ColumnLayout {
                    visible: root.pickerOpen
                    Layout.fillWidth: true
                    spacing: Theme.gapS

                    Text {
                        Layout.fillWidth: true
                        text: root.pickerKind === "scale" ? "Select scale" : "Select resolution"
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        color: Theme.fgMuted
                    }
                    Repeater {
                        model: root.pickerOpen ? root.pickerOptions : []
                        delegate: Rectangle {
                            required property var modelData
                            required property int index
                            Layout.fillWidth: true
                            Layout.preferredHeight: 34
                            radius: Theme.roundingItem
                            readonly property bool isSel: {
                                const it = root.navItems[root.selIndex]
                                return it !== undefined && it.kind === "popt" && it.idx === index
                            }
                            color: isSel ? Theme.bgSelected : Theme.bgHover
                            border.width: 1
                            border.color: isSel ? Theme.borderSelected : Theme.border
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.left: parent.left
                                anchors.leftMargin: Theme.padM
                                text: String(modelData.label)
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                                color: Theme.fg
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: { root.selIndex = index; root.applyPicker() }
                            }
                        }
                    }
                }

                Text {
                    visible: ScreenCastService.lastError !== ""
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    color: Theme.critical
                    text: Icons.warning + " " + ScreenCastService.lastError
                }

                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    color: Theme.fgDim
                    text: {
                        if (root.pickerOpen) return "picker: j/k option · Enter/l apply · h/Esc back"
                        if (root.view === "settings") return "settings: j/k row · Enter act · Esc back"
                        return "j/k move · Enter connect · 1/2/3 mode · s settings · d disconnect · r rescan · / filter · Esc close"
                    }
                }
            }
        }

        Keys.onPressed: (e) => {
            if (e.key === Qt.Key_Escape) {
                if (root.pickerOpen) { root.closePicker(); e.accepted = true }
                else if (root.view === "settings") { root.showMain(); e.accepted = true }
                else if (root.filterActive) { root.filterActive = false; root.clearFilter(); column.forceActiveFocus(); e.accepted = true }
                else root.close()
            } else if (e.key === Qt.Key_J || e.key === Qt.Key_Down) {
                root.moveSel(1); e.accepted = true
            } else if (e.key === Qt.Key_K || e.key === Qt.Key_Up) {
                root.moveSel(-1); e.accepted = true
            } else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                root.activate(); e.accepted = true
            } else if (e.key === Qt.Key_1) {
                if (!root.active) { ScreenCastService.mode = "duplicate"; root.updateNav() }
                e.accepted = true
            } else if (e.key === Qt.Key_2) {
                if (!root.active) { ScreenCastService.mode = "extend"; root.updateNav() }
                e.accepted = true
            } else if (e.key === Qt.Key_3) {
                if (!root.active) { ScreenCastService.mode = "only-remote"; root.updateNav() }
                e.accepted = true
            } else if (e.key === Qt.Key_L) {
                if (root.pickerOpen) root.applyPicker(); else root.activate()
                e.accepted = true
            } else if (e.key === Qt.Key_H) {
                if (root.pickerOpen) root.closePicker()
                else if (root.view === "settings") root.showMain()
                e.accepted = true
            } else if (e.key === Qt.Key_R) {
                ScreenCastService.rescan(); e.accepted = true
            } else if (e.key === Qt.Key_D) {
                ScreenCastService.disconnect(); e.accepted = true
            } else if (e.key === Qt.Key_S) {
                if (root.active) root.openSettings()
                e.accepted = true
            } else if (e.text === "/") {
                root.filterActive = true; filterField.forceActiveFocus(); e.accepted = true
            }
        }
    }

    onIsOpenChanged: {
        if (!isOpen) return
        ScreenCastService.clearError()
        ScreenCastService.open()
        root.view = "main"
        root.pickerOpen = false
        root.selIndex = 0
        root.updateNav()
        Qt.callLater(() => column.forceActiveFocus())
    }

    Connections {
        target: ScreenCastService
        function onDataUpdated() { root.updateNav() }
    }

    // ---- Navigation ---------------------------------------------------------
    function modeLabel(raw) {
        const m = /^(\d+)x(\d+)@([0-9.]+)/.exec(String(raw || ""))
        if (!m) return String(raw || "")
        return m[1] + "×" + m[2] + " @ " + Number(Number(m[3]).toFixed(2)) + " Hz"
    }

    function resolutionLabel(raw) { return root.modeLabel(raw) }

    function sameSinkList(a, b) {
        if (a.length !== b.length) return false
        for (let i = 0; i < a.length; i++) if (a[i].uuid !== b[i].uuid) return false
        return true
    }

    function clearFilter() {
        root.suppressUpdate = true
        filterField.text = ""
        root.suppressUpdate = false
        root.updateNav()
    }

    function updateNav() {
        const query = root.filterActive ? filterField.text.trim().toLowerCase() : ""
        let sinks = ScreenCastService.sinks
        if (query !== "") sinks = sinks.filter(s => s.name.toLowerCase().indexOf(query) !== -1)
        if (!root.sameSinkList(root.filteredSinks, sinks)) root.filteredSinks = sinks

        if (root.pickerOpen) return

        const items = []
        if (root.view === "main") {
            items.push({ kind: "mode", value: "duplicate" })
            items.push({ kind: "mode", value: "extend" })
            items.push({ kind: "mode", value: "only-remote" })
            items.push({ kind: "scan" })
            for (let i = 0; i < sinks.length; i++) items.push({ kind: "sink", idx: i })
            if (root.active) {
                items.push({ kind: "settings" })
                items.push({ kind: "disconnect" })
            }
        } else {
            if (ScreenCastService.active !== null && ScreenCastService.active.mode === "extend") {
                items.push({ kind: "sres" })
                items.push({ kind: "sscale" })
            }
            if (ScreenCastService.active !== null && ScreenCastService.active.mode === "only-remote") items.push({ kind: "spanel" })
            items.push({ kind: "sback" })
        }
        root.navItems = items
        root.selIndex = Math.max(0, Math.min(root.selIndex, items.length - 1))
    }

    function moveSel(delta) {
        const n = root.navItems.length
        if (n === 0) return
        root.selIndex = Math.max(0, Math.min(n - 1, root.selIndex + delta))
        const it = root.navItems[root.selIndex]
        if (it && it.kind === "sink" && sinkList) sinkList.positionViewAtIndex(it.idx, ListView.Contain)
        Qt.callLater(() => column.forceActiveFocus())
    }

    function activate() {
        const it = root.navItems[root.selIndex]
        if (!it) return
        if (it.kind === "mode") { if (!root.active) { ScreenCastService.mode = it.value; root.updateNav() } }
        else if (it.kind === "scan") ScreenCastService.rescan()
        else if (it.kind === "sink") { const s = root.filteredSinks[it.idx]; if (s) ScreenCastService.connectSink(s) }
        else if (it.kind === "settings") root.openSettings()
        else if (it.kind === "disconnect") ScreenCastService.disconnect()
        else if (it.kind === "sres") root.openPicker("mode")
        else if (it.kind === "sscale") root.openPicker("scale")
        else if (it.kind === "spanel") ScreenCastService.setLocalPanel(ScreenCastService.localPanelOff)
        else if (it.kind === "sback") root.showMain()
        else if (it.kind === "popt") root.applyPicker()
    }

    function openSettings() {
        if (!root.active) return
        root.view = "settings"
        root.selIndex = 0
        root.updateNav()
        Qt.callLater(() => column.forceActiveFocus())
    }

    function showMain() {
        root.view = "main"
        root.pickerOpen = false
        root.selIndex = 0
        root.updateNav()
        Qt.callLater(() => column.forceActiveFocus())
    }

    function openPicker(kind) {
        if (!root.active) return
        const options = []
        if (kind === "scale") {
            for (const s of root.scales) options.push({ label: String(s) + "×", value: s })
        } else {
            const monitor = ScreenCastService.castOutput
            const modes = monitor && monitor.availableModes ? monitor.availableModes : []
            for (const m of modes) options.push({ label: root.resolutionLabel(m), value: String(m) })
            if (options.length === 0) return
        }
        root.pickerKind = kind
        root.pickerOptions = options
        root.pickerOpen = true
        root.navItems = options.map((_, i) => ({ kind: "popt", idx: i }))
        root.selIndex = 0
        Qt.callLater(() => column.forceActiveFocus())
    }

    function closePicker() {
        root.pickerOpen = false
        root.pickerOptions = []
        root.selIndex = 0
        root.updateNav()
        Qt.callLater(() => column.forceActiveFocus())
    }

    function applyPicker() {
        const it = root.navItems[root.selIndex]
        if (!it || it.kind !== "popt") return
        const option = root.pickerOptions[it.idx]
        if (!option) return
        ScreenCastService.applyOutput(root.pickerKind, option.value)
        root.closePicker()
    }
}
