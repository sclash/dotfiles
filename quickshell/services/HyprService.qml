pragma Singleton
import QtQuick
import Quickshell.Io
import Quickshell.Hyprland

QtObject {
    id: root
    property string layoutName: ""
    property bool available: true
    property var monitors: []
    property var allMonitors: []
    property var availableMonitors: []

    function isBuiltinName(name) {
        const n = String(name || "")
        return n.indexOf("eDP") === 0 || n.indexOf("DSI") === 0
    }
    readonly property string refMonitorName: {
        const b = root.allMonitors.find(m => root.isBuiltinName(m.name))
        if (b) return b.name
        const ba = root.monitors.find(m => root.isBuiltinName(m.name))
        if (ba) return ba.name
        return root.monitors.length > 0 ? root.monitors[0].name : ""
    }
    readonly property bool externalAvailable: allMonitors.some(m => m.name !== refMonitorName)
    readonly property bool externalConnected: monitors.some(m => m.name !== refMonitorName)

    function cycleLayout() {
        root.kbProc.running = true
        root.switchProc.running = true
    }
    function refreshMonitors() {
        root.monProc.running = true
    }

    // Main keyboard is discovered from Hyprland itself (no hard-coded device
    // name, no python). The badge shows the active layout code from the
    // configured layout list, so it works for any keymap, not just IT/US.
    property Process kbProc: Process {
        command: ["hyprctl", "devices", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                let k = null
                try {
                    const kbs = JSON.parse(String(this.text || "{}")).keyboards || []
                    k = kbs.find(kb => kb.main) || kbs[0] || null
                } catch (e) { k = null }
                if (!k) { root.layoutName = ""; return }

                const layouts = String(k.layout || "").split(",").map(s => s.trim()).filter(Boolean)
                const rawIdx = Number(k.active_layout_index)
                const idx = (rawIdx >= 0 && rawIdx < layouts.length) ? rawIdx : -1
                const code = idx >= 0 ? layouts[idx] : ""
                if (code) { root.layoutName = code.toUpperCase(); return }

                // Older Hyprland without active_layout_index: best effort.
                const km = String(k.active_keymap || "").toLowerCase()
                root.layoutName = (km.indexOf("italian") !== -1 || km.indexOf("it") === 0) ? "IT" : "US"
            }
        }
    }
    property Process switchProc: Process {
        // `current` is Hyprland's main keyboard on every machine.
        command: ["hyprctl", "switchxkblayout", "current", "next"]
        stdout: StdioCollector { onStreamFinished: root.kbProc.running = true }
    }

    function mapMonitor(m) {
        // Older Hyprland builds omit hardwareDetails; treat as no capabilities.
        const hardwareDetails = m.hardwareDetails || {}
        return {
            name: m.name,
            id: m.id,
            mode: (m.width > 0) ? (m.width + "x" + m.height + "@" + m.refreshRate) : "preferred",
            scale: m.scale,
            pos: m.x + "x" + m.y,
            focused: !!m.focused,
            mirrorOf: m.mirrorOf || "none",
            x: m.x,
            y: m.y,
            w: m.width,
            h: m.height,
            transform: m.transform || 0,
            description: m.description || "",
            make: m.make || "",
            model: m.model || "",
            serial: m.serial || "",
            refreshRate: m.refreshRate || 0,
            availableModes: m.availableModes || [],
            dpmsStatus: !!m.dpmsStatus,
            vrrActive: !!m.vrr,
            vrrCapable: !!hardwareDetails.vrrCapable,
            hdrCapable: !!hardwareDetails.hdr,
            wideColor: !!hardwareDetails.bt2020,
            cm: m.colorManagementPreset || "srgb",
            sdrBrightness: m.sdrBrightness !== undefined ? m.sdrBrightness : 1,
            sdrSaturation: m.sdrSaturation !== undefined ? m.sdrSaturation : 1,
            currentFormat: m.currentFormat || "",
            bitDepth: /2101010/.test(m.currentFormat || "") ? 10 : 8
        }
    }

    property Process monProc: Process {
        command: ["sh", "-c", "hyprctl monitors -j; printf '\\n---SPLIT---\\n'; hyprctl monitors all -j 2>/dev/null || hyprctl monitors -j"]
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = String(this.text || "").split("---SPLIT---")
                let active = []
                let all = []
                try { active = JSON.parse(parts[0]) } catch (err) { active = [] }
                try { all = JSON.parse(parts[1]) } catch (err) { all = [] }
                const activeNames = active.map(m => m.name)
                const mapped = active.map(root.mapMonitor)
                for (const m of all) {
                    if (!m.disabled && activeNames.indexOf(m.name) === -1) mapped.push(root.mapMonitor(m))
                }
                root.monitors = mapped
                root.allMonitors = all.map(m => ({ name: m.name, mode: m.width ? (m.width + "x" + m.height) : "preferred" }))
                root.availableMonitors = all
                    .filter(m => m.disabled && activeNames.indexOf(m.name) === -1)
                    .map(m => ({ name: m.name, mode: m.width ? (m.width + "x" + m.height) : "preferred" }))
            }
        }
    }

    property Connections hyprConn: Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event && event.name === "activelayout") root.kbProc.running = true
            else if (event && (event.name.indexOf("monitor") === 0 || event.name === "configreloaded")) root.monitorDebounce.restart()
        }
    }

    property Timer monitorDebounce: Timer { interval: 300; onTriggered: root.refreshMonitors() }
    property Timer init: Timer { interval: 300; running: true; repeat: false; onTriggered: { root.kbProc.running = true; root.refreshMonitors() } }
}
