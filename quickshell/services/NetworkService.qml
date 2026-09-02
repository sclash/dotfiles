pragma Singleton
import QtQuick
import Quickshell.Io

QtObject {
    id: root
    property bool available: true
    property bool connected: false
    property string type: "none"
    property string essid: ""
    property string ipaddr: ""
    property int signalStrength: -1
    property bool vpnActive: false
    property string vpnName: ""
    property bool connecting: false
    property string connectingSsid: ""
    property var knownNetworks: []
    property var scannedNetworks: []
    property var vpnConnections: []
    property string lastError: ""
    readonly property bool busy: nmUpProc.running || nmScanConnectProc.running || nmDownProc.running
    signal dataUpdated()

    function reportError(txt) {
        const t = (txt || "").trim()
        if (!t) return
        const line = t.split("\n").filter(l => l.indexOf("Error") !== -1)[0] || t.split("\n")[0]
        if (line) { root.lastError = line; root.dataUpdated() }
    }
    // Splits an nmcli terse line on unescaped ':' ('\:' is an escaped colon inside a value)
    function splitTerse(line) {
        const out = []
        let cur = ""
        for (let i = 0; i < line.length; i++) {
            if (line[i] === "\\" && line[i + 1] === ":") { cur += ":"; i++ }
            else if (line[i] === ":") { out.push(cur); cur = "" }
            else cur += line[i]
        }
        out.push(cur)
        return out
    }

    function disconnect() {
        if (!connected || busy) return
        lastError = ""
        root.nmDownProc.command = ["nmcli", "connection", "down", "id", essid]
        root.nmDownProc.running = true
    }
    function connectKnown(uuid) {
        if (busy) return
        lastError = ""
        root.connecting = true
        const k = root.knownNetworks
        for (let i = 0; i < k.length; i++) if (k[i].uuid === uuid) { root.connectingSsid = k[i].name; break }
        root.nmUpProc.command = ["nmcli", "connection", "up", "uuid", uuid]
        root.nmUpProc.running = true
    }
    // One-shot connect (spec §3.3/§5): resolves the ssid against known profiles internally —
    // known → nmcli connection up (password ignored); unknown → device wifi connect.
    function connectScanned(ssid, password) {
        if (busy) return
        lastError = ""
        root.connecting = true
        root.connectingSsid = ssid
        const k = root.knownNetworks
        for (let i = 0; i < k.length; i++) {
            if (k[i].name === ssid) {
                root.nmUpProc.command = ["nmcli", "connection", "up", "uuid", k[i].uuid]
                root.nmUpProc.running = true
                return
            }
        }
        const args = ["nmcli", "device", "wifi", "connect", ssid]
        if (password && password.length > 0) args.push("password", password)
        root.nmScanConnectProc.command = args
        root.nmScanConnectProc.running = true
    }
    function forget(uuid) {
        if (busy) return
        lastError = ""
        root.nmForgetProc.command = ["nmcli", "connection", "delete", "uuid", uuid]
        root.nmForgetProc.running = true
    }
    function rescanWifi() { root.nmRescanProc.running = true }
    function vpnConnect(uuid) { root.nmVpnUpProc.command = ["nmcli", "connection", "up", "uuid", uuid]; root.nmVpnUpProc.running = true }
    function vpnDisconnect(uuid) { root.nmVpnDownProc.command = ["nmcli", "connection", "down", "uuid", uuid]; root.nmVpnDownProc.running = true }
    function vpnDelete(uuid) { root.nmVpnDelProc.command = ["nmcli", "connection", "delete", "uuid", uuid]; root.nmVpnDelProc.running = true }
    function refresh() { root.pollProc.running = true; root.knownProc.running = true; root.vpnProc.running = true }
    function launchEditor() { root.vpnEditorProc.running = true }
    function vpnAdd() { root.vpnAddProc.running = true }

    property Process pollProc: Process {
        running: true
        command: ["sh", "-c", "nmcli -t -f TYPE,STATE,CONNECTION device 2>/dev/null; echo '---IP---'; nmcli -t -f IP4.ADDRESS device show 2>/dev/null | head -n 5; echo '---VPN---'; nmcli -t -f NAME,TYPE connection show --active 2>/dev/null | grep vpn || true; echo '---WIFI---'; nmcli -t -f IN-USE,SIGNAL,SSID device wifi list --rescan no 2>/dev/null | head -n 20"]
        stdout: StdioCollector {
            onStreamFinished: {
                const txt = this.text
                if (!txt || txt.trim().length === 0) { root.available = false; return }
                root.available = true
                const parts = txt.split("---IP---")
                const devSection = parts[0] || ""
                const ipPart = (parts[1] || "").split("---VPN---")[0] || ""
                const vpnPart = (parts[1] || "").split("---VPN---")[1] || ""
                const wifiPart = (parts[1] || "").split("---WIFI---")[1] || ""
                const lines = devSection.trim().split("\n").filter(Boolean)
                let foundWifi = false
                let foundEth = false
                let activeSsid = ""
                for (const l of lines) {
                    const segs = l.split(":")
                    if (segs.length < 3) continue
                    const t = segs[0], state = segs[1], name = segs.slice(2).join(":")
                    if (state.indexOf("connected") !== -1) {
                        if (t === "wifi") { foundWifi = true; activeSsid = name; root.type = "wifi"; root.connected = true }
                        else if (t === "ethernet") { foundEth = true; if (!foundWifi) { root.type = "ethernet"; root.connected = true; activeSsid = name } }
                    }
                }
                if (!foundWifi && !foundEth) { root.connected = false; root.type = "none"; activeSsid = ""; root.essid = "" }
                else { root.essid = activeSsid }
                if (wifiPart) {
                    const wlines = wifiPart.trim().split("\n")
                    for (const wl of wlines) if (wl.startsWith("*")) { const segs = wl.split(":"); if (segs.length >= 3) root.signalStrength = parseInt(segs[1]) || -1 }
                }
                const ipLines = ipPart.trim().split("\n").filter(Boolean).map(l=> l.replace("IP4.ADDRESS[1]:","").split("/")[0].trim()).filter(ip=> ip && ip !== "127.0.0.1" && !ip.startsWith("172.17."))
                root.ipaddr = ipLines.length > 0 ? ipLines[0] : ""
                const vpnLines = vpnPart.trim().split("\n").filter(Boolean).filter(l => l.indexOf("vpn") !== -1)
                root.vpnActive = vpnLines.length > 0
                root.vpnName = vpnLines.length > 0 ? vpnLines[0].split(":")[0] : ""
                root.dataUpdated()
            }
        }
    }

    property Process knownProc: Process {
        command: ["sh", "-c", "nmcli -t -f NAME,UUID,TYPE connection show 2>/dev/null | grep 802-11-wireless"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = this.text.trim().split("\n").filter(Boolean)
                root.knownNetworks = lines.map(l => {
                    const p = root.splitTerse(l)
                    return ({ name: p[0] || "", uuid: p[1] || "", type: "wifi" })
                }).filter(n => n.name && n.uuid)
            }
        }
    }
    property Process vpnProc: Process {
        command: ["sh", "-c", "nmcli -t -f NAME,UUID,TYPE connection show 2>/dev/null | grep -E 'vpn|wireguard'"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = this.text.trim().split("\n").filter(Boolean)
                root.vpnConnections = lines.map(l => {
                    const p = root.splitTerse(l)
                    return ({ name: p[0] || "", uuid: p[1] || "", active: false })
                }).filter(v => v.name && v.uuid)
            }
        }
    }

    property Process nmDownProc: Process {
        stdout: StdioCollector { onStreamFinished: root.pollProc.running = true }
        stderr: StdioCollector { onStreamFinished: root.reportError(this.text) }
    }
    property Process nmUpProc: Process {
        stdout: StdioCollector {
            onStreamFinished: {
                const txt = this.text
                if (txt.indexOf("successfully activated") !== -1) root.lastError = ""
                root.connecting = false
                root.connectingSsid = ""
                root.pollProc.running = true
            }
        }
        stderr: StdioCollector { onStreamFinished: { root.connecting = false; root.connectingSsid = ""; root.reportError(this.text) } }
    }
    property Process nmScanConnectProc: Process {
        stdout: StdioCollector {
            onStreamFinished: {
                const txt = this.text
                if (txt.indexOf("successfully activated") !== -1) root.lastError = ""
                root.connecting = false
                root.connectingSsid = ""
                root.pollProc.running = true
            }
        }
        stderr: StdioCollector { onStreamFinished: { root.connecting = false; root.connectingSsid = ""; root.reportError(this.text) } }
    }
    property Process nmForgetProc: Process {
        stdout: StdioCollector { onStreamFinished: { root.pollProc.running = true; root.knownProc.running = true } }
        stderr: StdioCollector { onStreamFinished: root.reportError(this.text) }
    }
    property Process nmVpnUpProc: Process {
        stdout: StdioCollector { onStreamFinished: root.pollProc.running = true }
        stderr: StdioCollector { onStreamFinished: root.reportError(this.text) }
    }
    property Process nmVpnDownProc: Process {
        stdout: StdioCollector { onStreamFinished: root.pollProc.running = true }
        stderr: StdioCollector { onStreamFinished: root.reportError(this.text) }
    }
    property Process nmVpnDelProc: Process {
        stdout: StdioCollector { onStreamFinished: root.vpnProc.running = true }
        stderr: StdioCollector { onStreamFinished: root.reportError(this.text) }
    }
    property Process nmRescanProc: Process {
        command: ["sh", "-c", "nmcli device wifi rescan 2>/dev/null; nmcli -t -f SSID,SIGNAL,SECURITY device wifi list --rescan no 2>/dev/null | head -n 30"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = this.text.trim().split("\n").filter(Boolean)
                root.scannedNetworks = lines.map(l => { const parts = l.split(":"); if (parts.length < 3) return null; return ({ ssid: parts[0], signal: parseInt(parts[1])||0, security: parts[2] }) }).filter(Boolean).sort((a,b)=> b.signal - a.signal)
                root.pollProc.running = true
            }
        }
    }
    property Process vpnEditorProc: Process { command: ["nm-connection-editor"]; stdout: StdioCollector { onStreamFinished: { root.vpnProc.running = true; root.knownProc.running = true } } }
    property Process vpnAddProc: Process { command: ["nm-connection-editor", "-c", "-t", "vpn"]; stdout: StdioCollector { onStreamFinished: { root.vpnProc.running = true; root.knownProc.running = true } } }

    property Timer pollTimer: Timer { interval: 5000; running: true; repeat: true; onTriggered: root.pollProc.running = true }
    Component.onCompleted: { root.knownProc.running = true; root.vpnProc.running = true }
}
