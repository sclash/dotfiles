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
    signal dataUpdated()

    function disconnect(address) { root.btDiscProc.command = ["bluetoothctl", "disconnect", address]; root.btDiscProc.running = true }
    function connect(address) { root.btConnProc.command = ["bluetoothctl", "connect", address]; root.btConnProc.running = true }
    function forget(address) { root.btRemoveProc.command = ["bluetoothctl", "remove", address]; root.btRemoveProc.running = true }
    function trust(address) { root.btTrustProc.command = ["bluetoothctl", "trust", address]; root.btTrustProc.running = true }
    function togglePower() { if (root.powered) root.btPowerOff.running=true; else root.btPowerOn.running=true }
    function pairAndConnect(address) {
        root.btPairProc.command = ["sh", "-c", "bluetoothctl --agent NoInputNoOutput pair " + address + "; bluetoothctl trust " + address + "; bluetoothctl --agent NoInputNoOutput connect " + address + " 2>/dev/null"]
        root.btPairProc.running = true
    }

    function startScan() {
        root.nearby = []
        root.seenAddrs = {}
        if (!root.powered) { root.btPowerOn.running = true; root.scanning = true; root.deferredScan.running = true }
        else beginScan()
    }
    function beginScan() {
        if (!root.powered) { root.btPowerOn.running = true; root.deferredScan.running = true; return }
        root.seenAddrs = {}
        root.scanning = true
        root.btDiscoverableOn.running = true
        root.btScanOnProc.running = true
        root.scanTimer.restart()
    }
    function stopScan() {
        root.btScanOnProc.running = false
        root.btScanOffProc.running = true
        root.btDiscoverableOff.running = true
        root.scanTimer.running = false
        root.scanning = false
        // Names resolve into BlueZ's cache during discovery but [CHG] Name
        // events are unreliable — read the cache once the scan ends (same as
        // running `bluetoothctl devices` after `scan on` in a terminal).
        root.btScanListProc.running = true
    }

    // bluetoothctl hardcodes ANSI colour codes on [NEW]/[CHG] event lines even
    // when stdout is piped, so raw lines look like "\x1b[0;92mNEW\x1b[0m Device …"
    // and never match a literal "[NEW]" — strip the escapes before parsing.
    function sanitizeLine(line) { return String(line).replace(/\x1b\[[0-9;]*m/g, "").trim() }
    function isPlaceholderAlias(alias, addr) {
        if (!alias || alias === "Unknown device") return true
        return alias.replace(/-/g, ":").toUpperCase() === addr
    }
    function handleScanLine(line) {
        const l = root.sanitizeLine(line)
        if (!l) return
        const known = root.nearby
        // [NEW] Device AA:BB:CC:DD:EE:FF Name
        const nw = l.match(/\[NEW\]\s+Device\s+([0-9A-Fa-f:]{17})(?:\s+(.*))?/)
        if (nw) {
            const addr = nw[1].toUpperCase()
            root.seenAddrs[addr] = true
            if (known.some(d => d.address === addr)) return
            const rawAlias = (nw[2] || "").trim()
            root.nearby = known.concat([{ address: addr, alias: root.isPlaceholderAlias(rawAlias, addr) ? "Unknown device" : rawAlias, rssi: 0 }])
            root.dataUpdated()
            return
        }
        const addrRe = /\[CHG\]\s+Device\s+([0-9A-Fa-f:]{17})\s+(.*)/
        // [CHG] Device AA:BB... RSSI: -42 — signal for spec sorting
        const rssi = l.match(addrRe)
        if (rssi && rssi[2].startsWith("RSSI:")) {
            const addr = rssi[1].toUpperCase()
            root.seenAddrs[addr] = true
            const val = parseInt(rssi[2].slice(5).trim(), 10)
            if (isNaN(val)) return
            root.nearby = known.map(d => d.address === addr ? { address: d.address, alias: d.alias, rssi: val } : d)
            root.dataUpdated()
            return
        }
        // [CHG] Device AA:BB... Name:/Alias: X — update alias when it arrives later
        const chg = l.match(addrRe)
        if (chg && (chg[2].startsWith("Name:") || chg[2].startsWith("Alias:"))) {
            const addr = chg[1].toUpperCase()
            root.seenAddrs[addr] = true
            const name = chg[2].slice(chg[2].indexOf(":") + 1).trim()
            if (!name) return
            let hit = false
            const copy = known.map(d => {
                if (d.address !== addr) return d
                hit = true
                return root.isPlaceholderAlias(d.alias, addr) ? { address: d.address, alias: name, rssi: d.rssi } : d
            })
            if (hit) { root.nearby = copy; root.dataUpdated() }
        }
    }

    property Process pollProc: Process {
        running: true
        command: ["sh", "-c", "bluetoothctl show 2>/dev/null; echo '---DEVICES---'; bluetoothctl devices Connected 2>/dev/null; echo '---PAIRED---'; bluetoothctl devices Paired 2>/dev/null; echo '---ALL---'; bluetoothctl devices 2>/dev/null | head -n 30"]
        stdout: StdioCollector {
            onStreamFinished: {
                // bluetoothctl emits ANSI escapes on error/status lines even piped
                const txt = String(this.text).replace(/\x1b\[[0-9;]*m/g, "")
                if (!txt || txt.indexOf("No default controller") !== -1) { root.available = false; root.powered = false; return }
                root.available = true
                const sections = txt.split("---DEVICES---")
                const showSec = sections[0] || ""
                root.powered = showSec.indexOf("Powered: yes") !== -1
                const aliasMatch = showSec.match(/Alias:\s*(.*)/)
                if (aliasMatch) root.controllerAlias = aliasMatch[1].trim()
                const addrMatch = showSec.match(/Controller\s+([0-9A-F:]+)/)
                if (addrMatch) root.controllerAddress = addrMatch[1].trim()
                const afterDevices = (sections[1]||"").split("---PAIRED---")
                const connectedSec = afterDevices[0]||""
                const pairedSec = (afterDevices[1]||"").split("---ALL---")[0]||""
                const allSec = (afterDevices[1]||"").split("---ALL---")[1]||""
                const connectedLines = connectedSec.trim().split("\n").filter(l=> l.indexOf("Device")===0)
                root.connectedCount = connectedLines.length
                const pairedMap = {}
                pairedSec.trim().split("\n").forEach(l=>{ const m = l.match(/Device\s+([0-9A-F:]+)\s+(.*)/); if (m) pairedMap[m[1]] = m[2] })
                const allLines = allSec.trim().split("\n").filter(l=> l.indexOf("Device")===0)
                const devs = allLines.map(l=>{ const m=l.match(/Device\s+([0-9A-F:]+)\s+(.*)/); if (!m) return null; const addr=m[1], alias=m[2]; const isConnected = connectedSec.indexOf(addr)!==-1; const isPaired = pairedMap[addr] !== undefined; return ({ alias: alias, address: addr, connected: isConnected, paired: isPaired, trusted: isPaired, battery: -1 }) }).filter(Boolean)
                root.devices = devs
                root.dataUpdated()
            }
        }
    }

    property Process btDiscProc: Process { stdout: StdioCollector { onStreamFinished: root.pollProc.running = true } }
    property Process btConnProc: Process { stdout: StdioCollector { onStreamFinished: root.pollProc.running = true } }
    property Process btRemoveProc: Process { stdout: StdioCollector { onStreamFinished: root.pollProc.running = true } }
    property Process btTrustProc: Process { stdout: StdioCollector { onStreamFinished: root.pollProc.running = true } }
    property Process btPairProc: Process { stdout: StdioCollector { onStreamFinished: root.pollProc.running = true } }
    property Process btPowerOn: Process { command: ["bluetoothctl", "power", "on"]; stdout: StdioCollector { onStreamFinished: root.pollProc.running = true } }
    property Process btPowerOff: Process { command: ["bluetoothctl", "power", "off"]; stdout: StdioCollector { onStreamFinished: root.pollProc.running = true } }
    property Process btScanOnProc: Process {
        // One-shot (--timeout) mode: plain `bluetoothctl scan on` piped to a
        // non-tty never prints "Discovery started" nor [NEW] events, while
        // --timeout streams them and exits on its own (scanTimer acts as backup).
        command: ["bluetoothctl", "--timeout", "10", "scan", "on"]
        stdout: SplitParser { onRead: (line) => root.handleScanLine(line) }
    }
    property Process btScanOffProc: Process { command: ["bluetoothctl", "scan", "off"]; stdout: StdioCollector { onStreamFinished: root.pollProc.running = true } }
    property Process btScanListProc: Process {
        // `paired-devices` is not a valid command on this bluetoothctl version —
        // the menu-style filter `devices Paired` is the supported equivalent.
        command: ["sh", "-c", "echo '---PAIRED---'; bluetoothctl devices Paired 2>/dev/null; echo '---CONNECTED---'; bluetoothctl devices Connected 2>/dev/null; echo '---CACHE---'; bluetoothctl devices 2>/dev/null"]
        stdout: StdioCollector { onStreamFinished: root.populateNearbyFromCache(String(this.text).replace(/\x1b\[[0-9;]*m/g, ""))
        }
    }

    // Post-scan nearby refresh: cache devices seen by discovery, minus paired,
    // connected and still-nameless entries.
    function populateNearbyFromCache(txt) {
        if (root.scanning) return
        if (!txt) return
        const pairedSec = (txt.split("---PAIRED---")[1] || "").split("---CONNECTED---")[0] || ""
        const connectedSec = (txt.split("---CONNECTED---")[1] || "").split("---CACHE---")[0] || ""
        const cacheSec = (txt.split("---CACHE---")[1] || "")
        const inPaired = a => pairedSec.indexOf(a) !== -1
        const inConnected = a => connectedSec.indexOf(a) !== -1
        const list = []
        cacheSec.trim().split("\n").forEach(l => {
            const m = l.match(/Device\s+([0-9A-F:]{17})\s+(.*)/)
            if (!m) return
            const addr = m[1].toUpperCase()
            const alias = m[2].trim()
            // Only devices actually seen during the current scan session — the
            // cache keeps stale entries for devices that are off/out of range.
            if (!root.seenAddrs[addr]) return
            if (inPaired(addr) || inConnected(addr)) return
            if (root.isPlaceholderAlias(alias, addr)) return
            list.push({ address: addr, alias: alias, rssi: 0 })
        })
        root.nearby = list
        root.dataUpdated()
    }
    property Process btDiscoverableOn: Process { command: ["sh", "-c", "bluetoothctl discoverable on; bluetoothctl pairable on"] }
    property Process btDiscoverableOff: Process { command: ["bluetoothctl", "discoverable", "off"] }

    property Timer scanTimer: Timer { interval: 10000; running: false; repeat: false; onTriggered: root.stopScan() }
    property Timer deferredScan: Timer { interval: 1500; running: false; repeat: false; onTriggered: root.beginScan() }
    property Timer pollTimer: Timer { interval: 5000; running: true; repeat: true; onTriggered: root.pollProc.running = true }

    // Bluetooth powered off by default at session start
    Component.onCompleted: Qt.callLater(() => { root.btPowerOff.running = true })
}