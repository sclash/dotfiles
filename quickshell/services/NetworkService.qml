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
    property var knownNetworks: []
    property var scannedNetworks: []
    property var vpnConnections: []
    property string lastError: ""
    signal dataUpdated()

    function disconnect() {
        if (!connected) return
        lastError = ""
        root.nmDownProc.command = ["nmcli", "connection", "down", "id", essid]
        root.nmDownProc.running = true
    }
    function connectKnown(name) {
        lastError = ""
        root.nmUpProc.command = ["nmcli", "connection", "up", "id", name]
        root.nmUpProc.running = true
    }
    function connectScanned(ssid, password, security) {
        lastError = ""
        const sec = security || ""
        const km = sec.indexOf("WPA3") !== -1 || sec.indexOf("SAE") !== -1 ? "sae" : "wpa-psk"
        const hasPwd = password && password.length > 0
        const secArgs = hasPwd ? ' wifi-sec.key-mgmt ' + km + ' wifi-sec.psk "$2"' : ''
        const modArgs = hasPwd ? ' wifi-sec.psk "$2"' : ''
        let script = 'err=$(nmcli connection up id "$1" 2>&1); rc=$?; if [ $rc -eq 0 ]; then echo "$err"; exit 0; fi; '
        script += 'case "$err" in *"unknown connection"*|*"mismatching interface"*|*"No suitable device"*|*"Secrets were required"*) ;; *) echo "$err" >&2; exit $rc;; esac; '
        script += 'nmcli connection modify id "$1" connection.interface-name ""' + modArgs + ' 2>/dev/null; '
        script += 'err=$(nmcli connection up id "$1" 2>&1); rc=$?; if [ $rc -eq 0 ]; then echo "$err"; exit 0; fi; '
        script += 'if nmcli -t -f NAME connection show 2>/dev/null | cut -d: -f1 | grep -qxF "$1"; then un="$1 (user)"; else un="$1"; fi; '
        script += 'nmcli connection add type wifi con-name "$un" ssid "$1"' + secArgs + ' connection.permissions "user:$(id -un)" && nmcli connection up "$un"'
        root.nmScanConnectProc.command = ["sh", "-c", script, "sh", ssid, password ? password : ""]
        root.nmScanConnectProc.running = true
    }
    function forget(name) {
        lastError = ""
        root.nmForgetProc.command = ["nmcli", "connection", "delete", "id", name]
        root.nmForgetProc.running = true
    }
    function rescanWifi() { root.nmRescanProc.running = true }
    function vpnConnect(name) { root.nmVpnUpProc.command = ["nmcli", "connection", "up", "id", name]; root.nmVpnUpProc.running = true }
    function vpnDisconnect(name) { root.nmVpnDownProc.command = ["nmcli", "connection", "down", "id", name]; root.nmVpnDownProc.running = true }
    function vpnDelete(name) { root.nmVpnDelProc.command = ["nmcli", "connection", "delete", "id", name]; root.nmVpnDelProc.running = true }
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
                else { root.essid = activeSsid; root.lastError = "" }
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
        command: ["sh", "-c", "nmcli -t -f NAME,TYPE connection show 2>/dev/null | grep 802-11-wireless | cut -d: -f1"]
        stdout: StdioCollector {
            onStreamFinished: {
                const names = this.text.trim().split("\n").filter(Boolean)
                root.knownNetworks = names.map(n => ({ name: n, type: "wifi" }))
            }
        }
    }
    property Process vpnProc: Process {
        command: ["sh", "-c", "nmcli -t -f NAME,TYPE connection show 2>/dev/null | grep vpn"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = this.text.trim().split("\n").filter(Boolean)
                root.vpnConnections = lines.map(l => { const p = l.split(":"); return ({ name: p[0], active: false }) })
            }
        }
    }

    property Process nmDownProc: Process { stdout: StdioCollector { onStreamFinished: root.pollProc.running = true } }
    property Process nmUpProc: Process {
        stdout: StdioCollector {
            onStreamFinished: {
                const txt = this.text
                if (txt.indexOf("successfully activated") !== -1) root.lastError = ""
                root.pollProc.running = true
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                const txt = this.text.trim()
                if (txt && txt.indexOf("Error") !== -1) { root.lastError = txt.split("\n").filter(l => l.indexOf("Error") !== -1)[0] || txt.split("\n")[0]; root.dataUpdated() }
            }
        }
    }
    property Process nmScanConnectProc: Process {
        stdout: StdioCollector {
            onStreamFinished: {
                const txt = this.text
                if (txt.indexOf("successfully activated") !== -1 || txt.indexOf("successfully added") !== -1) root.lastError = ""
                root.pollProc.running = true
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                const txt = this.text.trim()
                if (txt && txt.indexOf("Error") !== -1) { root.lastError = txt.split("\n").filter(l => l.indexOf("Error") !== -1)[0] || txt.split("\n")[0]; root.dataUpdated() }
            }
        }
    }
    property Process nmForgetProc: Process { stdout: StdioCollector { onStreamFinished: { root.pollProc.running = true; root.knownProc.running = true } } }
    property Process nmVpnUpProc: Process { stdout: StdioCollector { onStreamFinished: root.pollProc.running = true } }
    property Process nmVpnDownProc: Process { stdout: StdioCollector { onStreamFinished: root.pollProc.running = true } }
    property Process nmVpnDelProc: Process { stdout: StdioCollector { onStreamFinished: root.vpnProc.running = true } }
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
