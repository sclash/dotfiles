import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../theme"

// Per-output settings view. Renders rows from the compositor state and the
// hardware descriptor and turns keys into service writes; the panel owns no
// processes.
Item {
    id: root

    property var monitor: ({})
    property var hardware: ({})
    // Passed in by DisplayManager: the selected output is duplicating another
    // one, so only the hardware backends remain meaningful here.
    property bool mirrored: false
    // True while the gamma daemon looks reachable on any probed output; used
    // to keep the "not running" hint from firing on outputs without a leaf.
    property bool gammaReachable: true
    property int selIndex: 0
    property bool pickerOpen: false
    property int pickerIndex: 0
    property var pickerOptions: []
    property string pickerRow: ""
    // -1 means "no explicit choice yet"; only 0/1/2 are ever applied.
    property int vrrOverride: -1
    property string _monitorName: ""

    signal closeRequested()
    signal setBrightness(real percent)
    signal setTemperature(int kelvin)
    signal applyCompositor(string key, var value)

    readonly property var brightness: (hardware && hardware.brightness) ? hardware.brightness : ({ available: false })
    readonly property var temperature: (hardware && hardware.temperature) ? hardware.temperature : ({ available: false })
    readonly property bool hdrActive: {
        const cm = root.monitor ? String(root.monitor.cm || "") : ""
        return cm === "hdr" || cm === "hdredid"
    }

    // Row order follows the design spec §7: compositor rows first, then the
    // hardware backends.
    readonly property var rows: {
        const r = []
        if (!root.monitor || !root.monitor.name) return r
        r.push("mode")
        r.push("scale")
        r.push("rotation")
        if (root.monitor.hdrCapable || root.monitor.wideColor || root.monitor.bitDepth === 10)
            r.push("bitdepth")
        if (root.monitor.vrrCapable)
            r.push("vrr")
        r.push("cm")
        if (root.hdrActive) {
            r.push("sdrbrightness")
            r.push("sdrsaturation")
        }
        if (root.brightness.available) r.push("brightness")
        if (root.temperature.available) r.push("temperature")
        return r
    }
    readonly property string brightnessBackend: {
        if (!root.brightness.available) return ""
        return root.brightness.backend === "gamma" ? "software" : root.brightness.backend
    }
    readonly property string unavailableHint: {
        const lines = []
        if (!root.temperature.available && !root.gammaReachable)
            lines.push("wl-gammarelay-rs not running — color temperature unavailable")
        if (!root.brightness.available)
            lines.push("Brightness unavailable — no backlight or DDC/CI")
        return lines.join("\n")
    }

    function currentKind() {
        return root.rows.length > 0 ? root.rows[Math.max(0, Math.min(root.selIndex, root.rows.length - 1))] : ""
    }
    function reset() {
        root.selIndex = 0
        root.pickerOpen = false
        root.pickerIndex = 0
        root.pickerOptions = []
        root.pickerRow = ""
    }

    // ---- Row metadata ------------------------------------------------------

    function isEnumerated(kind) {
        return kind === "mode" || kind === "scale" || kind === "rotation"
            || kind === "bitdepth" || kind === "vrr" || kind === "cm"
    }
    // Every row that writes a monitor rule is a compositor row; brightness and
    // temperature are hardware backends. Keep this broader than the enumerated
    // set (sdrbrightness/sdrsaturation are compositor rows too).
    function isCompositorRow(kind) {
        return kind !== "brightness" && kind !== "temperature"
    }
    // A non-empty reason disables the row and is rendered under its label.
    function rowReason(kind) {
        if (root.mirrored && root.isCompositorRow(kind))
            return "mirrored — extend to configure"
        // No reported mode list means the picker could only echo the current
        // mode, so the row is informational and non-actionable.
        if (kind === "mode" && (!root.monitor.availableModes
            || root.monitor.availableModes.length === 0))
            return "no modes reported"
        if (root.hdrActive) {
            if (kind === "temperature")
                return "unavailable in HDR mode"
            if (kind === "brightness" && root.brightness.backend === "gamma")
                return "unavailable in HDR mode"
        }
        return ""
    }
    function rowEnabled(kind) {
        if (root.rowReason(kind) !== "") return false
        // HDR owns the output format: bit depth is forced to 10 and locked.
        if (kind === "bitdepth" && root.hdrActive) return false
        return true
    }
    function rowLabel(kind) {
        switch (kind) {
        case "mode": return "Mode / refresh"
        case "scale": return "Scale"
        case "rotation": return "Rotation"
        case "bitdepth": return "Bit depth"
        case "vrr": return "VRR"
        case "cm": return "Color preset"
        case "sdrbrightness": return "HDR brightness"
        case "sdrsaturation": return "HDR saturation"
        case "brightness": return "Brightness"
        case "temperature": return "Color temperature"
        }
        return ""
    }
    function rowIcon(kind) {
        switch (kind) {
        case "mode": return Icons.display
        case "scale": return Icons.expand
        case "rotation": return Icons.reboot
        case "bitdepth": return Icons.eye
        case "vrr": return Icons.shade
        case "cm": return Icons.temp
        case "sdrbrightness": return Icons.eye
        case "sdrsaturation": return Icons.temp
        case "brightness": return Icons.eye
        case "temperature": return Icons.temp
        }
        return Icons.settings
    }
    function rowRange(kind) {
        if (kind === "brightness") return { min: root.brightness.min, max: root.brightness.max }
        if (kind === "temperature") return { min: root.temperature.min, max: root.temperature.max }
        if (kind === "sdrbrightness") return { min: 1, max: 2 }
        if (kind === "sdrsaturation") return { min: 0.8, max: 1.2 }
        return { min: 0, max: 1 }
    }
    function rowValue(kind) {
        if (kind === "brightness") return Number(root.brightness.value)
        if (kind === "temperature") return Number(root.temperature.value)
        if (kind === "sdrbrightness") return root.monitor.sdrBrightness !== undefined ? Number(root.monitor.sdrBrightness) : 1
        if (kind === "sdrsaturation") return root.monitor.sdrSaturation !== undefined ? Number(root.monitor.sdrSaturation) : 1
        return 0
    }
    function rowRatio(kind) {
        const r = root.rowRange(kind)
        const span = r.max - r.min
        return span > 0 ? Math.max(0, Math.min(1, (root.rowValue(kind) - r.min) / span)) : 0
    }
    function rowDisplay(kind) {
        if (kind === "brightness") return Math.round(root.rowValue(kind)) + "%"
        if (kind === "temperature") return Math.round(root.rowValue(kind)) + " K"
        if (kind === "sdrbrightness") return root.rowValue(kind).toFixed(2) + "×"
        if (kind === "sdrsaturation") return root.rowValue(kind).toFixed(2)
        if (kind === "bitdepth") return root.effectiveBitDepth() + "-bit"
        if (kind === "vrr") return root.vrrLabel(root.effectiveVrr())
        if (kind === "cm") return root.cmLabel(String(root.monitor.cm || "srgb"))
        if (kind === "scale") return String(root.monitor.scale) + "×"
        if (kind === "rotation") return root.rotationLabel(Number(root.monitor.transform || 0))
        if (kind === "mode") return root.modeLabel(root.monitor.mode)
        return ""
    }

    // ---- Enumerated options -----------------------------------------------

    function modeParts(raw) {
        const match = /^(\d+)x(\d+)@([0-9.]+)/.exec(String(raw || ""))
        if (!match) return null
        return { w: Number(match[1]), h: Number(match[2]), r: Number(match[3]) }
    }
    function modeLabel(raw) {
        const p = root.modeParts(raw)
        if (!p) return String(raw || "")
        return p.w + "×" + p.h + " @ " + Number(p.r.toFixed(2)) + " Hz"
    }
    function rotationLabel(v) {
        if (v === 1) return "90°"
        if (v === 2) return "180°"
        if (v === 3) return "270°"
        return "Normal"
    }
    function vrrLabel(v) {
        if (v === 2) return "Fullscreen only"
        if (v === 1) return "On"
        return "Off"
    }
    function cmLabel(v) {
        switch (v) {
        case "auto": return "Auto"
        case "srgb": return "sRGB"
        case "dcip3": return "DCI-P3"
        case "dp3": return "Display P3"
        case "adobe": return "Adobe RGB"
        case "edid": return "EDID"
        case "wide": return "Wide gamut"
        case "hdr": return "HDR"
        case "hdredid": return "HDR (EDID)"
        }
        return String(v || "")
    }
    function effectiveBitDepth() {
        return root.hdrActive ? 10 : Number(root.monitor.bitDepth || 8)
    }
    function effectiveVrr() {
        return root.vrrOverride >= 0 ? root.vrrOverride : (root.monitor.vrrActive ? 1 : 0)
    }

    function optionsFor(kind) {
        if (kind === "mode") {
            const opts = []
            const modes = root.monitor.availableModes || []
            for (let i = 0; i < modes.length; i++)
                opts.push({ value: modes[i], label: root.modeLabel(modes[i]) })
            const cur = root.modeParts(root.monitor.mode)
            let found = false
            if (cur) {
                for (let i = 0; i < opts.length; i++) {
                    const p = root.modeParts(opts[i].value)
                    if (p && p.w === cur.w && p.h === cur.h && Math.abs(p.r - cur.r) < 0.02) { found = true; break }
                }
            }
            if (!found) opts.unshift({ value: root.monitor.mode || "preferred", label: root.modeLabel(root.monitor.mode) })
            return opts
        }
        if (kind === "scale") {
            const values = [0.5, 0.75, 1, 1.25, 1.5, 1.75, 2, 2.5, 3]
            const cur = Number(root.monitor.scale)
            if (cur > 0 && values.indexOf(cur) === -1) {
                values.push(cur)
                values.sort((a, b) => a - b)
            }
            return values.map(v => ({ value: v, label: String(v) + "×" }))
        }
        if (kind === "rotation") {
            return [
                { value: 0, label: "Normal" },
                { value: 1, label: "90°" },
                { value: 2, label: "180°" },
                { value: 3, label: "270°" }
            ]
        }
        if (kind === "bitdepth") {
            return [{ value: 8, label: "8-bit" }, { value: 10, label: "10-bit" }]
        }
        if (kind === "vrr") {
            return [
                { value: 0, label: "Off" },
                { value: 1, label: "On" },
                { value: 2, label: "Fullscreen only" }
            ]
        }
        if (kind === "cm") {
            const opts = [
                { value: "auto", label: "Auto" },
                { value: "srgb", label: "sRGB" },
                { value: "dcip3", label: "DCI-P3" },
                { value: "dp3", label: "Display P3" },
                { value: "adobe", label: "Adobe RGB" },
                { value: "edid", label: "EDID" }
            ]
            if (root.monitor.wideColor) opts.push({ value: "wide", label: "Wide gamut" })
            if (root.monitor.hdrCapable) {
                opts.push({ value: "hdr", label: "HDR" })
                opts.push({ value: "hdredid", label: "HDR (EDID)" })
            }
            return opts
        }
        return []
    }

    function currentOptionIndex(kind) {
        const opts = root.optionsFor(kind)
        if (kind === "mode") {
            const cur = root.modeParts(root.monitor.mode)
            if (!cur) return -1
            for (let i = 0; i < opts.length; i++) {
                const p = root.modeParts(opts[i].value)
                if (p && p.w === cur.w && p.h === cur.h && Math.abs(p.r - cur.r) < 0.02) return i
            }
            return -1
        }
        let target
        if (kind === "scale") target = Number(root.monitor.scale)
        else if (kind === "rotation") target = Number(root.monitor.transform || 0)
        else if (kind === "bitdepth") target = root.effectiveBitDepth()
        else if (kind === "vrr") target = root.effectiveVrr()
        else if (kind === "cm") target = String(root.monitor.cm || "srgb")
        for (let i = 0; i < opts.length; i++) {
            if (kind === "scale") {
                if (Math.abs(Number(opts[i].value) - target) < 0.001) return i
            } else if (typeof opts[i].value === "number") {
                if (Number(opts[i].value) === Number(target)) return i
            } else if (String(opts[i].value) === String(target)) {
                return i
            }
        }
        return -1
    }

    // ---- Key actions -------------------------------------------------------

    function moveSel(delta) {
        const n = root.rows.length
        if (n === 0) return
        root.selIndex = Math.max(0, Math.min(n - 1, root.selIndex + delta))
        Qt.callLater(() => {
            if (rowsList) rowsList.positionViewAtIndex(root.selIndex, ListView.Contain)
            root.forceActiveFocus()
        })
    }

    function stepValue(kind, delta) {
        const r = root.rowRange(kind)
        const step = kind === "brightness" ? 5 : kind === "temperature" ? 100 : kind === "sdrbrightness" ? 0.05 : 0.02
        const v = Math.max(r.min, Math.min(r.max, root.rowValue(kind) + delta * step))
        if (kind === "temperature") return Math.round(v / 100) * 100
        if (kind === "sdrbrightness" || kind === "sdrsaturation") return Number(v.toFixed(2))
        return Math.round(v)
    }

    function adjust(delta) {
        const kind = root.currentKind()
        if (kind === "" || !root.rowEnabled(kind)) return
        if (root.isEnumerated(kind)) {
            // l enters the option list; h is a no-op on a row (h backs out
            // once the picker is open), matching the app-tray flow.
            if (delta > 0) root.openPicker(kind)
            return
        }
        const v = root.stepValue(kind, delta)
        if (kind === "brightness") root.setBrightness(v)
        else if (kind === "temperature") root.setTemperature(v)
        else if (kind === "sdrbrightness") root.applyCompositor("sdrbrightness", v)
        else if (kind === "sdrsaturation") root.applyCompositor("sdrsaturation", v)
    }

    // Long mode lists scroll under the highlight, so every picker index change
    // must bring the selected option back into view once the delegate exists.
    function ensurePickerVisible() {
        Qt.callLater(() => {
            if (pickerList) pickerList.positionViewAtIndex(root.pickerIndex, ListView.Contain)
        })
    }

    function openPicker(kind) {
        if (!root.rowEnabled(kind)) return
        const opts = root.optionsFor(kind)
        if (opts.length === 0) return
        root.pickerRow = kind
        root.pickerOptions = opts
        const cur = root.currentOptionIndex(kind)
        root.pickerIndex = cur >= 0 ? cur : 0
        root.pickerOpen = true
        root.ensurePickerVisible()
    }

    function commitPicker() {
        if (!root.pickerOpen) return
        const kind = root.pickerRow
        const opts = root.pickerOptions
        const idx = Math.max(0, Math.min(opts.length - 1, root.pickerIndex))
        const value = opts.length > 0 ? opts[idx].value : undefined
        root.pickerOpen = false
        // The output may have become mirrored or entered HDR while the picker
        // was open; never write through a now-disabled row.
        if (kind !== "" && value !== undefined && root.rowEnabled(kind))
            root.applyCompositor(kind, value)
    }

    function activate() {
        if (root.pickerOpen) {
            root.commitPicker()
            return
        }
        const kind = root.currentKind()
        if (kind === "" || !root.rowEnabled(kind)) return
        if (root.isEnumerated(kind)) root.openPicker(kind)
    }

    function back() {
        if (root.pickerOpen) {
            root.pickerOpen = false
            return
        }
        root.closeRequested()
    }

    function handleKey(event) {
        if (event.key === Qt.Key_Escape) { root.back(); return true }
        if (root.pickerOpen) {
            // s/r are manager-level actions; dismiss the picker first so it
            // cannot linger when settings is reopened for the same output.
            if (event.key === Qt.Key_S || event.key === Qt.Key_R) {
                root.pickerOpen = false
                return false
            }
            if (event.key === Qt.Key_J || event.key === Qt.Key_Down) {
                root.pickerIndex = Math.min(root.pickerOptions.length - 1, root.pickerIndex + 1)
                root.ensurePickerVisible()
                return true
            }
            if (event.key === Qt.Key_K || event.key === Qt.Key_Up) {
                root.pickerIndex = Math.max(0, root.pickerIndex - 1)
                root.ensurePickerVisible()
                return true
            }
            if (event.key === Qt.Key_L || event.key === Qt.Key_Right) {
                root.commitPicker()
                return true
            }
            if (event.key === Qt.Key_H || event.key === Qt.Key_Left) {
                root.pickerOpen = false
                return true
            }
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                root.commitPicker()
                return true
            }
            return false
        }
        if (event.key === Qt.Key_J || event.key === Qt.Key_Down) { root.moveSel(1); return true }
        if (event.key === Qt.Key_K || event.key === Qt.Key_Up) { root.moveSel(-1); return true }
        if (event.key === Qt.Key_H || event.key === Qt.Key_Left) { root.adjust(-1); return true }
        if (event.key === Qt.Key_L || event.key === Qt.Key_Right) { root.adjust(1); return true }
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { root.activate(); return true }
        return false
    }

    function setRatio(kind, ratio) {
        if (kind === "" || root.isEnumerated(kind) || !root.rowEnabled(kind)) return
        const r = root.rowRange(kind)
        const raw = r.min + Math.max(0, Math.min(1, ratio)) * (r.max - r.min)
        if (kind === "brightness") root.setBrightness(Math.round(raw))
        else if (kind === "temperature") root.setTemperature(Math.round(raw / 100) * 100)
        else if (kind === "sdrbrightness") root.applyCompositor("sdrbrightness", Number((Math.round(raw / 0.05) * 0.05).toFixed(2)))
        else if (kind === "sdrsaturation") root.applyCompositor("sdrsaturation", Number((Math.round(raw / 0.02) * 0.02).toFixed(2)))
    }

    onMonitorChanged: {
        const name = root.monitor ? (root.monitor.name || "") : ""
        if (name !== root._monitorName) {
            root._monitorName = name
            root.reset()
        }
    }
    onRowsChanged: root.selIndex = Math.max(0, Math.min(root.selIndex, root.rows.length - 1))
    focus: true

    Rectangle {
        id: card
        width: 640
        height: Math.min(640, body.implicitHeight + Theme.padL * 2)
        anchors.centerIn: parent
        radius: Theme.roundingLauncher
        color: Theme.bgLauncher
        border.width: 1
        border.color: Theme.borderActive
        clip: true

        ColumnLayout {
            id: body
            anchors.fill: parent
            anchors.margins: Theme.padL
            spacing: Theme.gapM

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.gapS
                Text {
                    text: root.monitor.name || ""
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                    font.weight: Theme.fontWeightMedium
                    color: Theme.fg
                }
                Text {
                    readonly property string desc: root.monitor.description || root.monitor.make || ""
                    visible: desc.length > 0
                    text: "·"
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    color: Theme.fgDim
                }
                Text {
                    readonly property string desc: root.monitor.description || root.monitor.make || ""
                    text: desc
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    color: Theme.fgMuted
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                    Layout.maximumWidth: Number.POSITIVE_INFINITY
                }
                Text {
                    text: "Settings"
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    color: Theme.fgMuted
                    font.capitalization: Font.AllUppercase
                    font.letterSpacing: 1.2
                }
            }
            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border }

            ListView {
                id: rowsList
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(440, contentHeight)
                clip: true
                spacing: 4
                model: root.rows
                delegate: Rectangle {
                    id: row
                    required property string modelData
                    required property int index
                    readonly property bool isSel: index === root.selIndex
                    readonly property bool isEnum: root.isEnumerated(modelData)
                    readonly property bool rowOn: root.rowEnabled(modelData)
                    readonly property string reason: root.rowReason(modelData)
                    width: rowsList.width
                    height: (isEnum && reason === "") ? 46 : 68
                    radius: Theme.roundingItem
                    color: isSel ? Theme.bgSelected : Theme.bgActive
                    border.color: isSel ? Theme.borderSelected : Theme.border
                    border.width: 1

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.selIndex = row.index
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: Theme.padM
                        spacing: Theme.gapS

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.gapS
                            Text {
                                text: root.rowIcon(row.modelData)
                                font.family: Theme.fontFamily
                                font.pixelSize: 14
                                color: row.isSel ? Theme.fgBright : Theme.fgMuted
                            }
                            Text {
                                text: root.rowLabel(row.modelData)
                                font.family: Theme.fontFamily
                                font.pixelSize: 13
                                color: row.rowOn ? Theme.fg : Theme.fgDim
                                Layout.fillWidth: true
                            }
                            Text {
                                visible: row.modelData === "brightness"
                                text: root.brightnessBackend
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                                color: Theme.fgDim
                            }
                            Text {
                                text: root.rowDisplay(row.modelData)
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                                font.weight: Theme.fontWeightMedium
                                color: row.rowOn ? Theme.fgBright : Theme.fgDim
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: row.rowOn ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    onClicked: (m) => {
                                        root.selIndex = row.index
                                        if (!row.rowOn) return
                                        if (row.isEnum) root.activate()
                                        else root.adjust(m.x < width / 2 ? -1 : 1)
                                    }
                                }
                            }
                            Text {
                                visible: row.isEnum && row.rowOn
                                text: Icons.chevronRight
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                                color: Theme.fgDim
                            }
                        }

                        Text {
                            visible: row.reason.length > 0
                            text: row.reason
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                            color: Theme.fgDim
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }

                        RowLayout {
                            visible: !row.isEnum && row.reason.length === 0
                            Layout.fillWidth: true
                            spacing: Theme.gapS

                            Rectangle {
                                width: 22; height: 22
                                radius: Theme.roundingItem
                                color: minusMouse.containsMouse ? Theme.bgHover : "transparent"
                                Text { anchors.centerIn: parent; text: "−"; font.family: Theme.fontFamily; font.pixelSize: 14; color: Theme.fgMuted }
                                MouseArea {
                                    id: minusMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: { root.selIndex = row.index; root.adjust(-1) }
                                }
                            }

                            Item {
                                Layout.fillWidth: true
                                implicitHeight: 20
                                Rectangle {
                                    id: track
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width
                                    height: 4
                                    radius: 2
                                    color: Theme.border
                                }
                                Rectangle {
                                    width: Math.max(0, Math.min(track.width, track.width * root.rowRatio(row.modelData)))
                                    height: track.height
                                    radius: 2
                                    color: Theme.fgMuted
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                Rectangle {
                                    x: Math.max(0, Math.min(track.width - width, track.width * root.rowRatio(row.modelData) - width / 2))
                                    width: 10; height: 10
                                    radius: 5
                                    color: Theme.fg
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: (m) => {
                                        root.selIndex = row.index
                                        root.setRatio(row.modelData, m.x / width)
                                    }
                                }
                            }

                            Rectangle {
                                width: 22; height: 22
                                radius: Theme.roundingItem
                                color: plusMouse.containsMouse ? Theme.bgHover : "transparent"
                                Text { anchors.centerIn: parent; text: "+"; font.family: Theme.fontFamily; font.pixelSize: 14; color: Theme.fgMuted }
                                MouseArea {
                                    id: plusMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: { root.selIndex = row.index; root.adjust(1) }
                                }
                            }
                        }
                    }
                }
            }

            Text {
                visible: root.unavailableHint.length > 0
                text: root.unavailableHint
                font.family: Theme.fontFamily
                font.pixelSize: 11
                color: Theme.fgDim
                Layout.fillWidth: true
            }

            Text {
                visible: !root.pickerOpen
                text: "settings: j/k row · l open · h/l adjust · Esc back"
                font.family: Theme.fontFamily
                font.pixelSize: 10
                color: Theme.fgDim
                Layout.alignment: Qt.AlignHCenter
            }
        }

        // Modal option list for enumerated rows. Keys are routed by the panel;
        // the backdrop click only dismisses the picker.
        Rectangle {
            id: pickerOverlay
            anchors.fill: parent
            z: 10
            visible: root.pickerOpen
            color: Theme.overlay

            MouseArea {
                anchors.fill: parent
                onClicked: root.back()
            }

            Rectangle {
                width: 380
                // The settings card can be shorter than the picker's natural
                // height (e.g. no hardware rows), so never exceed its inner
                // box: the card clips, and a taller picker would lose its
                // title or footer.
                height: Math.max(0, Math.min(360, pickerCol.implicitHeight + Theme.padL * 2, card.height - Theme.padL * 2))
                anchors.centerIn: parent
                radius: Theme.roundingLauncher
                color: Theme.bgLauncher
                border.width: 1
                border.color: Theme.borderActive

                ColumnLayout {
                    id: pickerCol
                    anchors.fill: parent
                    anchors.margins: Theme.padL
                    spacing: Theme.gapM

                    Text {
                        text: root.rowLabel(root.pickerRow)
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        color: Theme.fgMuted
                        font.capitalization: Font.AllUppercase
                        font.letterSpacing: 1.2
                    }
                    Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border }

                    ListView {
                        id: pickerList
                        Layout.fillWidth: true
                        Layout.preferredHeight: Math.min(260, contentHeight)
                        // The capped picker height can be shorter than the
                        // options: let the list shrink instead of overflowing
                        // the card and pushing the footer out of view.
                        Layout.fillHeight: true
                        Layout.minimumHeight: 0
                        clip: true
                        spacing: 2
                        model: root.pickerOptions
                        delegate: Rectangle {
                            id: pickerItem
                            required property var modelData
                            required property int index
                            readonly property bool isSel: index === root.pickerIndex
                            width: pickerList.width
                            height: 34
                            radius: Theme.roundingItem
                            color: isSel ? Theme.bgSelected : (pickerMouse.containsMouse ? Theme.bgHover : "transparent")
                            border.color: isSel ? Theme.borderSelected : "transparent"
                            border.width: 1

                            Text {
                                anchors.left: parent.left
                                anchors.leftMargin: Theme.padM
                                anchors.verticalCenter: parent.verticalCenter
                                text: pickerItem.modelData.label
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                                color: pickerItem.isSel ? Theme.fgBright : Theme.fg
                            }
                            Text {
                                visible: pickerItem.isSel
                                anchors.right: parent.right
                                anchors.rightMargin: Theme.padM
                                anchors.verticalCenter: parent.verticalCenter
                                text: Icons.check
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                color: Theme.fgMuted
                            }
                            MouseArea {
                                id: pickerMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.pickerIndex = pickerItem.index
                                    root.commitPicker()
                                }
                            }
                        }
                    }

                    Text {
                        text: "picker:   j/k option · l apply · h/Esc back"
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
