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

    // ---- Monitor rules -----------------------------------------------------
    // Every compositor mutation goes through these helpers so the launchers
    // never build lua by hand.

    function luaQuote(s) {
        return "\"" + String(s).replace(/\\/g, "\\\\").replace(/"/g, "\\\"") + "\""
    }

    // Current compositor value for an optional rule field, or undefined when
    // the field is absent (older Hyprland) or not meaningful for this output.
    // `vrr` always returns undefined: hyprctl's `vrr` field is the *active*
    // state, which Hyprland drops while no VRR-eligible surface is visible, so
    // it must never be written back from state. It is emitted only when an
    // override supplies it explicitly.
    function currentRuleValue(m, key) {
        if (!m) return undefined
        switch (key) {
        case "transform":
            return (m.transform !== undefined && m.transform !== null) ? m.transform : undefined
        case "vrr":
            return undefined
        case "bitdepth":
            return m.currentFormat ? m.bitDepth : undefined
        case "cm":
            return m.cm ? m.cm : undefined
        case "sdrbrightness":
            return (m.sdrBrightness !== undefined && m.sdrBrightness !== null) ? m.sdrBrightness : undefined
        case "sdrsaturation":
            return (m.sdrSaturation !== undefined && m.sdrSaturation !== null) ? m.sdrSaturation : undefined
        }
        return undefined
    }

    // Builds one `hl.monitor` rule. `m` is a mapped monitor or a synthetic
    // {name, mode, position, scale, mirror} object for outputs that are not
    // in `monitors` yet (connect). Overrides win; otherwise the current value
    // is re-asserted so the rule is idempotent.
    function monitorRule(m, overrides) {
        if (!m) return ""
        const o = overrides || {}
        if (o.disabled === true)
            return "hl.monitor({output=" + root.luaQuote(m.name) + ", disabled=true})"

        const mirror = (o.mirror !== undefined) ? String(o.mirror)
            : (m.mirror !== undefined ? String(m.mirror) : root.mirrorName(m))
        const mode = (o.mode !== undefined) ? o.mode : (m.mode !== undefined ? m.mode : "preferred")
        const position = (o.position !== undefined) ? o.position
            : (m.position !== undefined ? m.position : (m.x + "x" + m.y))
        const scale = (o.scale !== undefined) ? o.scale : (m.scale !== undefined ? m.scale : 1)

        let lua = "hl.monitor({output=" + root.luaQuote(m.name)
            + ", disabled=false"
            + ", mirror=" + root.luaQuote(mirror)
            + ", mode=" + root.luaQuote(mode)
            + ", position=" + root.luaQuote(position)
            + ", scale=" + Number(scale)

        const optional = ["transform", "vrr", "bitdepth", "cm", "sdrbrightness", "sdrsaturation"]
        for (const key of optional) {
            const v = (o[key] !== undefined && o[key] !== null)
                ? o[key]
                : root.currentRuleValue(m, key)
            if (v === undefined || v === null) continue
            lua += ", " + key + "=" + (key === "cm" ? root.luaQuote(v) : Number(v))
        }
        return lua + "})"
    }

    // Full rule for every other active, non-mirrored output so a mutation
    // never disturbs the rest of the layout.
    function preserveRules(exceptIdx) {
        let lua = ""
        for (let i = 0; i < root.monitors.length; i++) {
            if (i === exceptIdx) continue
            const m = root.monitors[i]
            if (root.mirrorName(m)) continue
            lua += root.monitorRule(m, {}) + "; "
        }
        return lua
    }

    function applyLua(lua) {
        root.evalProc.command = ["hyprctl", "eval", String(lua)]
        root.evalProc.running = true
    }

    function applyMonitor(name, overrides) {
        const idx = root.monitors.findIndex(x => x.name === name)
        if (idx < 0) return
        root.applyLua(root.monitorRule(root.monitors[idx], overrides || {}) + "; " + root.preserveRules(idx))
    }

    // ---- Monitor geometry --------------------------------------------------

    function logicalSize(m) {
        const sw = (m.transform % 2 === 1) ? m.h : m.w
        const sh = (m.transform % 2 === 1) ? m.w : m.h
        return { w: Math.round(sw / m.scale), h: Math.round(sh / m.scale) }
    }

    function mirrorName(m) {
        if (!m || !m.mirrorOf || m.mirrorOf === "none") return ""
        const target = root.monitors.find(x => String(x.id) === String(m.mirrorOf))
        return target ? target.name : ""
    }

    function anchorFor(m) {
        if (!m) return null
        if (root.refMonitorName && m.name !== root.refMonitorName) {
            const ref = root.monitors.find(x => x.name === root.refMonitorName)
            if (ref) return ref
        }
        return root.monitors.find(x => x.name !== m.name) || null
    }

    function monitorRelation(idx) {
        const m = root.monitors[idx]
        if (!m) return null
        const s = root.logicalSize(m)
        const near = (p, q) => Math.abs(p - q) <= 2
        for (const o of root.monitors) {
            if (o.name === m.name) continue
            const os = root.logicalSize(o)
            if (near(m.y, o.y) && near(m.x + s.w, o.x)) return { dir: "left", name: o.name }
            if (near(m.y, o.y) && near(m.x, o.x + os.w)) return { dir: "right", name: o.name }
            if (near(m.x, o.x) && near(m.y + s.h, o.y)) return { dir: "top", name: o.name }
            if (near(m.x, o.x) && near(m.y, o.y + os.h)) return { dir: "bottom", name: o.name }
        }
        return null
    }

    // Collision-free position for monitor `idx` placed towards `dir`,
    // using `size` as its hypothetical logical size.
    function positionFor(idx, dir, size) {
        const m = root.monitors[idx]
        if (!m) return null
        const a = root.anchorFor(m)
        if (!a) return null
        let x = a.x
        let y = a.y
        for (const o of root.monitors) {
            if (o.name === m.name) continue
            const os = root.logicalSize(o)
            if (dir === "left") x = Math.min(x, o.x - size.w)
            else if (dir === "right") x = Math.max(x, o.x + os.w)
            else if (dir === "top") y = Math.min(y, o.y - size.h)
            else if (dir === "bottom") y = Math.max(y, o.y + os.h)
        }
        return { x: x, y: y }
    }

    property Process evalProc: Process {
        stdout: StdioCollector { onStreamFinished: root.refreshMonitors() }
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
