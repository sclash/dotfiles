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
        if (!root.powered) { root.btPowerOn.running = true; root.scanning = true; root.deferredScan.running = true }
        else beginScan()
    }
    function beginScan() {
        if (!root.powered) { root.btPowerOn.running = true; root.deferredScan.running = true; return }
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
    }

    function handleScanLine(line) {
        const l = String(line).trim()
        if (!l) return
        const known = root.nearby
        // [NEW] Device AA:BB:CC:DD:EE:FF Name
        const nw = l.match(/\[NEW\]\s+Device\s+([0-9A-Fa-f:]{17})(?:\s+(.*))?/)
        if (nw) {
            const addr = nw[1].toUpperCase()
            if (known.some(d => d.address === addr)) return
            root.nearby = known.concat([{ address: addr, alias: (nw[2] || "Unknown device").trim(), rssi: 0 }])
            root.dataUpdated()
            return
        }
        const addrRe = /\[CHG\]\s+Device\s+([0-9A-Fa-f:]{17})\s+(.*)/
        // [CHG] Device AA:BB... RSSI: -42 — signal for spec sorting
        const rssi = l.match(addrRe)
        if (rssi && rssi[2].startsWith("RSSI:")) {
            const addr = rssi[1].toUpperCase()
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
            const name = chg[2].slice(chg[2].indexOf(":") + 1).trim()
            if (!name) return
            let hit = false
            const copy = known.map(d => {
                if (d.address !== addr) return d
                hit = true
                const isPlaceholder = !d.alias || d.alias === "Unknown device" || d.alias === d.address
                return isPlaceholder ? { address: d.address, alias: name, rssi: d.rssi } : d
            })
            if (hit) { root.nearby = copy; root.dataUpdated() }
        }
    }

    property Process pollProc: Process {
        running: true
        command: ["sh", "-c", "bluetoothctl show 2>/dev/null; echo '---DEVICES---'; bluetoothctl devices Connected 2>/dev/null; echo '---PAIRED---'; bluetoothctl paired-devices 2>/dev/null; echo '---ALL---'; bluetoothctl devices 2>/dev/null | head -n 30"]
        stdout: StdioCollector {
            onStreamFinished: {
                const txt = this.text
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
        command: ["bluetoothctl", "scan", "on"]
        stdout: SplitParser { onRead: (line) => root.handleScanLine(line) }
    }
    property Process btScanOffProc: Process { command: ["bluetoothctl", "scan", "off"]; stdout: StdioCollector { onStreamFinished: root.pollProc.running = true } }
    property Process btDiscoverableOn: Process { command: ["sh", "-c", "bluetoothctl discoverable on; bluetoothctl pairable on"] }
    property Process btDiscoverableOff: Process { command: ["bluetoothctl", "discoverable", "off"] }

    property Timer scanTimer: Timer { interval: 10000; running: false; repeat: false; onTriggered: root.stopScan() }
    property Timer deferredScan: Timer { interval: 1500; running: false; repeat: false; onTriggered: root.beginScan() }
    property Timer pollTimer: Timer { interval: 5000; running: true; repeat: true; onTriggered: root.pollProc.running = true }

    // Bluetooth powered off by default at session start
    Component.onCompleted: Qt.callLater(() => { root.btPowerOff.running = true })
}