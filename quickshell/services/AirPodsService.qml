pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "airPodsParse.js" as Parse
import "airPodsLifecycle.js" as Lifecycle

// Adapted from omarchy-pods Service.qml (MIT), commit f35dbc4.
//
// AirPodsService — reads the one-line status file librepods publishes
// ($XDG_STATE_HOME/librepods/status.json), sends librepods-ctl verbs and
// starts/stops the user service only while the AirPods are connected or the
// panel is open. Launchers and the bar badge are pure readers over this
// singleton; no view owns a process or a timer.
//
// The daemon removes the file when it stops, so an absent file is a stopped
// daemon. A line that cannot be parsed still proves it is running.
QtObject {
    id: root

    // ---------- daemon state ----------
    property bool daemonReachable: false
    property bool daemonStarting: false
    property bool daemonActive: false
    property string lifecycleError: ""

    // ---------- status ----------
    property bool connected: false
    property string deviceName: ""
    property string modelName: ""
    property string modelNumber: ""
    property bool isProSeries: false
    property bool isHeadset: false
    property bool supportsNoiseOff: true
    property bool supportsNoiseControl: true
    property bool supportsAdaptive: false
    property bool supportsConversationalAwareness: false
    property bool supportsOneBudANC: false
    property int noiseMode: Parse.NOISE_UNKNOWN
    property int adaptiveNoiseLevel: 0
    property bool oneBudANC: false
    property bool conversationalAwareness: false
    property int earDetectionBehavior: Parse.EAR_PAUSE_ONE_OUT
    property int lidState: Parse.LID_UNKNOWN
    property var leftPod: Parse.defaultPod()
    property var rightPod: Parse.defaultPod()
    property var caseBattery: ({ level: Parse.LEVEL_UNKNOWN, charging: false })
    property var headsetBattery: ({ level: Parse.LEVEL_UNKNOWN, charging: false })
    property string lastError: ""
    property string actionStatus: ""

    readonly property bool hasAirPods: root.connected
    // A headset reports one level for the whole device; earbuds and the case
    // each report their own, and any one of them is enough for the badge.
    readonly property bool hasBattery: root.isHeadset
        ? root.headsetBattery.level !== Parse.LEVEL_UNKNOWN
        : (root.leftPod.level !== Parse.LEVEL_UNKNOWN
            || root.rightPod.level !== Parse.LEVEL_UNKNOWN
            || root.caseBattery.level !== Parse.LEVEL_UNKNOWN)
    readonly property bool busy: root.ctlProcess.running

    // ---------- paths and tuning ----------
    readonly property string statePath: Quickshell.env("AIRPODS_STATE")
        || (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state")
            + "/librepods/status.json"
    readonly property string ctlPath: Quickshell.env("AIRPODS_CTL") || "librepods-ctl"
    // How long an optimistic value is held before the daemon's own state wins.
    readonly property int settleHoldMs: 4000
    readonly property int actionStatusMs: 2200
    // 8 s in production; the lifecycle smoke shortens it through this hook.
    readonly property int startTimeoutMs: {
        const ms = Number(Quickshell.env("AIRPODS_START_TIMEOUT_MS"))
        return ms > 0 ? ms : 8000
    }

    // ---------- lifecycle state ----------
    property bool panelOpen: false
    // A start that failed must not be retried by the 5 s Bluetooth poll; the
    // next panel open or wantDaemon false→true transition clears it.
    property bool startFailed: false
    readonly property bool wantDaemon: Lifecycle.shouldRun(
        BluetoothService.devices.some(d => d.connected && d.isAirPods),
        root.panelOpen, root.connected)
    readonly property bool lifecycleBusy: root.lifecycleProc.running
    property bool _lifecycleQueued: false
    property string _lifecycleAction: ""
    // A start that exited 0 but never wrote the status file may have left the
    // unit running (or restarting); stop it before any later start.
    property bool _stopAfterTimeout: false

    // ---------- ctl state ----------
    // Held over incoming reads until the daemon agrees, so a write already in
    // flight when the click landed cannot snap the control back.
    property string _pendingField: ""
    property var _pendingValue: null
    // Single slot: a verb sent while another is in flight replaces the queued
    // one rather than being dropped, which is what arrow-key repeat produces.
    property var _queued: null
    property string _activeVerb: ""
    // Last parse error only; a ctl error survives a good status line.
    property string _parseError: ""

    // ---------- status file ----------
    function refresh() {
        root.statusFile.reload()
    }

    // A line we cannot parse still proves the daemon is running and writing,
    // so daemonActive is set either way.
    function applyLine(raw) {
        const status = Parse.parseStatus(raw)
        root.daemonReachable = true
        root.daemonActive = true
        root.daemonStarting = false
        // A late status proves the start succeeded, so a start that timed out
        // earlier must not keep blocking the next restart.
        root.startFailed = false
        root._stopAfterTimeout = false
        root.startWatch.stop()
        if (status.ok) {
            root.lifecycleError = ""
            if (root.lastError === root._parseError) root.lastError = ""
            root._parseError = ""
        } else {
            root._parseError = status.lastError
            root.lastError = status.lastError
        }
        root.applyStatus(status)
        root.reconcile()
    }

    // The daemon removes the file when it stops. A missing file while a start
    // is still pending is expected, not evidence that the daemon died: leave
    // daemonStarting and the start watch alone or every refresh starts again.
    function stateGone() {
        const wasActive = root.daemonActive
        root.daemonReachable = false
        root.daemonActive = false
        if (wasActive) {
            root.daemonStarting = false
            root.startWatch.stop()
        }
        root.connected = false
        root.lastError = ""
        root._parseError = ""
        root.reconcile()
    }

    function applyStatus(status) {
        root.connected = status.connected
        root.deviceName = status.deviceName
        root.modelName = status.modelName
        root.modelNumber = status.modelNumber
        root.isProSeries = status.isProSeries
        root.isHeadset = status.isHeadset
        root.supportsNoiseOff = status.supportsNoiseOff
        root.supportsNoiseControl = status.supportsNoiseControl
        root.supportsAdaptive = status.supportsAdaptive
        root.supportsConversationalAwareness = status.supportsConversationalAwareness
        root.supportsOneBudANC = status.supportsOneBudANC
        root.leftPod = status.left
        root.rightPod = status.right
        root.caseBattery = status.caseBattery
        root.headsetBattery = status.headsetBattery
        root.lidState = status.lidState
        root.noiseMode = root._settle("noiseMode", status.noiseMode)
        root.adaptiveNoiseLevel = root._settle("adaptiveNoiseLevel", status.adaptiveNoiseLevel)
        root.oneBudANC = root._settle("oneBudANC", status.oneBudANC)
        root.conversationalAwareness = root._settle("conversationalAwareness", status.conversationalAwareness)
        root.earDetectionBehavior = root._settle("earDetectionBehavior", status.earDetectionBehavior)
    }

    function _settle(field, reported) {
        if (root._pendingField !== field) return reported
        if (reported === root._pendingValue) {
            root._clearPending()
            return reported
        }
        return root._pendingValue
    }

    function _clearPending() {
        root._pendingField = ""
        root._pendingValue = null
        root.settleTimer.stop()
    }

    // ---------- controls ----------
    function availableModes() {
        return Parse.availableModes(root.supportsNoiseControl, root.supportsNoiseOff, root.supportsAdaptive)
    }

    function setNoiseMode(mode) {
        if (root.availableModes().indexOf(mode) < 0) return
        root._send(Parse.noiseModeVerb(mode), "noiseMode", mode)
    }

    function cycleNoiseMode() {
        if (!root.hasAirPods) return
        const modes = root.availableModes()
        if (modes.length === 0) return
        const at = modes.indexOf(root.noiseMode)
        // An unknown current mode has no next one, so start at the head.
        root.setNoiseMode(at < 0 ? modes[0] : modes[(at + 1) % modes.length])
    }

    function setAdaptiveNoiseLevel(level) {
        const rounded = Math.round(Number(level))
        if (!isFinite(rounded)) return
        const clamped = Math.max(0, Math.min(100, rounded))
        root._send("adaptive:" + clamped, "adaptiveNoiseLevel", clamped)
    }

    function setConversationalAwareness(enabled) {
        root._send(enabled === true ? "ca:on" : "ca:off", "conversationalAwareness", enabled === true)
    }

    function setOneBudANC(enabled) {
        root._send(enabled === true ? "onebud:on" : "onebud:off", "oneBudANC", enabled === true)
    }

    function setEarDetectionBehavior(behavior) {
        const verb = Parse.earDetectionVerb(behavior)
        if (verb === "") return
        root._send(verb, "earDetectionBehavior", behavior)
    }

    function cycleEarDetection() {
        // The three behaviors are contiguous, 0..2.
        root.setEarDetectionBehavior((root.earDetectionBehavior + 1) % (Parse.EAR_DISABLED + 1))
    }

    // One verb at a time, optimistic in the meantime. A verb that arrives
    // while another runs replaces the queued one.
    function _send(verb, field, value) {
        if (verb === "") return
        root[field] = value
        if (root.ctlProcess.running) {
            root._queued = { verb: verb, field: field, value: value }
            root._pendingField = field
            root._pendingValue = value
            root.settleTimer.restart()
            return
        }
        root._beginSend(verb, field, value)
    }

    function _beginSend(verb, field, value) {
        root._activeVerb = verb
        root._pendingField = field
        root._pendingValue = value
        root.settleTimer.restart()
        root.ctlProcess.command = [root.ctlPath, verb]
        root.ctlProcess.running = true
    }

    function ctlExited(exitCode) {
        const err = String(root.ctlProcess.stderr.text || "").trim()
        const verb = root._activeVerb
        root._activeVerb = ""
        if (exitCode !== 0 || err !== "") {
            root.lastError = Parse.elideError(err || ("librepods-ctl " + verb + " failed"))
            // Drop the optimistic value and let the daemon's line win.
            root._clearPending()
            root.refresh()
        } else {
            root.lastError = ""
            root._parseError = ""
            root.actionStatus = verb
            root.actionStatusTimer.restart()
        }
        if (root._queued) {
            const next = root._queued
            root._queued = null
            root._beginSend(next.verb, next.field, next.value)
        }
    }

    // ---------- daemon lifecycle ----------
    function notePanelOpen() {
        // A user retry is allowed after a failed or timed-out start, and the
        // old error must not stay under "Connecting…".
        root.startFailed = false
        root.lifecycleError = ""
        root._stopAfterTimeout = false
        root.panelOpen = true
        root.reconcile()
        root.refresh()
    }

    function notePanelClosed() {
        root.panelOpen = false
        root.reconcile()
    }

    function reconcile() {
        if (Quickshell.env("AIRPODS_NO_LIFECYCLE") === "1") return
        if (root.daemonStarting) return
        if (root.lifecycleBusy) {
            root._lifecycleQueued = true
            return
        }
        // A start that never wrote the status file may have left the unit
        // running; stop it before deciding anything else.
        if (root._stopAfterTimeout) {
            root._stopAfterTimeout = false
            root._runLifecycle("stop")
            return
        }
        const action = Lifecycle.nextAction(root.wantDaemon, root.daemonActive)
        if (action === "none") return
        // A failed start waits for the user (panel open) or a real reconnect.
        if (action === "start" && root.startFailed) return
        root._runLifecycle(action)
    }

    function _runLifecycle(action) {
        root._lifecycleAction = action
        if (action === "start") {
            root.daemonStarting = true
            root.startWatch.restart()
        }
        root.lifecycleProc.command = ["systemctl", "--user", action, "librepods.service"]
        root.lifecycleProc.running = true
    }

    function lifecycleExited(exitCode) {
        const action = root._lifecycleAction
        root._lifecycleAction = ""
        if (exitCode !== 0) {
            if (action === "start") {
                root.daemonStarting = false
                root.startWatch.stop()
                root.startFailed = true
            }
            const err = String(root.lifecycleProc.stderr.text || "").trim()
            root.lifecycleError = Parse.elideError(err || ("systemctl could not " + (action || "apply") + " librepods"))
        }
        if (root._lifecycleQueued) {
            root._lifecycleQueued = false
            root.reconcile()
        }
    }

    onWantDaemonChanged: {
        if (root.wantDaemon) root.startFailed = false
    }

    // ---------- children ----------
    property FileView statusFile: FileView {
        path: root.statePath
        watchChanges: true
        printErrors: false
        // text() is stale inside the change signal, so both paths go through reload.
        onFileChanged: reload()
        onLoaded: root.applyLine(text())
        onLoadFailed: root.stateGone()
    }

    property Process ctlProcess: Process {
        command: []
        stderr: StdioCollector { waitForEnd: true }
        onExited: function (exitCode) { root.ctlExited(exitCode) }
        // FailedToStart never emits `exited`; `running` still drops. Without
        // this a missing librepods-ctl would no-op silently.
        onRunningChanged: {
            if (running || root._activeVerb === "") return
            root.lastError = "librepods-ctl could not run"
            root._activeVerb = ""
            root._queued = null
            root._clearPending()
            root.refresh()
        }
    }

    property Process lifecycleProc: Process {
        command: []
        stderr: StdioCollector { waitForEnd: true }
        onExited: function (exitCode) { root.lifecycleExited(exitCode) }
    }

    property Timer settleTimer: Timer {
        interval: root.settleHoldMs
        repeat: false
        // A verb that changed nothing leaves the file untouched, so no watch
        // fires to correct the display; re-read anyway.
        onTriggered: { root._clearPending(); root.refresh() }
    }

    property Timer actionStatusTimer: Timer {
        interval: root.actionStatusMs
        repeat: false
        onTriggered: root.actionStatus = ""
    }

    property Timer startWatch: Timer {
        interval: root.startTimeoutMs
        repeat: false
        onTriggered: {
            if (root.daemonActive) return
            root.daemonStarting = false
            root.startFailed = true
            root.lifecycleError = "librepods did not start — journalctl --user -u librepods"
            // The unit may be running (or crash-looping) without writing the
            // status file, so stop it; "only while connected or the panel is
            // open" must hold even after a failed watch.
            if (root.lifecycleBusy) {
                root._stopAfterTimeout = true
                root._lifecycleQueued = true
            } else {
                root._runLifecycle("stop")
            }
        }
    }

    property Connections bluetoothConn: Connections {
        target: BluetoothService
        function onDataUpdated() { root.reconcile() }
    }

    Component.onCompleted: {
        root.reconcile()
        root.refresh()
    }
}
