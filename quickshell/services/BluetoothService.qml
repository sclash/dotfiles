pragma Singleton
import QtQuick
import Quickshell.Io

QtObject {
    id: root
    property bool available: true
    property bool powered: false
    property bool scanning: false
    property int connectedCount: 0
    property string controllerAlias: ""
    property string controllerAddress: ""
    property var devices: []
    property var nearby: []
    property var seenAddrs: ({})
    property string lastError: ""
    property bool pendingScan: false
    property string pairingAddress: ""
    property string pairAddress: ""
    property string pairAlias: ""
    signal dataUpdated()

    function stripAnsi(txt) { return String(txt || "").replace(/\x1b\[[0-9;]*m/g, "") }
    function processText(proc) {
        if (!proc || !proc.stdout || proc.stdout.text === undefined || proc.stdout.text === null) return ""
        return root.stripAnsi(proc.stdout.text).trim()
    }
    function reportError(txt) {
        const t = root.stripAnsi(txt).trim()
        if (!t) return
        const line = t.split("\n").map(l => l.trim()).filter(Boolean)[0] || t
        if (line) { root.lastError = line; root.dataUpdated() }
    }
    function findFailure(raw) {
        const lines = String(raw || "").split("\n").map(l => l.trim()).filter(Boolean)
        return lines.find(l => /failed|error|not available|authentication|cancel|denied|blocked|timed out|timeout|no agent|invalid/i.test(l)) || ""
    }
    function finishAction(proc) {
        const failure = root.findFailure(root.processText(proc))
        if (failure) root.reportError(failure)
        else { root.lastError = "" }
        root.dataUpdated()
        root.pollProc.running = true
    }

    function finishPower(proc, exitCode, fallback) {
        const raw = root.processText(proc)
        const failure = root.findFailure(raw)
        if (exitCode !== 0 || failure) root.reportError(failure || raw || fallback)
        else root.lastError = ""
        root.pollProc.running = true
    }

    function disconnect(address) { root.lastError = ""; root.btDiscProc.command = ["bluetoothctl", "disconnect", address]; root.btDiscProc.running = true }
    function connect(address) { root.lastError = ""; root.btConnProc.command = ["bluetoothctl", "connect", address]; root.btConnProc.running = true }
    function forget(address) { root.lastError = ""; root.btRemoveProc.command = ["bluetoothctl", "remove", address]; root.btRemoveProc.running = true }
    function trust(address) { root.lastError = ""; root.btTrustProc.command = ["bluetoothctl", "trust", address]; root.btTrustProc.running = true }
    function togglePower() {
        root.lastError = ""
        if (root.powered) { root.stopScan(); root.btPowerOff.running = true }
        else root.btPowerOn.running = true
    }

    // Pairing is resolved at click time: the address shown in the list may be
    // a stale BLE random address (they rotate) while audio devices such as
    // AirPods must be paired over classic BR/EDR with their public address.
    function pairAndConnect(address, alias) {
        if (!address) return
        root.lastError = ""
        root.pairingAddress = address
        root.pairAddress = address
        root.pairAlias = alias || ""
        root.btInfoProc.command = ["bluetoothctl", "info", address]
        root.btInfoProc.running = true
    }
    function runPair(address) {
        if (!address) { root.pairingAddress = ""; return }
        root.pairAddress = address
        root.btPairProc.command = ["sh", "-c",
            "bluetoothctl --agent NoInputNoOutput pair \"$1\"; " +
            "bluetoothctl trust \"$1\" >/dev/null 2>&1; " +
            "bluetoothctl --agent NoInputNoOutput connect \"$1\"",
            "sh", address]
        root.btPairProc.running = true
    }

    function startScan() {
        // Scanning must never change the power state — if the adapter is off,
        // stay off and let the UI surface the hint (power is user-controlled).
        if (!root.powered) { root.scanning = false; return }
        if (root.btScanOnProc.running) {
            // A scan process is still winding down: restart it once it exits.
            root.pendingScan = true
            root.btScanOnProc.running = false
            root.scanTimer.running = false
            return
        }
        root.nearby = []
        root.seenAddrs = {}
        root.beginScan()
    }
    function beginScan() {
        if (!root.powered) { root.scanning = false; return }
        root.seenAddrs = {}
        root.scanning = true
        root.btPairableProc.running = true
        root.btScanOnProc.running = true
        root.scanTimer.restart()
    }
    function stopScan() {
        root.scanTimer.running = false
        if (!root.scanning) return
        root.scanning = false
        root.btScanOnProc.running = false
        root.btScanOffProc.running = true
        // Names resolve into BlueZ's cache during discovery. Merge that cache
        // into the list instead of replacing it: BLE devices drop out of the
        // cache as soon as they stop advertising, which is what made entries
        // disappear seconds after a scan ended.
        root.btScanListProc.running = true
    }

    // bluetoothctl hardcodes ANSI colour codes on [NEW]/[CHG] event lines even
    // when stdout is piped, so raw lines look like "\x1b[0;92mNEW\x1b[0m Device …"
    // and never match a literal "[NEW]" — strip the escapes before parsing.
    function sanitizeLine(line) { return root.stripAnsi(line).trim() }
    function isPlaceholderAlias(alias, addr) {
        if (!alias || alias === "Unknown device") return true
        return alias.replace(/-/g, ":").toUpperCase() === addr
    }
    function upsertNearby(address, alias, rssi) {
        const addr = String(address).toUpperCase()
        const known = root.nearby
        const idx = known.findIndex(d => d.address === addr)
        if (idx === -1) {
            root.nearby = known.concat([{
                address: addr,
                alias: (alias && !root.isPlaceholderAlias(alias, addr)) ? alias : "Unknown device",
                rssi: typeof rssi === "number" ? rssi : 0
            }])
            return
        }
        const cur = known[idx]
        const nextAlias = (!alias || root.isPlaceholderAlias(alias, addr)) ? cur.alias : alias
        const nextRssi = typeof rssi === "number" ? rssi : cur.rssi
        if (nextAlias === cur.alias && nextRssi === cur.rssi) return
        const copy = known.slice()
        copy[idx] = { address: cur.address, alias: nextAlias, rssi: nextRssi }
        root.nearby = copy
    }
    function handleScanLine(line) {
        const l = root.sanitizeLine(line)
        if (!l) return
        // [NEW] Device AA:BB:CC:DD:EE:FF Name
        const nw = l.match(/\[NEW\]\s+Device\s+([0-9A-Fa-f:]{17})(?:\s+(.*))?/)
        if (nw) {
            const addr = nw[1].toUpperCase()
            root.seenAddrs[addr] = true
            const rawAlias = (nw[2] || "").trim()
            root.upsertNearby(addr, rawAlias, 0)
            root.dataUpdated()
            return
        }
        const chg = l.match(/\[CHG\]\s+Device\s+([0-9A-Fa-f:]{17})\s+(.*)/)
        if (!chg) return
        const addr = chg[1].toUpperCase()
        const prop = chg[2]
        root.seenAddrs[addr] = true
        // BlueZ prints RSSI as signed hex: "RSSI: 0xffffffc5 (-59)".
        if (prop.startsWith("RSSI:")) {
            const dec = prop.match(/\((-?\d+)\)\s*$/) || prop.match(/RSSI:\s*(-?\d+)/)
            let val = dec ? parseInt(dec[1], 10) : NaN
            if (isNaN(val)) {
                const hex = prop.match(/0x([0-9a-fA-F]+)/)
                if (hex) {
                    val = parseInt(hex[1], 16)
                    if (val > 0x7fffffff) val -= 0x100000000
                }
            }
            if (!isNaN(val)) { root.upsertNearby(addr, "", val); root.dataUpdated() }
            return
        }
        // [CHG] Device AA:BB... Name:/Alias: X — update alias when it arrives later
        if (prop.startsWith("Name:") || prop.startsWith("Alias:")) {
            const name = prop.slice(prop.indexOf(":") + 1).trim()
            if (name) { root.upsertNearby(addr, name, undefined); root.dataUpdated() }
        }
    }

    property Process pollProc: Process {
        running: true
        command: ["sh", "-c", "bluetoothctl show 2>/dev/null; echo '---SECTION:CONNECTED---'; bluetoothctl devices Connected 2>/dev/null; echo '---SECTION:PAIRED---'; bluetoothctl devices Paired 2>/dev/null; echo '---SECTION:ALL---'; bluetoothctl devices 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                // bluetoothctl emits ANSI escapes on error/status lines even piped
                const txt = root.stripAnsi(this.text)
                if (!txt || txt.indexOf("No default controller") !== -1) {
                    root.available = false
                    root.powered = false
                    root.connectedCount = 0
                    root.devices = []
                    root.dataUpdated()
                    return
                }
                root.available = true
                const showSec = txt.split("---SECTION:CONNECTED---")[0] || ""
                root.powered = showSec.indexOf("Powered: yes") !== -1
                const aliasMatch = showSec.match(/Alias:\s*(.*)/)
                if (aliasMatch) root.controllerAlias = aliasMatch[1].trim()
                const addrMatch = showSec.match(/Controller\s+([0-9A-F:]+)/)
                if (addrMatch) root.controllerAddress = addrMatch[1].trim()

                const connectedSec = (txt.split("---SECTION:CONNECTED---")[1] || "").split("---SECTION:PAIRED---")[0] || ""
                const pairedSec = (txt.split("---SECTION:PAIRED---")[1] || "").split("---SECTION:ALL---")[0] || ""
                const allSec = (txt.split("---SECTION:ALL---")[1] || "")
                const parseDevices = sec => {
                    const map = {}
                    sec.trim().split("\n").forEach(l => {
                        const m = l.match(/Device\s+([0-9A-Fa-f:]{17})\s+(.*)/)
                        if (m) map[m[1].toUpperCase()] = m[2].trim()
                    })
                    return map
                }
                const connected = parseDevices(connectedSec)
                const paired = parseDevices(pairedSec)
                const all = parseDevices(allSec)
                // Paired devices must be listed even when they are not in the
                // discovery cache (previously the first 30 cache entries were
                // the only source, so a freshly paired device could vanish).
                const addrs = Object.keys(all)
                    .concat(Object.keys(paired))
                    .concat(Object.keys(connected))
                    .filter((a, i, arr) => arr.indexOf(a) === i)
                const devs = addrs.map(a => ({
                    alias: all[a] || paired[a] || connected[a] || a,
                    address: a,
                    connected: connected[a] !== undefined,
                    paired: paired[a] !== undefined,
                    trusted: paired[a] !== undefined,
                    battery: -1
                }))
                root.connectedCount = Object.keys(connected).length
                root.devices = devs
                root.dataUpdated()
            }
        }
    }

    property Process btDiscProc: Process { stdout: StdioCollector {} onExited: root.finishAction(root.btDiscProc) }
    property Process btConnProc: Process { stdout: StdioCollector {} onExited: root.finishAction(root.btConnProc) }
    property Process btRemoveProc: Process { stdout: StdioCollector {} onExited: root.finishAction(root.btRemoveProc) }
    property Process btTrustProc: Process { stdout: StdioCollector {} onExited: root.finishAction(root.btTrustProc) }
    property Process btInfoProc: Process {
        stdout: StdioCollector {}
        onExited: {
            const raw = root.processText(root.btInfoProc)
            if (/not available/i.test(raw)) {
                root.pairingAddress = ""
                root.reportError("Device is no longer in range — rescan and try again")
                root.pollProc.running = true
                return
            }
            const type = raw.match(/^Device\s+[0-9A-Fa-f:]+\s+\((public|random)\)/m)
            if (type && type[1] === "random" && root.pairAlias) {
                // BLE random address (AirPods, phones, …). Look for a classic
                // sibling with the same alias and pair that instead.
                root.btTwinProc.command = ["sh", "-c",
                    "addr=\"$1\"; name=\"$2\"; " +
                    "bluetoothctl devices 2>/dev/null | while read -r _ a rest; do " +
                    "  [ \"$a\" = \"$addr\" ] && continue; " +
                    "  [ \"$rest\" = \"$name\" ] || continue; " +
                    "  case \"$(bluetoothctl info \"$a\" 2>/dev/null)\" in " +
                    "    *\"(public)\"*) echo \"$a\"; break;; " +
                    "  esac; " +
                    "done",
                    "sh", root.pairAddress, root.pairAlias]
                root.btTwinProc.running = true
            } else {
                root.runPair(root.pairAddress)
            }
        }
    }
    property Process btTwinProc: Process {
        stdout: StdioCollector {}
        onExited: {
            const twin = root.processText(root.btTwinProc).split("\n")[0].trim()
            root.runPair(twin || root.pairAddress)
        }
    }
    property Process btPairProc: Process {
        stdout: StdioCollector {}
        onExited: {
            const failure = root.findFailure(root.processText(root.btPairProc))
            root.pairingAddress = ""
            if (failure) {
                const hint = /authentication|failed to pair|not available/i.test(failure)
                    ? " — put the device in pairing mode and rescan" : ""
                root.reportError(failure + hint)
            } else {
                root.lastError = ""
                root.dataUpdated()
            }
            root.pollProc.running = true
        }
    }
    property Process btPowerOn: Process {
        command: ["sh", "-c", "rfkill unblock bluetooth 2>/dev/null; bluetoothctl power on 2>&1"]
        stdout: StdioCollector {}
        onExited: function(exitCode) {
            root.finishPower(root.btPowerOn, exitCode, "Bluetooth power-on failed")
        }
    }
    property Process btPowerOff: Process {
        command: ["sh", "-c", "bluetoothctl power off 2>&1"]
        stdout: StdioCollector {}
        onExited: function(exitCode) {
            root.finishPower(root.btPowerOff, exitCode, "Bluetooth power-off failed")
        }
    }
    property Process btScanOnProc: Process {
        // One-shot (--timeout) mode: plain `bluetoothctl scan on` piped to a
        // non-tty never prints "Discovery started" nor [NEW] events, while
        // --timeout streams them and exits on its own (scanTimer acts as backup).
        command: ["bluetoothctl", "--timeout", "10", "scan", "on"]
        stdout: SplitParser { onRead: (line) => root.handleScanLine(line) }
        onExited: {
            if (root.pendingScan) { root.pendingScan = false; root.beginScan() }
            else if (root.scanning) root.stopScan()
        }
    }
    property Process btScanOffProc: Process { command: ["bluetoothctl", "scan", "off"]; stdout: StdioCollector { onStreamFinished: root.pollProc.running = true } }
    property Process btScanListProc: Process {
        // `paired-devices` is not a valid command on this bluetoothctl version —
        // the menu-style filter `devices Paired` is the supported equivalent.
        command: ["sh", "-c", "echo '---SECTION:PAIRED---'; bluetoothctl devices Paired 2>/dev/null; echo '---SECTION:CONNECTED---'; bluetoothctl devices Connected 2>/dev/null; echo '---SECTION:CACHE---'; bluetoothctl devices 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: root.mergeNearbyFromCache(root.stripAnsi(this.text))
        }
    }

    // Post-scan nearby refresh: merge BlueZ's resolved names into the list that
    // was built live from discovery events. Never remove entries here — the
    // BlueZ cache drops BLE devices as soon as they stop advertising.
    function mergeNearbyFromCache(txt) {
        if (!txt) return
        const cacheSec = (txt.split("---SECTION:CACHE---")[1] || "")
        const byAddr = {}
        root.nearby.forEach(d => { byAddr[d.address] = d })
        cacheSec.trim().split("\n").forEach(l => {
            const m = l.match(/Device\s+([0-9A-Fa-f:]{17})\s+(.*)/)
            if (!m) return
            const addr = m[1].toUpperCase()
            const alias = m[2].trim()
            // Only devices actually seen during this scan session.
            if (!root.seenAddrs[addr]) return
            if (root.isPlaceholderAlias(alias, addr)) return
            if (!byAddr[addr]) byAddr[addr] = { address: addr, alias: alias, rssi: 0 }
            else if (root.isPlaceholderAlias(byAddr[addr].alias, addr)) byAddr[addr] = { address: addr, alias: alias, rssi: byAddr[addr].rssi }
        })
        root.nearby = Object.keys(byAddr).map(a => byAddr[a])
        root.dataUpdated()
    }
    property Process btPairableProc: Process { command: ["bluetoothctl", "pairable", "on"] }

    property Timer scanTimer: Timer { interval: 12000; running: false; repeat: false; onTriggered: root.stopScan() }
    property Timer pollTimer: Timer { interval: 5000; running: true; repeat: true; onTriggered: root.pollProc.running = true }

    // Do not force the adapter off at startup: this runs on every QML reload and
    // was power-cycling Bluetooth mid-session, dropping paired devices (AirPods
    // would connect, then get disconnected a few seconds later). BlueZ's
    // AutoEnable=true already handles the desired session default.
}
