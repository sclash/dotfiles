pragma Singleton
import QtQuick
import Quickshell.Io
import "screenCastParse.js" as Parse

// ScreenCastService — owns the GNOME Network Displays daemon (cast targets) and
// the transient stream units it spawns. Launchers are pure views over this
// singleton; all Processes live here (SPECS.md §2.3 rule 3).
//
// The daemon exposes scan + start + stop only (org.gnome.NetworkDisplays.Manager,
// session bus). Extend/duplicate/only-remote are implemented around it:
//   • extend      → `hyprctl output create headless SCREENCAST` before StartStream;
//                   the share dialog then offers that output.
//   • duplicate   → no pre-action; the user picks the built-in panel.
//   • only-remote → duplicate; the local panel is turned off from session
//                   settings *after* the stream is up, never automatically.
//                   (The share picker lives on that panel — DPMS-off before the
//                   picker is answered would lock the user out.)
QtObject {
    id: root

    readonly property string extendOutput: "SCREENCAST"
    readonly property bool busy: daemonActiveProc.running || daemonStartProc.running
        || displaysProc.running || startProc.running || stopProc.running
        || extendCreateProc.running || extendRemoveProc.running || unitsProc.running

    // Public state -----------------------------------------------------------
    property bool available: true          // daemon reachable / package present
    property bool daemonRunning: false
    property bool scanning: false
    property var sinks: []                 // [{uuid, name, priority, state, protocol}]
    property string mode: "duplicate"      // duplicate | extend | only-remote
    property var active: null              // {uuid, name, protocol, unit, mode}
    property string sessionState: "idle"   // idle | connecting | streaming | error
    property bool localPanelOff: false
    property bool extendOutputCreated: false
    property string lastError: ""
    signal dataUpdated()

    // Internal ---------------------------------------------------------------
    property var pendingSink: null
    property string pendingMode: "duplicate"
    property int idleTicks: 0
    property string pollUnit: ""
    property bool dpmsTargetState: true
    property bool closePending: false
    property int scanTicks: 0
    property int displayRetries: 0

    function protocolLabel(p) { return Parse.protocolLabel(p) }
    function stateLabel(s) { return Parse.stateLabel(s) }
    function modeLabel(m) {
        if (m === "extend") return "Extend"
        if (m === "only-remote") return "Only remote"
        return "Duplicate"
    }
    function fail(message) {
        root.pollTimer.stop()
        root.pendingSink = null
        root.lastError = String(message || "Cast operation failed")
        root.sessionState = "error"
        root.dataUpdated()
    }
    // The stream ended on its own (unit failed/inactive): release the
    // resources we created but keep the error visible.
    function abortSession(message) {
        root.pollTimer.stop()
        if (root.extendOutputCreated) root.extendRemoveProc.running = true
        if (root.localPanelOff) root.setLocalPanel(true)
        root.active = null
        root.pendingSink = null
        root.idleTicks = 0
        root.sessionState = "error"
        root.lastError = String(message || "The stream ended")
        root.dataUpdated()
    }
    function clearError() {
        if (root.lastError !== "") { root.lastError = ""; root.dataUpdated() }
    }

    // Lifecycle --------------------------------------------------------------
    function open() {
        root.closePending = false
        root.scanTicks = 0
        root.displayRetries = 0
        root.scanTimer.restart()
        root.ensureDaemon()
    }

    function close() {
        // Keep the daemon alive while a stream is running; its list is needed
        // when the launcher reopens.
        if (root.active || root.sessionState === "connecting" || root.startProc.running) return
        root.pendingSink = null
        if (root.busy) { root.closePending = true; return }
        root.scanTimer.stop()
        root.retryTimer.stop()
        root.daemonStopProc.running = true
    }

    // A close requested while a Process was in flight: stop the daemon once it
    // settles. Without this, opening and immediately closing leaves P2P
    // discovery running forever.
    function maybeFinishClose() {
        if (!root.closePending || root.busy) return
        root.closePending = false
        root.scanTimer.stop()
        root.retryTimer.stop()
        root.daemonStopProc.running = true
    }

    function ensureDaemon() {
        if (root.daemonStartProc.running || root.daemonActiveProc.running) return
        root.daemonActiveProc.running = true
    }

    function refresh() {
        if (root.displaysProc.running) return
        if (!root.daemonRunning) { root.ensureDaemon(); return }
        root.scanning = true
        root.displaysProc.running = true
    }

    function rescan() { root.refresh() }

    // Connection -------------------------------------------------------------
    function connectSink(sink) {
        if (!sink || root.active || root.busy) return
        root.clearError()
        root.pendingSink = sink
        root.pendingMode = root.mode
        root.sessionState = "connecting"
        root.scanTimer.stop()
        root.dataUpdated()

        if (root.mode === "extend" && !root.extendOutputCreated) {
            root.extendCreateProc.running = true
            return
        }
        root.startStream(sink)
    }

    function startStream(sink) {
        if (!sink) { root.fail("No display selected"); return }
        root.pendingSink = sink
        root.startProc.command = [
            "busctl", "--user", "--timeout=8", "call",
            "org.gnome.NetworkDisplays.Manager",
            "/org/gnome/NetworkDisplays/Manager",
            "org.gnome.NetworkDisplays.Manager",
            "StartStream", "s", String(sink.uuid)
        ]
        root.startProc.running = true
    }

    function disconnect() {
        if (!root.active) return
        root.stopProc.command = ["systemctl", "--user", "stop", root.active.unit]
        root.stopProc.running = true
    }

    function cleanupAfterStop() {
        root.pollTimer.stop()
        if (root.extendOutputCreated) root.extendRemoveProc.running = true
        if (root.localPanelOff) root.setLocalPanel(true)
        root.active = null
        root.pendingSink = null
        root.sessionState = "idle"
        root.idleTicks = 0
        root.dataUpdated()
        Qt.callLater(() => root.maybeFinishClose())
    }

    // Session tracking -------------------------------------------------------
    function checkSession() {
        if (!root.active) { root.pollTimer.stop(); return }
        if (root.sessionProc.running) return
        root.pollUnit = root.active.unit
        root.sessionProc.command = ["systemctl", "--user", "is-active", root.active.unit]
        root.sessionProc.running = true
    }

    function handleSessionState(state) {
        if (!root.active) return
        if (root.pollUnit !== root.active.unit) return
        let changed = false
        if (state === "active" || state === "activating" || state === "reloading") {
            if (root.sessionState !== "streaming") { root.sessionState = "streaming"; changed = true }
            root.idleTicks = 0
        } else if (state === "failed") {
            root.abortSession("The stream failed — check the share dialog and the display")
            return
        } else if (state === "inactive" || state === "deactivating" || state === "") {
            root.idleTicks++
            if (root.idleTicks >= 4) {
                root.abortSession("The stream ended")
                return
            }
        } else if (root.sessionState === "streaming") {
            root.sessionState = "connecting"
            changed = true
        }
        if (changed) root.dataUpdated()
    }

    // Discovers a unit left running by a previous shell session, so reopening
    // the launcher still shows the active cast, then probes Hyprland for the
    // outputs it created (mode, headless output, panel DPMS state).
    function discoverActiveUnit() {
        if (root.active || root.startProc.running || root.stopProc.running) return
        root.unitsProc.running = true
    }

    // Local panel ------------------------------------------------------------
    function setLocalPanel(on) {
        const name = HyprService.refMonitorName
        if (!name) return
        root.dpmsTargetState = on
        root.localPanelOff = !on
        root.dpmsProc.command = ["hyprctl", "dispatch", "dpms", on ? "on" : "off", name]
        root.dpmsProc.running = true
    }

    // Post-connect output settings ------------------------------------------
    readonly property var castOutput: {
        if (!root.active) return null
        const name = root.active.mode === "extend" ? root.extendOutput : HyprService.refMonitorName
        return HyprService.monitors.find(m => m.name === name) || null
    }

    function applyOutput(key, value) {
        const monitor = root.castOutput
        if (!monitor) return
        const overrides = {}
        if (key === "mode") overrides.mode = String(value)
        else if (key === "scale") overrides.scale = Number(value)
        else if (key === "position") overrides.position = String(value)
        else return
        HyprService.applyMonitor(monitor.name, overrides)
    }

    // Processes --------------------------------------------------------------
    property Process daemonActiveProc: Process {
        command: ["systemctl", "--user", "is-active", "--quiet", "gnome-network-displays-daemon.service"]
        onExited: (code, status) => {
            if (code === 0) {
                root.daemonRunning = true
                root.available = true
                root.refresh()
            } else {
                root.daemonRunning = false
                root.daemonStartProc.running = true
            }
        }
    }

    property Process daemonStartProc: Process {
        command: ["systemctl", "--user", "start", "gnome-network-displays-daemon.service"]
        onExited: (code, status) => {
            if (code !== 0) {
                root.available = false
                root.fail("Network Displays daemon unavailable")
                return
            }
            root.daemonRunning = true
            root.available = true
            root.refresh()
            Qt.callLater(() => root.maybeFinishClose())
        }
        stderr: StdioCollector {
            onStreamFinished: {
                const t = String(this.text || "").trim()
                if (t) root.lastError = t.split("\n")[0]
            }
        }
    }

    property Process daemonStopProc: Process {
        command: ["systemctl", "--user", "stop", "gnome-network-displays-daemon.service"]
        onExited: (code, status) => {
            root.daemonRunning = false
            root.sinks = []
            root.dataUpdated()
        }
    }

    property Process displaysProc: Process {
        command: ["busctl", "--user", "--json=short", "get-property",
            "org.gnome.NetworkDisplays.Manager",
            "/org/gnome/NetworkDisplays/Manager",
            "org.gnome.NetworkDisplays.Manager", "Displays"]
        onExited: (code, status) => {
            root.scanning = false
            Qt.callLater(() => root.maybeFinishClose())
        }
        stdout: StdioCollector {
            onStreamFinished: {
                const text = String(this.text || "").trim()
                if (text === "") return
                root.sinks = Parse.parseDisplays(text)
                if (root.sinks.length > 0) root.scanTimer.stop()
                root.available = true
                root.displayRetries = 0
                // A successful reply proves the daemon is reachable, so drop a
                // stale "unavailable" error and return to the list. A session
                // error is only cleared once its stream is no longer active.
                if (root.active === null && root.sessionState === "error") {
                    root.sessionState = "idle"
                    root.lastError = ""
                }
                root.dataUpdated()
                root.discoverActiveUnit()
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                const t = String(this.text || "").trim()
                // Type=dbus makes the first call deterministic; a daemon that
                // crashed between is-active and get-property still races. Retry
                // briefly instead of declaring the whole feature unavailable.
                if (t !== "" && Parse.isTransientBusError(t) && root.displayRetries < 6) {
                    root.displayRetries++
                    root.retryTimer.restart()
                    return
                }
                root.available = false
                root.lastError = t ? t.split("\n")[0] : "Network Displays daemon unavailable"
                root.dataUpdated()
            }
        }
    }

    property Process unitsProc: Process {
        command: ["sh", "-c",
            "systemctl --user list-units --type=service --all --no-legend --plain 'gnome-network-displays-stream-*.service' 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (root.active) return
                const lines = String(this.text || "").trim().split("\n").filter(Boolean)
                for (const line of lines) {
                    const parts = line.trim().split(/\s+/)
                    if (parts.length < 3) continue
                    const unit = parts[0]
                    const state = parts[2]
                    if (state !== "active" && state !== "activating") continue
                    const uuid = unit.replace(/^gnome-network-displays-stream-/, "").replace(/\.service$/, "")
                    const sink = root.sinks.find(s => s.uuid === uuid)
                    root.active = {
                        uuid: uuid,
                        name: sink ? sink.name : "Display",
                        protocol: sink ? sink.protocol : 0,
                        unit: unit,
                        mode: "duplicate"
                    }
                    root.sessionState = "streaming"
                    root.pollTimer.restart()
                    root.hyprMonitorsProc.running = true
                    root.dataUpdated()
                    return
                }
            }
        }
        onExited: (code, status) => Qt.callLater(() => root.maybeFinishClose())
    }

    // Recovers the adopted session's mode from Hyprland: a SCREENCAST output
    // means extend; a DPMS-off built-in panel without it means only-remote.
    property Process hyprMonitorsProc: Process {
        command: ["hyprctl", "monitors", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (!root.active) return
                let monitors = []
                try { monitors = JSON.parse(String(this.text || "[]")) } catch (e) { monitors = [] }
                if (monitors.length === 0) return
                const builtin = monitors.find(m => /^(eDP|DSI)/.test(m.name)) || monitors[0]
                const extended = monitors.some(m => m.name === root.extendOutput)
                root.extendOutputCreated = extended
                root.localPanelOff = !!(builtin && builtin.dpmsStatus === false)
                if (extended) root.active.mode = "extend"
                else if (root.localPanelOff) root.active.mode = "only-remote"
                root.dataUpdated()
            }
        }
    }

    property Process extendCreateProc: Process {
        command: ["hyprctl", "output", "create", "headless", root.extendOutput]
        onExited: (code, status) => {
            if (code !== 0) {
                root.fail("Could not create the virtual output")
                return
            }
            root.extendOutputCreated = true
            if (root.pendingSink) root.startStream(root.pendingSink)
        }
        stderr: StdioCollector {
            onStreamFinished: {
                const t = String(this.text || "").trim()
                if (t) root.lastError = t.split("\n")[0]
            }
        }
    }

    property Process extendRemoveProc: Process {
        command: ["hyprctl", "output", "remove", root.extendOutput]
        onExited: (code, status) => {
            if (code === 0) {
                root.extendOutputCreated = false
            } else {
                root.extendOutputCreated = true
                root.lastError = "Could not remove the virtual output"
            }
            root.dataUpdated()
            Qt.callLater(() => root.maybeFinishClose())
        }
    }

    property Process startProc: Process {
        stdout: StdioCollector {
            onStreamFinished: {
                const text = String(this.text || "").trim()
                if (text === "") return
                const unit = Parse.parseUnitName(text)
                if (!unit) return
                const sink = root.pendingSink
                root.active = {
                    uuid: sink ? sink.uuid : "",
                    name: sink ? sink.name : "Display",
                    protocol: sink ? sink.protocol : 0,
                    unit: unit,
                    mode: root.pendingMode
                }
                root.pendingSink = null
                root.sessionState = "connecting"
                root.idleTicks = 0
                root.pollTimer.restart()
                root.dataUpdated()
            }
        }
        onExited: (code, status) => {
            if (code === 0) {
                if (root.active === null && root.lastError === "")
                    root.fail("The daemon did not return a stream unit")
                return
            }
            if (root.extendOutputCreated) root.extendRemoveProc.running = true
            root.fail(root.lastError || "The daemon refused the connection")
        }
        stderr: StdioCollector {
            onStreamFinished: {
                const t = String(this.text || "").trim()
                if (t) root.lastError = t.split("\n")[0]
            }
        }
    }

    property Process stopProc: Process {
        onExited: (code, status) => root.cleanupAfterStop()
    }

    property Process sessionProc: Process {
        stdout: StdioCollector {
            onStreamFinished: root.handleSessionState(String(this.text || "").trim())
        }
    }

    property Process dpmsProc: Process {
        onExited: (code, status) => {
            if (code !== 0) root.localPanelOff = !root.dpmsTargetState
            root.dataUpdated()
        }
    }

    property Timer pollTimer: Timer {
        interval: 1500
        repeat: true
        onTriggered: root.checkSession()
    }

    // Bounded auto-discovery: a fresh daemon can take a few seconds to browse
    // Avahi/Wi-Fi P2P, and a single read at open often sees an empty list.
    property Timer scanTimer: Timer {
        interval: 3000
        repeat: true
        onTriggered: {
            if (root.active || root.sessionState === "connecting") { root.scanTimer.stop(); return }
            root.scanTicks++
            if (root.scanTicks > 10) { root.scanTimer.stop(); return }
            root.refresh()
        }
    }

    // Fast bounded retry for "the daemon is not up yet" failures. The unit is
    // Type=dbus, so this should rarely fire; it covers a daemon crash between
    // `is-active` and `get-property`.
    property Timer retryTimer: Timer {
        interval: 250
        repeat: false
        onTriggered: {
            if (root.active || root.closePending) return
            if (!root.daemonRunning) root.ensureDaemon()
            else root.refresh()
        }
    }
}
