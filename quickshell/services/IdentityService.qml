pragma Singleton
import QtQuick
import Quickshell.Io
import "identityParse.js" as Parse
import "../theme"

// IdentityService — the current user's ways to authenticate: password
// (always on; changed through `identity-passwd`), face (Howdy over an IR
// camera) and fingerprint (fprintd CLIs). Launchers are pure views over this
// singleton; all Processes live here (SPECS.md §2.3 rule 3).
//
// State files (shared with hypr/hyprlock.conf and nixos/hardware-devices):
//   ~/.local/state/identity/choices — `fingerprint=on|off`, `face=on|off`;
//     written only here. A missing key = the hardware default (enabled when
//     the device is present).
//   ~/.local/state/hyprlock-auth.conf — derived from the choices and the
//     detected hardware on every refresh; sourced last by hyprlock. It
//     switches hyprlock's native fprintd unlock and its PAM service
//     (`hyprlock` = password, `hyprlock-face` = Howdy then password).
QtObject {
    id: root

    // ---------- fingerprint ----------
    property bool fprintdAvailable: false
    property bool devicePresent: false
    property var enrolled: []              // [{ name, label }]
    property bool enrolling: false
    property string enrollFinger: ""
    property string enrollStage: ""        // raw fprintd enroll status
    readonly property string enrollMessage: Parse.enrollStageLabel(enrollStage)
    property int enrollPasses: 0
    property bool enrollDone: false
    property string lastError: ""          // fingerprint errors
    readonly property string fingerprintState: Parse.methodState(devicePresent, choices.fingerprint)

    // ---------- face ----------
    property bool howdyAvailable: false
    property string irDevice: ""           // Howdy's device_path
    property bool irPresent: false
    property var faceModels: []            // [{ id, label, time }]
    property bool faceBusy: false          // a pkexec howdy add/remove is running
    property string faceAction: ""         // "add" | "remove" while busy
    property string faceMessage: ""        // last add/remove outcome
    property bool faceMessageIsError: false
    property bool faceNeedsEmitter: false  // Howdy only saw black frames
    readonly property string faceState: Parse.methodState(howdyAvailable && irPresent, choices.face)

    // ---------- password ----------
    property bool passwordAvailable: false // identity-passwd on PATH
    property bool passwordBusy: false
    property string passwordMessage: ""
    property bool passwordOk: false

    // ---------- shared ----------
    property var choices: ({ fingerprint: "", face: "" })
    readonly property var effective: Parse.effectiveAuth({
        fingerprintPresent: devicePresent, fingerprintChoice: choices.fingerprint,
        irPresent: howdyAvailable && irPresent, faceChoice: choices.face,
        faceModelCount: faceModels.length
    })
    // Lock-screen icons under the password box (hidden when unsupported).
    readonly property var lockIcons: Parse.lockIcons({
        fingerprintState: fingerprintState, faceState: faceState, faceModelCount: faceModels.length
    })
    signal dataUpdated()

    property bool _listErrorActive: false
    property string _queuedFinger: ""
    property string _writtenAuth: ""       // last hyprlock-auth.conf content written
    property string _pwPayload: ""         // cleared as soon as it is written

    // ---------- public API ----------

    function refresh() {
        root.probeProc.running = true
    }
    // method: "fingerprint" | "face". Only meaningful when the hardware exists.
    function setChoice(method, on) {
        const next = Object.assign({}, root.choices)
        next[method] = on ? "on" : "off"
        root.choices = next
        root.choicesProc.environment = { CONTENT: Parse.renderChoices(next) }
        root.choicesProc.running = true
    }

    // --- fingerprint ---
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

    // --- face (root actions through pkexec → polkit password prompt) ---
    function addFace(label) {
        if (root.faceBusy || !root.howdyAvailable || !root.irPresent) return
        const clean = String(label || "").replace(/,/g, "").trim().slice(0, 24)
        root._startFace("add", ["add", clean !== "" ? clean : "Face " + (root.faceModels.length + 1)])
    }
    function removeFace(id) {
        if (root.faceBusy || !root.howdyAvailable) return
        root._startFace("remove", ["remove", String(id)])
    }
    function _startFace(action, args) {
        root.faceBusy = true
        root.faceAction = action
        root.faceMessage = action === "add" ? "Look straight into the camera…" : "Removing…"
        root.faceMessageIsError = false
        root.faceNeedsEmitter = false
        root.faceProc.command = ["sh", "-c", 'exec pkexec howdy -U "$(id -un)" -y "$@" 2>&1', "howdy"].concat(args)
        root.faceProc.running = true
        root.dataUpdated()
    }

    // --- password ---
    function changePassword(current, next) {
        if (root.passwordBusy || !root.passwordAvailable) return
        root.passwordBusy = true
        root.passwordOk = false
        root.passwordMessage = "Changing password…"
        root._pwPayload = current + "\n" + next + "\n"
        root.passwdProc.running = true
        root.dataUpdated()
    }
    function clearPasswordMessage() {
        if (root.passwordBusy) return
        root.passwordMessage = ""
        root.passwordOk = false
    }

    // ---------- internals ----------

    function _sections(text) {
        // "KEY=VAL" header lines, then "@@NAME" sections with raw bodies.
        const out = { head: {}, body: {} }
        const parts = String(text || "").split(/^@@/m)
        for (const line of parts.shift().split("\n")) {
            const m = line.match(/^(\w+)=(.*)$/)
            if (m) out.head[m[1]] = m[2].trim()
        }
        for (const p of parts) {
            const nl = p.indexOf("\n")
            out.body[p.slice(0, nl).trim()] = p.slice(nl + 1)
        }
        return out
    }
    function _handleProbe(text) {
        const s = root._sections(text)
        root.fprintdAvailable = s.head.FPRINT === "1"
        root.howdyAvailable = s.head.HOWDY === "1" && s.head.PKEXEC === "1"
        root.passwordAvailable = s.head.PASSWD === "1"
        root.choices = Parse.parseChoices(s.body.CHOICES)
        root.irDevice = root.howdyAvailable ? Parse.parseHowdyDevicePath(s.body.HOWDYCONF) : ""
        if (!root.fprintdAvailable) {
            root.devicePresent = false
            root.enrolled = []
        }
        root.faceProbe.environment = { FACE_DEVICE: root.irDevice }
        root.faceProbe.running = true
    }
    function _handleFaceProbe(text) {
        const s = root._sections(text)
        root.irPresent = root.howdyAvailable && s.head.IR === "1"
        root.faceModels = Parse.parseHowdyModels(s.body.MODELS)
        if (root.fprintdAvailable) root.listProc.running = true
        else root._finishRefresh()
    }
    function _finishRefresh() {
        const hex = c => String(c).replace("#", "")
        const text = Parse.renderHyprlockAuth(root.effective, root.lockIcons, {
            glyphs: { fingerprint: Icons.fingerprint, face: Icons.face },
            colors: { selected: hex(Theme.fgBright), enabled: hex(Theme.fg), disabled: hex(Theme.fgDim), hint: hex(Theme.fgMuted) },
            font: Theme.fontFamily
        })
        if (text !== root._writtenAuth) {
            root._writtenAuth = text
            root.authProc.environment = { CONTENT: text }
            root.authProc.running = true
        }
        root.dataUpdated()
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
    function _finishFace(code, text) {
        const msg = Parse.howdyMessage(text)
        root.faceBusy = false
        root.faceNeedsEmitter = msg.needsEmitter
        if (code === 0) {
            root.faceMessage = root.faceAction === "add" ? "Face model added" : "Face model removed"
            root.faceMessageIsError = false
        } else if (Parse.pkexecMessage(code, text) !== "") {
            // pkexec never ran howdy: no agent, dismissed or not allowed.
            root.faceMessage = Parse.pkexecMessage(code, text)
            root.faceMessageIsError = true
        } else {
            root.faceMessage = msg.text !== "" ? msg.text : "howdy " + root.faceAction + " failed (" + code + ")"
            root.faceMessageIsError = true
        }
        root.faceAction = ""
        root.refresh()
    }

    // ---------- processes ----------

    property Process probeProc: Process {
        command: ["sh", "-c", 'has() { command -v "$1" >/dev/null 2>&1 && echo 1 || echo 0; }; '
            + 'fp=1; for c in fprintd-enroll fprintd-list fprintd-delete; do command -v "$c" >/dev/null 2>&1 || fp=0; done; '
            + 'echo "FPRINT=$fp"; echo "HOWDY=$(has howdy)"; echo "PKEXEC=$(has pkexec)"; echo "PASSWD=$(has identity-passwd)"; '
            + 'echo @@CHOICES; cat "$HOME/.local/state/identity/choices" 2>/dev/null || echo ABSENT; '
            + 'echo @@HOWDYCONF; cat /etc/howdy/config.ini 2>/dev/null || echo ABSENT']
        stdout: StdioCollector {
            onStreamFinished: root._handleProbe(this.text)
        }
    }

    // The IR camera counts as present when Howdy's device_path exists. Face
    // models are world-readable JSON written by `howdy add` (Howdy 3.0.0).
    property Process faceProbe: Process {
        command: ["sh", "-c", 'if [ -n "$FACE_DEVICE" ] && [ -e "$FACE_DEVICE" ]; then echo IR=1; else echo IR=0; fi; '
            + 'echo @@MODELS; cat "/var/lib/howdy/models/$(id -un).dat" 2>/dev/null || echo ABSENT']
        stdout: StdioCollector {
            onStreamFinished: root._handleFaceProbe(this.text)
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
                root._finishRefresh()
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

    // Output and exit can arrive in either order; finish once both are in.
    property Process faceProc: Process {
        property string output: ""
        property bool gotOutput: false
        property int code: -1
        function settle() {
            if (!gotOutput || code < 0) return
            const c = code, t = output
            gotOutput = false; code = -1; output = ""
            root._finishFace(c, t)
        }
        stdout: StdioCollector {
            onStreamFinished: { root.faceProc.output = this.text; root.faceProc.gotOutput = true; root.faceProc.settle() }
        }
        onExited: (exitCode, exitStatus) => { root.faceProc.code = exitCode; root.faceProc.settle() }
    }

    // Passwords go to identity-passwd's stdin only (never argv/env) and the
    // payload is dropped as soon as it has been written.
    property Process passwdProc: Process {
        command: ["identity-passwd"]
        stdinEnabled: true
        onStarted: {
            root.passwdProc.write(root._pwPayload)
            root._pwPayload = ""
            root.passwdProc.stdinEnabled = false
        }
        stdout: StdioCollector {
            onStreamFinished: {
                const r = Parse.passwdResult(this.text)
                root.passwordOk = r.ok
                root.passwordMessage = r.message
                root.passwordBusy = false
                root.dataUpdated()
            }
        }
        onExited: (exitCode, exitStatus) => {
            root._pwPayload = ""
            root.passwdProc.stdinEnabled = true   // ready for the next attempt
        }
    }

    property Process choicesProc: Process {
        command: ["sh", "-c", 'd="$HOME/.local/state/identity"; mkdir -p "$d" && printf "%s" "$CONTENT" > "$d/choices.tmp" && mv "$d/choices.tmp" "$d/choices"']
        onExited: (exitCode, exitStatus) => root.refresh()
    }

    property Process authProc: Process {
        command: ["sh", "-c", 'd="$HOME/.local/state"; mkdir -p "$d" && printf "%s" "$CONTENT" > "$d/hyprlock-auth.conf.tmp" && mv "$d/hyprlock-auth.conf.tmp" "$d/hyprlock-auth.conf"']
        onExited: (exitCode, exitStatus) => { if (exitCode !== 0) root._writtenAuth = "" }
    }

    // FailedToStart never emits `exited`; `running` still drops to false. If an
    // attempt is still flagged as running shortly after start, finish it.
    property Timer _startWatch: Timer {
        interval: 1200
        onTriggered: { if (root.enrolling && !root.enrollProc.running) root._finishEnroll(1) }
    }

    Component.onCompleted: root.refresh()
}
