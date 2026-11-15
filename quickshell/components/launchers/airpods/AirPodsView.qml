import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../../theme"
import "../../../services"
import "../../../services/airPodsParse.js" as Parse

// Card content of the AirPods launcher (AirPodsCenter.qml).
//
// A pure reader over AirPodsService: the overlay owns the WlrLayershell and
// forwards keys here. This file owns the rows, the selection and every verb
// the keyboard can send. No Process, Timer or systemctl call lives here.
//
// Battery levels are gated on `live`, not on AirPodsService.hasBattery: the
// service keeps the last levels after the daemon removes its status file, so
// hasBattery stays true and the card must draw `--` then, not stale numbers.
Item {
    id: view

    property var navItems: []
    property int selIndex: 0
    property bool filterActive: false
    property alias filterText: filterField.text
    signal closeRequested()

    // The daemon answered and reports a connected device.
    readonly property bool live: AirPodsService.daemonReachable && AirPodsService.connected
    // The listening rows the filter left visible; the Repeater draws these.
    readonly property var modeRows: navItems.filter(it => it.kind === "mode")
    // One empty status block would still take two layout gaps; show it only
    // when there is something to say.
    readonly property bool showStatus: !AirPodsService.daemonReachable
        || !AirPodsService.connected || AirPodsService.lastError !== ""

    implicitWidth: 620
    implicitHeight: mainCol.implicitHeight + Theme.padL * 2
    focus: true

    readonly property string deviceTitle: {
        if (AirPodsService.connected) {
            if (AirPodsService.deviceName !== "") return AirPodsService.deviceName
            if (AirPodsService.modelName !== "") return AirPodsService.modelName
            return "AirPods"
        }
        // A readable status with no device is a real disconnect; a daemon
        // that is starting, stopped or unreadable has its own line below.
        if (AirPodsService.daemonReachable && !AirPodsService.daemonStarting
                && AirPodsService.lastError === "") return "Not connected"
        return "AirPods"
    }

    // An unknown model still shows the number the daemon reports (the live
    // test saw model_name empty with A3439), and says so when it has neither.
    readonly property string modelLine: {
        if (!AirPodsService.connected) return ""
        const name = AirPodsService.modelName
        const number = AirPodsService.modelNumber
        if (name !== "") return number === "" ? name : name + " · " + number
        if (number !== "") return "Model " + number
        return "Model not recognised"
    }

    readonly property var batteryRows: {
        const service = AirPodsService
        const on = view.live
        // A headset reports one level for the whole device. The row shape
        // follows isHeadset alone: a disconnected AirPods Max still shows one
        // Headset row with `--`, not three stale earbud/case rows.
        if (service.isHeadset) {
            const headset = service.headsetBattery
            return [{
                label: "Headset",
                level: on ? headset.level : Parse.LEVEL_UNKNOWN,
                charging: on && headset.charging,
                meta: on ? Parse.podMeta({ charging: headset.charging, inEar: false }) : "",
                lid: ""
            }]
        }
        const left = service.leftPod
        const right = service.rightPod
        const caseBattery = service.caseBattery
        return [
            {
                label: "Left",
                level: on ? left.level : Parse.LEVEL_UNKNOWN,
                charging: on && left.charging,
                meta: on ? Parse.podMeta(left) : "",
                lid: ""
            },
            {
                label: "Right",
                level: on ? right.level : Parse.LEVEL_UNKNOWN,
                charging: on && right.charging,
                meta: on ? Parse.podMeta(right) : "",
                lid: ""
            },
            {
                label: "Case",
                level: on ? caseBattery.level : Parse.LEVEL_UNKNOWN,
                charging: on && caseBattery.charging,
                meta: on ? Parse.podMeta({ charging: caseBattery.charging, inEar: false }) : "",
                lid: on ? Parse.lidText(service.lidState) : ""
            }
        ]
    }

    // Only the rows this device has; the feature order matches navItems.
    readonly property var featureRows: {
        const rows = []
        if (AirPodsService.supportsConversationalAwareness) {
            rows.push({
                kind: "ca", label: "Conversation Awareness",
                value: AirPodsService.conversationalAwareness ? "On" : "Off",
                on: AirPodsService.conversationalAwareness
            })
        }
        if (AirPodsService.supportsOneBudANC) {
            rows.push({
                kind: "onebud", label: "One-Bud ANC",
                value: AirPodsService.oneBudANC ? "On" : "Off",
                on: AirPodsService.oneBudANC
            })
        }
        if (AirPodsService.connected) {
            rows.push({
                kind: "ear", label: "Ear detection",
                value: Parse.earDetectionName(AirPodsService.earDetectionBehavior),
                on: true
            })
        }
        rows.push({ kind: "refresh", label: "Refresh", value: "", on: false })
        return rows
    }

    function hasItem(kind) {
        for (let i = 0; i < navItems.length; i++)
            if (navItems[i].kind === kind) return true
        return false
    }

    function isSelected(kind, mode) {
        const item = navItems[selIndex]
        if (item === undefined || item.kind !== kind) return false
        if (kind === "mode") return item.mode === mode
        return true
    }

    // Rebuilt from the service on every change: availableModes() decides the
    // listening rows, the capability flags the feature rows, and the filter
    // hides settings rows by label. The battery rows are outside navItems, so
    // the filter never hides them.
    function updateModels() {
        const service = AirPodsService
        const items = []
        if (service.connected) {
            const modes = service.availableModes()
            for (let i = 0; i < modes.length; i++) {
                items.push({ kind: "mode", mode: modes[i], label: Parse.noiseModeName(modes[i]) })
            }
            // The level only applies while Adaptive is the active mode.
            if (service.supportsAdaptive && service.noiseMode === Parse.NOISE_ADAPTIVE)
                items.push({ kind: "adaptive", label: "Adaptive level" })
            if (service.supportsConversationalAwareness)
                items.push({ kind: "ca", label: "Conversation Awareness" })
            if (service.supportsOneBudANC)
                items.push({ kind: "onebud", label: "One-Bud ANC" })
            items.push({ kind: "ear", label: "Ear detection" })
        }
        items.push({ kind: "refresh", label: "Refresh" })

        const query = filterText.trim().toLowerCase()
        const shown = query === "" ? items
            : items.filter(it => it.label.toLowerCase().indexOf(query) !== -1)
        navItems = shown
        if (selIndex >= shown.length) selIndex = Math.max(0, shown.length - 1)
    }

    function moveSel(delta) {
        if (navItems.length === 0) return
        selIndex = Math.max(0, Math.min(navItems.length - 1, selIndex + delta))
        Qt.callLater(ensureVisible)
    }

    function adjustSel(delta) {
        const item = navItems[selIndex]
        if (item === undefined || item.kind !== "adaptive") return
        AirPodsService.setAdaptiveNoiseLevel(AirPodsService.adaptiveNoiseLevel + (delta < 0 ? -5 : 5))
    }

    function activate() {
        const item = navItems[selIndex]
        if (item === undefined) return
        if (item.kind === "mode") AirPodsService.setNoiseMode(item.mode)
        else if (item.kind === "ca") AirPodsService.setConversationalAwareness(!AirPodsService.conversationalAwareness)
        else if (item.kind === "onebud") AirPodsService.setOneBudANC(!AirPodsService.oneBudANC)
        else if (item.kind === "ear") AirPodsService.cycleEarDetection()
        else if (item.kind === "refresh") AirPodsService.refresh()
        // "adaptive" has no Enter action: h/l steps it by 5 %.
    }

    // A row click is a keyboard selection plus Enter, so both paths agree.
    function pick(kind, mode) {
        for (let i = 0; i < navItems.length; i++) {
            const item = navItems[i]
            if (item.kind !== kind) continue
            if (kind === "mode" && item.mode !== mode) continue
            selIndex = i
            activate()
            return
        }
    }

    function pressMode(mode) {
        if (!AirPodsService.connected) return
        if (AirPodsService.availableModes().indexOf(mode) >= 0)
            AirPodsService.setNoiseMode(mode)
    }

    function openFilter() {
        filterActive = true
        filterField.forceActiveFocus()
    }

    function clearFilter() {
        filterActive = false
        filterField.text = ""
        updateModels()
        Qt.callLater(() => view.forceActiveFocus())
    }

    // Esc clears the filter first and only then asks the overlay to close.
    // The overlay forwards every key here and acts on closeRequested.
    function handleKey(e) {
        if (e === undefined || e === null) return false
        const key = e.key
        if (key === Qt.Key_Escape) {
            if (filterActive) clearFilter()
            else closeRequested()
            e.accepted = true
            return true
        }
        if (key === Qt.Key_J || key === Qt.Key_Down) { moveSel(1); e.accepted = true; return true }
        if (key === Qt.Key_K || key === Qt.Key_Up) { moveSel(-1); e.accepted = true; return true }
        if (key === Qt.Key_H || key === Qt.Key_Left) { adjustSel(-1); e.accepted = true; return true }
        if (key === Qt.Key_L || key === Qt.Key_Right) { adjustSel(1); e.accepted = true; return true }
        if (key === Qt.Key_Return || key === Qt.Key_Enter || key === Qt.Key_Space) {
            activate()
            e.accepted = true
            return true
        }
        if (key === Qt.Key_O) { pressMode(Parse.NOISE_OFF); e.accepted = true; return true }
        if (key === Qt.Key_T) { pressMode(Parse.NOISE_TRANSPARENCY); e.accepted = true; return true }
        if (key === Qt.Key_A) { pressMode(Parse.NOISE_ADAPTIVE); e.accepted = true; return true }
        if (key === Qt.Key_N) { pressMode(Parse.NOISE_ANC); e.accepted = true; return true }
        if (key === Qt.Key_C) {
            if (AirPodsService.connected && AirPodsService.supportsConversationalAwareness)
                AirPodsService.setConversationalAwareness(!AirPodsService.conversationalAwareness)
            e.accepted = true
            return true
        }
        if (key === Qt.Key_B) {
            if (AirPodsService.connected && AirPodsService.supportsOneBudANC)
                AirPodsService.setOneBudANC(!AirPodsService.oneBudANC)
            e.accepted = true
            return true
        }
        if (key === Qt.Key_E) {
            if (AirPodsService.connected) AirPodsService.cycleEarDetection()
            e.accepted = true
            return true
        }
        if (key === Qt.Key_R) { AirPodsService.refresh(); e.accepted = true; return true }
        if (key === Qt.Key_Slash || e.text === "/") { openFilter(); e.accepted = true; return true }
        return false
    }

    // Rows live inside Repeaters, so the selected one is found by objectName;
    // only a keypress uses this path, never a binding.
    function rowFor(item) {
        const name = item.kind === "mode" ? "row-mode-" + item.mode : "row-" + item.kind
        function walk(node) {
            if (node.objectName === name) return node
            const children = node.children
            for (let i = 0; i < children.length; i++) {
                const hit = walk(children[i])
                if (hit !== null) return hit
            }
            return null
        }
        return walk(view)
    }

    function ensureVisible() {
        const item = navItems[selIndex]
        if (item === undefined) return
        const row = rowFor(item)
        if (row === null || !row.visible) return
        const y = row.mapToItem(mainCol, 0, 0).y
        const top = scrollView.contentY
        const bottom = top + scrollView.height
        if (y < top) {
            scrollView.contentY = Math.max(0, y - Theme.gapM)
        } else if (y + row.height > bottom) {
            const maxY = Math.max(0, scrollView.contentHeight - scrollView.height)
            scrollView.contentY = Math.min(maxY, y + row.height + Theme.gapM - scrollView.height)
        }
    }

    Component.onCompleted: updateModels()

    Connections {
        target: AirPodsService
        function onNoiseModeChanged() { view.updateModels() }
        function onConnectedChanged() { view.updateModels() }
        function onSupportsAdaptiveChanged() { view.updateModels() }
        function onSupportsConversationalAwarenessChanged() { view.updateModels() }
        function onSupportsOneBudANCChanged() { view.updateModels() }
        function onSupportsNoiseControlChanged() { view.updateModels() }
        function onSupportsNoiseOffChanged() { view.updateModels() }
    }

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
                text: "AirPods"
                font.family: Theme.fontFamily
                font.pixelSize: 11
                color: Theme.fgMuted
                font.capitalization: Font.AllUppercase
                font.letterSpacing: 1.2
            }
            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border }

            Rectangle {
                visible: view.filterActive
                Layout.fillWidth: true
                Layout.preferredHeight: 34
                radius: Theme.roundingItem
                color: Theme.bgActive
                border.color: filterField.activeFocus ? Theme.borderSelected : Theme.border
                border.width: 1
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.padM
                    anchors.rightMargin: Theme.padM
                    spacing: Theme.gapS
                    Text {
                        text: Icons.search
                        font.family: Theme.fontFamily
                        font.pixelSize: 14
                        color: Theme.fgMuted
                    }
                    TextField {
                        id: filterField
                        Layout.fillWidth: true
                        placeholderText: "filter settings…"
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
                        onTextChanged: view.updateModels()
                        // Keep the query visible; Esc clears it and returns the
                        // full list, as in every other launcher.
                        onAccepted: view.forceActiveFocus()
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.gapM
                Text {
                    text: Icons.airpods
                    font.family: Theme.fontFamily
                    font.pixelSize: 26
                    color: view.live ? Theme.fg : Theme.fgDim
                    Layout.alignment: Qt.AlignVCenter
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Text {
                        text: view.deviceTitle
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeLauncher
                        font.weight: Theme.fontWeightMedium
                        color: view.live ? Theme.fgBright : Theme.fgMuted
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }
                    Text {
                        visible: view.modelLine !== ""
                        text: view.modelLine
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.fgMuted
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }
                }
            }

            ColumnLayout {
                visible: view.showStatus
                Layout.fillWidth: true
                spacing: 2
                Text {
                    visible: !AirPodsService.daemonReachable
                    text: AirPodsService.daemonStarting ? "Connecting…" : "librepods is not running"
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                    color: AirPodsService.daemonStarting ? Theme.fgMuted : Theme.warning
                    Layout.fillWidth: true
                }
                Text {
                    visible: !AirPodsService.daemonReachable
                    text: AirPodsService.lifecycleError !== "" ? AirPodsService.lifecycleError
                        : (AirPodsService.daemonStarting ? "" : "systemctl --user start librepods")
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    color: Theme.fgDim
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                }
                Text {
                    visible: AirPodsService.daemonReachable && !AirPodsService.connected
                             && AirPodsService.lastError === ""
                    text: "AirPods not connected"
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                    color: Theme.fgMuted
                    Layout.fillWidth: true
                }
                Text {
                    visible: AirPodsService.lastError !== ""
                    text: Icons.warning + " " + AirPodsService.lastError
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    color: Theme.critical
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                }
            }

            Text {
                text: "Battery"
                font.family: Theme.fontFamily
                font.pixelSize: 11
                color: Theme.fgMuted
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.gapS
                Repeater {
                    model: view.batteryRows
                    delegate: RowLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.preferredHeight: 20
                        spacing: Theme.gapM
                        Text {
                            text: modelData.charging ? Icons.batteryCharging : Icons.battery
                            font.family: Theme.fontFamily
                            font.pixelSize: 15
                            color: modelData.charging ? Theme.accent
                                : (view.live ? Theme.fgMuted : Theme.fgDim)
                            Layout.alignment: Qt.AlignVCenter
                        }
                        Text {
                            text: modelData.label
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            color: view.live ? Theme.fg : Theme.fgMuted
                            Layout.preferredWidth: 52
                        }
                        Item { Layout.fillWidth: true }
                        Rectangle {
                            Layout.preferredWidth: 72
                            Layout.preferredHeight: 3
                            Layout.alignment: Qt.AlignVCenter
                            radius: 2
                            color: Theme.border
                            Rectangle {
                                width: parent.width * Parse.levelFraction(modelData.level)
                                height: parent.height
                                radius: 2
                                color: modelData.level >= 0 && modelData.level <= 20 ? Theme.warning
                                    : (modelData.charging ? Theme.accent : Theme.fgMuted)
                            }
                        }
                        Text {
                            text: Parse.levelText(modelData.level)
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            color: view.live ? Theme.fg : Theme.fgMuted
                            horizontalAlignment: Text.AlignRight
                            Layout.preferredWidth: 42
                        }
                        Text {
                            visible: modelData.meta !== ""
                            text: modelData.meta
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                            color: Theme.fgMuted
                        }
                        Text {
                            visible: modelData.lid !== ""
                            text: "Lid " + modelData.lid
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                            color: Theme.fgDim
                        }
                    }
                }
            }

            Text {
                text: "Listening"
                visible: view.modeRows.length > 0 || view.hasItem("adaptive")
                font.family: Theme.fontFamily
                font.pixelSize: 11
                color: Theme.fgMuted
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.gapS
                Repeater {
                    model: view.modeRows
                    delegate: Rectangle {
                        id: modeRow
                        required property var modelData
                        objectName: "row-mode-" + modelData.mode
                        Layout.fillWidth: true
                        Layout.preferredHeight: 30
                        radius: Theme.roundingItem
                        readonly property bool selected: view.isSelected("mode", modelData.mode)
                        readonly property bool active: AirPodsService.noiseMode === modelData.mode
                        color: selected ? Theme.bgSelected : "transparent"
                        border.width: 1
                        border.color: selected ? Theme.borderSelected : "transparent"
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Theme.padM
                            anchors.rightMargin: Theme.padM
                            spacing: Theme.gapM
                            Text {
                                text: modelData.label
                                font.family: Theme.fontFamily
                                font.pixelSize: 13
                                color: modeRow.active ? Theme.fgBright : Theme.fg
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                            }
                            Text {
                                visible: modeRow.active
                                text: Icons.check
                                font.family: Theme.fontFamily
                                font.pixelSize: 13
                                color: Theme.success
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: view.pick("mode", modelData.mode)
                        }
                    }
                }
                Rectangle {
                    objectName: "row-adaptive"
                    visible: view.hasItem("adaptive")
                    Layout.fillWidth: true
                    Layout.preferredHeight: 30
                    radius: Theme.roundingItem
                    readonly property bool selected: view.isSelected("adaptive")
                    color: selected ? Theme.bgSelected : "transparent"
                    border.width: 1
                    border.color: selected ? Theme.borderSelected : "transparent"
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.padM
                        anchors.rightMargin: Theme.padM
                        spacing: Theme.gapM
                        Text {
                            text: "Adaptive level"
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            color: Theme.fg
                            Layout.fillWidth: true
                        }
                        Rectangle {
                            Layout.preferredWidth: 90
                            Layout.preferredHeight: 3
                            Layout.alignment: Qt.AlignVCenter
                            radius: 2
                            color: Theme.border
                            Rectangle {
                                width: parent.width * Parse.levelFraction(AirPodsService.adaptiveNoiseLevel)
                                height: parent.height
                                radius: 2
                                color: Theme.fgMuted
                            }
                        }
                        Text {
                            text: Parse.levelText(AirPodsService.adaptiveNoiseLevel)
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            color: Theme.fg
                            horizontalAlignment: Text.AlignRight
                            Layout.preferredWidth: 42
                        }
                        Text {
                            text: "h/l"
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                            color: Theme.fgDim
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: view.pick("adaptive")
                    }
                }
            }

            Text {
                text: "Features"
                visible: view.hasItem("ca") || view.hasItem("onebud")
                         || view.hasItem("ear") || view.hasItem("refresh")
                font.family: Theme.fontFamily
                font.pixelSize: 11
                color: Theme.fgMuted
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.gapS
                Repeater {
                    model: view.featureRows
                    delegate: Rectangle {
                        required property var modelData
                        objectName: "row-" + modelData.kind
                        visible: view.hasItem(modelData.kind)
                        Layout.fillWidth: true
                        Layout.preferredHeight: 30
                        radius: Theme.roundingItem
                        readonly property bool selected: view.isSelected(modelData.kind)
                        color: selected ? Theme.bgSelected : "transparent"
                        border.width: 1
                        border.color: selected ? Theme.borderSelected : "transparent"
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Theme.padM
                            anchors.rightMargin: Theme.padM
                            spacing: Theme.gapM
                            Text {
                                text: modelData.label
                                font.family: Theme.fontFamily
                                font.pixelSize: 13
                                color: Theme.fg
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                            }
                            Text {
                                text: modelData.kind === "refresh" && AirPodsService.busy
                                    ? "Working…" : modelData.value
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                color: modelData.kind === "refresh" ? Theme.fgDim
                                    : (modelData.on ? Theme.fgBright : Theme.fgMuted)
                                Layout.maximumWidth: 280
                                elide: Text.ElideRight
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: view.pick(modelData.kind)
                        }
                    }
                }
            }

            Text {
                visible: view.filterActive && view.navItems.length === 0
                text: "No matching settings"
                font.family: Theme.fontFamily
                font.pixelSize: 11
                color: Theme.fgDim
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
            }

            Text {
                text: "j/k · Enter · o/t/a/n modes · c CA · b One-Bud · e ear · r refresh · / filter · Esc close"
                font.family: Theme.fontFamily
                font.pixelSize: 10
                color: Theme.fgDim
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
            }
        }
    }
}
