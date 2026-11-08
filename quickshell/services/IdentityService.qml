pragma Singleton
import QtQuick
import Quickshell.Io
import "identityParse.js" as Parse

// IdentityService — wraps the fprintd CLIs for the current user and the
// hyprlock fingerprint override file. Launchers are pure views over this
// singleton; all Processes live here (SPECS.md §2.3 rule 3).
//
// State-file contract (shared with hypr/hyprlock.conf and the NixOS test):
//   ~/.local/state/hyprlock-fingerprint.conf — `auth { fingerprint { … } }`
//   override read by hyprlock's last `source =` line; absent/unparseable
//   means enabled (the repo default). Seeded once per session so hyprlock
//   never logs a missing-source config error.
QtObject {
    id: root

    property bool fprintdAvailable: false
    property bool devicePresent: false
    property bool authEnabled: true
    property var enrolled: []              // [{ name, label }]
    property bool enrolling: false
    property string enrollFinger: ""
    property string enrollStage: ""        // raw fprintd enroll status
    readonly property string enrollMessage: Parse.enrollStageLabel(enrollStage)
    property int enrollPasses: 0
    property bool enrollDone: false
    property string lastError: ""
    signal dataUpdated()

    property bool _seeded: false
    property bool _listErrorActive: false
    property string _queuedFinger: ""

    // ---------- public API ----------

    function refresh() {
        root.probeProc.running = true
    }
    function setAuthEnabled(on) {
        root._writeState(on ? "true" : "false")
    }
    function enroll(finger) {
        if (root.enrolling || !root.fprintdAvailable) return
        root.enrolling = true
        root.enrollFinger = finger
        root.enrollPasses = 0
        root.enrollDone = false
        root.enrollStage = ""
        if (root.enrollProc.running) {
            // A cancelled process is still terminating; start as soon as it exits.
            root._queuedFinger = finger
            root.dataUpdated()
            return
        }
        root._startEnrollProc(finger)
        root.dataUpdated()
    }
    function _startEnrollProc(finger) {
        root.enrollProc.command = ["fprintd-enroll", "-f", finger]
        root.enrollProc.running = true
        root._startWatch.restart()
    }
    function cancelEnroll() {
        if (!root.enrolling) return
        root.enrollProc.running = false
        root.enrolling = false
        root.enrollDone = false
        root._queuedFinger = ""
        root._startWatch.stop()
        root.refresh()
    }
    function deleteFinger(finger) {
        if (root.enrolling || !root.fprintdAvailable) return
        root.deleteProc.environment = { FPRINT_FINGER: finger }
        root.deleteProc.running = true
    }

    // ---------- internals ----------

    function _writeState(value) {
        root.writeProc.environment = { FPRINT_ENABLED: value }
        root.writeProc.running = true
    }
    function _handleProbe(text) {
        const lines = String(text || "").split("\n")
        const bin = (lines.shift() || "").trim() === "BIN=1"
        const rest = lines.join("\n").trim()
        root.fprintdAvailable = bin
        if (!bin) {
            root.devicePresent = false
            root.enrolled = []
        }
        if (rest === "ABSENT" || rest === "") {
            root.authEnabled = true
            if (!root._seeded) {
                root._seeded = true
                root._writeState("true")   // seed once; writeProc re-probes
                return
            }
        } else {
            root.authEnabled = Parse.parseAuthEnabled(rest)
        }
        if (bin) root.listProc.running = true
        else root.dataUpdated()
    }
    function _handleEnrollLine(line) {
        const m = String(line).match(/^Enroll result: (.+)$/)
        if (m) {
            root.enrollStage = m[1]
            if (m[1] === "enroll-stage-passed") root.enrollPasses++
            root.dataUpdated()
            return
        }
        // Non-result chatter (e.g. "failed to claim device: …") — surface it.
        if (/failed|impossible/i.test(String(line))) { root.lastError = String(line).trim(); root._listErrorActive = false }
    }
    function _finishEnroll(code) {
        root._startWatch.stop()
        const wasQueued = root._queuedFinger
        root._queuedFinger = ""
        root.enrolling = false
        root.enrollDone = code === 0
        if (wasQueued !== "") {
            root.enroll(wasQueued)
            return
        }
        root.refresh()
    }

    // ---------- processes ----------

    property Process probeProc: Process {
        command: ["sh", "-c", 'if command -v fprintd-enroll >/dev/null 2>&1 && command -v fprintd-list >/dev/null 2>&1 && command -v fprintd-delete >/dev/null 2>&1; then echo BIN=1; else echo BIN=0; fi; if [ -f "$HOME/.local/state/hyprlock-fingerprint.conf" ]; then cat "$HOME/.local/state/hyprlock-fingerprint.conf"; else echo ABSENT; fi']
        stdout: StdioCollector {
            onStreamFinished: root._handleProbe(this.text)
        }
    }

    property Process listProc: Process {
        command: ["sh", "-c", "fprintd-list \"$(id -un)\" 2>&1"]
        stdout: StdioCollector {
            onStreamFinished: {
                const text = this.text
                const listErr = Parse.listError(text)
                if (listErr !== "") {
                    root.lastError = listErr
                    root._listErrorActive = true
                } else if (root._listErrorActive) {
                    root.lastError = ""
                    root._listErrorActive = false
                }
                root.devicePresent = listErr !== "nodevice" && listErr !== "daemon"
                root.enrolled = Parse.parseEnrolled(text).map(n => ({ name: n, label: Parse.fingerLabel(n) }))
                root.dataUpdated()
            }
        }
    }

    property Process enrollProc: Process {
        command: ["fprintd-enroll", "-f", "right-index-finger"]
        stdout: SplitParser {
            onRead: (line) => root._handleEnrollLine(line)
        }
        onExited: (exitCode, exitStatus) => root._finishEnroll(exitCode)
    }

    property Process deleteProc: Process {
        command: ["sh", "-c", "fprintd-delete \"$(id -un)\" -f \"$FPRINT_FINGER\" 2>&1"]
        stdout: StdioCollector {
            onStreamFinished: {
                const text = String(this.text || "").trim()
                if (text.indexOf("Failed to delete") !== -1) { root.lastError = text; root._listErrorActive = false }
                root.refresh()
            }
        }
    }

    property Process writeProc: Process {
        command: ["sh", "-c", "mkdir -p \"$HOME/.local/state\" && printf 'auth {\\n    fingerprint {\\n        enabled = %s\\n    }\\n}\\n' \"$FPRINT_ENABLED\" > \"$HOME/.local/state/hyprlock-fingerprint.conf\""]
        stdout: StdioCollector {
            onStreamFinished: root.probeProc.running = true
        }
    }

    // FailedToStart never emits `exited`; `running` still drops to false. If an
    // attempt is still flagged as running shortly after start, finish it.
    property Timer _startWatch: Timer {
        interval: 1200
        onTriggered: { if (root.enrolling && !root.enrollProc.running) root._finishEnroll(1) }
    }

    Component.onCompleted: root.refresh()
}
