pragma Singleton
import QtQuick
import Quickshell.Io

// Per-output brightness and color-temperature backends. Owns probing and
// writes only; the settings panel never spawns a process.
//
// Brightness precedence: kernel backlight -> DDC/CI -> gamma daemon.
// Color temperature always comes from the gamma daemon.
//
// Note: wl-gammarelay-rs registers the well-known bus name `rs.wl-gammarelay`
// (hyphen) but exposes its interface as `rs.wl.gammarelay` (dot).
QtObject {
    id: root

    property var hardware: ({})   // name -> descriptor (see emptyDescriptor)
    property bool probing: false
    property string error: ""

    // Probe bookkeeping
    property var _names: []
    property var _stage: ({})
    property var _lastMonitors: []
    property string _cacheKey: ""
    property int _gen: 0
    property int _probeGen: 0
    property bool _probePending: false
    property bool _probeForce: false

    // Per-backend probe queues
    property var _gammaQueue: []
    property var _ddcQueue: []
    property var _ddcMap: ({})

    // Writes — one Process per backend, pending values deduplicated per output.
    property var _pending: ({})   // "name|field" -> latest value
    property var _busy: ({ backlight: false, ddc: false, gamma: false })

    readonly property string gammaBus: "rs.wl-gammarelay"
    readonly property string gammaIface: "rs.wl.gammarelay"

    // ---------- public API ----------

    function emptyDescriptor() {
        return {
            brightness: {
                available: false, backend: "", value: 0,
                min: 1, max: 100, nativeMax: 100,
                device: "", display: "", path: ""
            },
            temperature: {
                available: false, value: 6500,
                min: 1000, max: 10000, path: ""
            },
            error: ""
        }
    }

    function hardwareFor(name) {
        const d = root.hardware[name]
        return d ? d : root.emptyDescriptor()
    }

    function invalidate() {
        root.hardware = ({})
        root._stage = ({})
        root._cacheKey = ""
        root._gen += 1
        // A probe may still be running: let it notice the stale generation and
        // re-probe, so we never run two probe chains at once.
        if (root.probing) root._probePending = true
    }

    function probe(monitors, force) {
        if (monitors && monitors.length > 0) root._lastMonitors = monitors
        const mons = root._lastMonitors || []
        if (mons.length === 0) return

        if (root.probing) {
            root._probePending = true
            root._probeForce = root._probeForce || !!force
            return
        }

        const names = mons.map(m => m.name).sort()
        const key = names.join(",")
        if (!force && key === root._cacheKey && Object.keys(root.hardware).length > 0) return

        root._cacheKey = key
        root._probePending = false
        root._probeForce = false
        root._gen += 1
        root._probeGen = root._gen
        root._names = names
        root._gammaQueue = []
        root._ddcQueue = []
        root._ddcMap = ({})
        root.error = ""
        root.probing = true

        const stage = ({})
        for (const n of names) stage[n] = root.emptyDescriptor()
        root._stage = stage

        root.backlightProbe.running = true
    }

    function setBrightness(name, percent) {
        const desc = root.hardwareFor(name)
        const b = desc.brightness
        if (!b.available) return
        const value = Math.round(root._clamp(percent, b.min, b.max))
        const next = root._copy(desc)
        next.brightness.value = value
        root._commit(name, next)
        root._queueWrite(name, "brightness", value)
    }

    function setTemperature(name, kelvin) {
        const desc = root.hardwareFor(name)
        const t = desc.temperature
        if (!t.available) return
        const value = Math.round(root._clamp(kelvin, t.min, t.max))
        const next = root._copy(desc)
        next.temperature.value = value
        root._commit(name, next)
        root._queueWrite(name, "temperature", value)
    }

    // ---------- helpers ----------

    function _clamp(v, lo, hi) {
        return Math.max(lo, Math.min(hi, v))
    }
    function _percent(cur, max) {
        if (!(max > 0)) return 0
        return Math.round(root._clamp(cur / max, 0, 1) * 100)
    }
    function _copy(desc) {
        return {
            brightness: Object.assign({}, desc.brightness),
            temperature: Object.assign({}, desc.temperature),
            error: desc.error || ""
        }
    }
    function _stagePut(name, desc) {
        const next = Object.assign({}, root._stage)
        next[name] = desc
        root._stage = next
    }
    function _commit(name, desc) {
        const next = Object.assign({}, root.hardware)
        next[name] = desc
        root.hardware = next
    }
    function _current() {
        return root._probeGen === root._gen
    }
    function _abandon() {
        root.probing = false
        if (root._probePending) {
            const force = root._probeForce
            root._probePending = false
            root._probeForce = false
            Qt.callLater(() => root.probe(root._lastMonitors, force))
        }
    }
    function _finishProbe() {
        if (!root._current()) { root._abandon(); return }
        root.hardware = root._stage
        root.probing = false
        if (root._probePending) {
            const force = root._probeForce
            root._probePending = false
            root._probeForce = false
            Qt.callLater(() => root.probe(root._lastMonitors, force))
        }
    }

    // body of a get-property reply line, e.g. "q 6500" / "d 0.75"
    function _valueOf(text, sigil) {
        const lines = String(text || "").split("\n")
        const re = new RegExp("^" + sigil + "\\s+(-?[0-9]*\\.?[0-9]+)")
        for (const l of lines) {
            const m = l.trim().match(re)
            if (m) return parseFloat(m[1])
        }
        return NaN
    }

    // ---------- probes ----------

    property Process backlightProbe: Process {
        command: ["sh", "-c",
            "for d in /sys/class/backlight/*; do " +
            "[ -d \"$d\" ] || continue; " +
            "dev=$(basename \"$d\"); " +
            "target=$(readlink -f \"$d/device\" 2>/dev/null); " +
            "conn=$(basename \"$target\" 2>/dev/null); " +
            "cur=$(cat \"$d/brightness\" 2>/dev/null); " +
            "max=$(cat \"$d/max_brightness\" 2>/dev/null); " +
            "typ=$(cat \"$d/type\" 2>/dev/null); " +
            "printf '%s|%s|%s|%s|%s\\n' \"$dev\" \"$conn\" \"$cur\" \"$max\" \"$typ\"; " +
            "done"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (!root._current()) { root._abandon(); return }
                root._applyBacklight(this.text)
                root.gammaTreeProbe.running = true
            }
        }
    }

    function _applyBacklight(text) {
        // name -> { rank, device, value }
        const best = ({})
        const lines = String(text || "").trim().split("\n").filter(Boolean)
        for (const line of lines) {
            const p = line.split("|")
            if (p.length < 5) continue
            const device = p[0]
            const conn = p[1] || ""
            const cur = Number(p[2])
            const max = Number(p[3])
            const type = p[4] || ""
            if (!(max > 0)) continue
            for (const name of root._names) {
                if (conn !== name && !conn.endsWith("-" + name)) continue
                const rank = type === "firmware" ? 0 : (type === "platform" ? 1 : 2)
                const prev = best[name]
                if (prev && prev.rank <= rank) continue
                best[name] = { rank: rank, device: device, value: root._percent(cur, max) }
            }
        }
        for (const name of Object.keys(best)) {
            const hit = best[name]
            const desc = root._stage[name] || root.emptyDescriptor()
            desc.brightness = {
                available: true,
                backend: "backlight",
                value: Math.max(1, hit.value),
                min: 1,
                max: 100,
                nativeMax: 100,
                device: hit.device,
                display: "",
                path: ""
            }
            root._stagePut(name, desc)
        }
    }

    property Process gammaTreeProbe: Process {
        command: ["busctl", "--user", "tree", root.gammaBus]
        stdout: StdioCollector {
            onStreamFinished: {
                if (!root._current()) { root._abandon(); return }
                root._parseGammaTree(this.text)
            }
        }
    }

    function _parseGammaTree(text) {
        const leaves = ({})
        const re = /\/outputs\/([A-Za-z0-9_]+)/g
        let m
        while ((m = re.exec(String(text || ""))) !== null) leaves[m[1]] = true

        const queue = []
        for (const name of root._names) {
            const leaf = name.replace(/[^A-Za-z0-9]/g, "_")
            if (leaves[leaf]) queue.push({ name: name, path: "/outputs/" + leaf })
        }
        root._gammaQueue = queue
        root._readNextGamma()
    }

    function _readNextGamma() {
        if (root._gammaQueue.length === 0) { root._startDdc(); return }
        const item = root._gammaQueue[0]
        const prefix = "busctl --user get-property " + root.gammaBus + " '" + item.path + "' " + root.gammaIface
        root.gammaReadProbe.command = ["sh", "-c",
            prefix + " Temperature 2>/dev/null; " +
            prefix + " Brightness 2>/dev/null"]
        root.gammaReadProbe.running = true
    }

    property Process gammaReadProbe: Process {
        stdout: StdioCollector {
            onStreamFinished: {
                if (!root._current()) { root._abandon(); return }
                const item = root._gammaQueue.shift()
                if (item) root._applyGamma(item, this.text)
                root._readNextGamma()
            }
        }
    }

    function _applyGamma(item, text) {
        const temp = root._valueOf(text, "q")
        const bright = root._valueOf(text, "d")
        const desc = root._stage[item.name] || root.emptyDescriptor()
        if (!isNaN(temp)) {
            desc.temperature = {
                available: true,
                value: Math.round(root._clamp(temp, 1000, 10000)),
                min: 1000,
                max: 10000,
                path: item.path
            }
        }
        if (!isNaN(bright) && !desc.brightness.available) {
            desc.brightness = {
                available: true,
                backend: "gamma",
                value: Math.max(1, Math.round(root._clamp(bright, 0, 1) * 100)),
                min: 1,
                max: 100,
                nativeMax: 100,
                device: "",
                display: "",
                path: item.path
            }
        }
        root._stagePut(item.name, desc)
    }

    function _startDdc() {
        if (root._ddcQueue.length > 0) { root._readNextDdc(); return }
        root.ddcDetectProbe.running = true
    }

    property Process ddcDetectProbe: Process {
        command: ["sh", "-c", "ddcutil detect 2>/dev/null || true"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (!root._current()) { root._abandon(); return }
                root._parseDdcDetect(this.text)
                root._readNextDdc()
            }
        }
    }

    function _parseDdcDetect(text) {
        const map = ({})
        let display = ""
        const lines = String(text || "").split("\n")
        for (const line of lines) {
            const dm = line.match(/^\s*Display\s+(\d+)\s*$/)
            if (dm) { display = dm[1]; continue }
            if (!display) continue
            const cm = line.match(/DRM[\s_]connector:\s*(\S+)/i)
            if (!cm) continue
            const conn = cm[1].replace(/^card\d+-/, "")
            for (const name of root._names) {
                if (name === conn && map[name] === undefined) map[name] = display
            }
        }
        root._ddcMap = map
        const queue = []
        for (const name of Object.keys(map)) queue.push({ name: name, display: map[name] })
        root._ddcQueue = queue
    }

    function _readNextDdc() {
        if (root._ddcQueue.length === 0) { root._finishProbe(); return }
        const item = root._ddcQueue[0]
        root.ddcVcpProbe.command = ["sh", "-c",
            "ddcutil --display " + item.display + " getvcp 10 --terse 2>/dev/null || true"]
        root.ddcVcpProbe.running = true
    }

    property Process ddcVcpProbe: Process {
        stdout: StdioCollector {
            onStreamFinished: {
                if (!root._current()) { root._abandon(); return }
                const item = root._ddcQueue.shift()
                if (item) root._applyDdc(item, this.text)
                root._readNextDdc()
            }
        }
    }

    function _applyDdc(item, text) {
        const m = String(text || "").match(/VCP\s+10\s+C\s+(\d+)\s+(\d+)/)
        if (!m) return
        const cur = Number(m[1])
        const max = Number(m[2])
        if (!(max > 0)) return
        const desc = root._stage[item.name] || root.emptyDescriptor()
        // Kernel backlight wins over DDC; gamma is only a fallback.
        if (desc.brightness.available && desc.brightness.backend === "backlight") return
        desc.brightness = {
            available: true,
            backend: "ddc",
            value: Math.max(1, root._percent(cur, max)),
            min: 1,
            max: 100,
            nativeMax: max,
            device: "",
            display: String(item.display),
            path: ""
        }
        root._stagePut(item.name, desc)
    }

    // ---------- writes ----------

    function _queueWrite(name, field, value) {
        root._pending[name + "|" + field] = value
        root.writeTimer.restart()
    }

    property Timer writeTimer: Timer {
        interval: 120
        onTriggered: root._flushWrites()
    }

    function _flushWrites() {
        const keys = Object.keys(root._pending)
        for (const key of keys) {
            const sep = key.lastIndexOf("|")
            const name = key.slice(0, sep)
            const field = key.slice(sep + 1)
            const value = root._pending[key]
            const desc = root.hardware[name]
            if (!desc) { delete root._pending[key]; continue }

            const backend = (field === "temperature") ? "gamma" : desc.brightness.backend
            if (!backend) { delete root._pending[key]; continue }
            if (root._busy[backend]) continue

            let cmd = null
            if (field === "temperature") {
                const t = desc.temperature
                if (!t.available || !t.path) { delete root._pending[key]; continue }
                cmd = ["busctl", "--user", "set-property", root.gammaBus,
                    t.path, root.gammaIface, "Temperature", "q", String(value)]
            } else {
                const b = desc.brightness
                if (!b.available) { delete root._pending[key]; continue }
                if (b.backend === "backlight") {
                    if (!b.device) { delete root._pending[key]; continue }
                    cmd = ["sh", "-c", "brightnessctl -d " + b.device + " set " + value + "% 2>/dev/null || true"]
                } else if (b.backend === "ddc") {
                    if (!b.display) { delete root._pending[key]; continue }
                    const raw = Math.round(value / 100 * (b.nativeMax || 100))
                    cmd = ["sh", "-c", "ddcutil --display " + b.display + " setvcp 10 " + raw + " 2>/dev/null || true"]
                } else if (b.backend === "gamma") {
                    if (!b.path) { delete root._pending[key]; continue }
                    cmd = ["busctl", "--user", "set-property", root.gammaBus,
                        b.path, root.gammaIface, "Brightness", "d", String(value / 100)]
                }
            }
            delete root._pending[key]
            if (!cmd) continue

            root._busy[backend] = true
            if (backend === "backlight") {
                root.backlightWrite.command = cmd
                root.backlightWrite.running = true
            } else if (backend === "ddc") {
                root.ddcWrite.command = cmd
                root.ddcWrite.running = true
            } else {
                root.gammaWrite.command = cmd
                root.gammaWrite.running = true
            }
        }
    }

    function _writeDone(backend) {
        root._busy[backend] = false
        root._flushWrites()
    }

    property Process backlightWrite: Process {
        stdout: StdioCollector { onStreamFinished: root._writeDone("backlight") }
    }
    property Process ddcWrite: Process {
        stdout: StdioCollector { onStreamFinished: root._writeDone("ddc") }
    }
    property Process gammaWrite: Process {
        stdout: StdioCollector { onStreamFinished: root._writeDone("gamma") }
    }
}
