pragma Singleton
import QtQuick
import Quickshell.Io

QtObject {
    id: root
    property bool available: true
    property bool powered: false
    property int connectedCount: 0
    property string controllerAlias: ""
    property string controllerAddress: ""
    property var devices: []
    property string lastError: ""
    signal dataUpdated()

    function disconnect(address) { root.btDiscProc.command = ["bluetoothctl", "disconnect", address]; root.btDiscProc.running = true }
    function connect(address) { root.btConnProc.command = ["bluetoothctl", "connect", address]; root.btConnProc.running = true }
    function forget(address) { root.btRemoveProc.command = ["bluetoothctl", "remove", address]; root.btRemoveProc.running = true }
    function trust(address) { root.btTrustProc.command = ["bluetoothctl", "trust", address]; root.btTrustProc.running = true }
    function togglePower() { if (root.powered) root.btPowerOff.running=true; else root.btPowerOn.running=true }
    function startScan() { root.btScanOnProc.running = true; root.scanTimer.running = true }
    function stopScan() { root.btScanOffProc.running = true; root.scanTimer.running = false }

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
    property Process btPowerOn: Process { command: ["bluetoothctl", "power", "on"]; stdout: StdioCollector { onStreamFinished: root.pollProc.running = true } }
    property Process btPowerOff: Process { command: ["bluetoothctl", "power", "off"]; stdout: StdioCollector { onStreamFinished: root.pollProc.running = true } }
    property Process btScanOnProc: Process { command: ["bluetoothctl", "scan", "on"]; stdout: StdioCollector {} }
    property Process btScanOffProc: Process { command: ["bluetoothctl", "scan", "off"]; stdout: StdioCollector { onStreamFinished: root.pollProc.running = true } }

    property Timer scanTimer: Timer { interval: 10000; running: false; repeat: false; onTriggered: { root.btScanOffProc.running = true; root.pollProc.running = true } }
    property Timer pollTimer: Timer { interval: 5000; running: true; repeat: true; onTriggered: root.pollProc.running = true }
}
