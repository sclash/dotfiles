pragma Singleton
import QtQuick
import Quickshell.Io
import "vpnSchema.js" as VpnSchema

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
    property bool wifiEnabled: true
    property string iface: ""
    property double rxTotal: 0
    property double txTotal: 0
    property double rxRate: 0
    property double txRate: 0
    property double _prevRx: -1
    property double _prevTx: -1
    property double _prevTs: 0
    property string _trafficIface: ""
    // Native VPN management through the nm-vpn helper
    // (docs/superpowers/specs/2026-11-09-native-vpn-design.md).
    property bool helperAvailable: false      // nm-vpn on PATH
    property var vpnTypes: []                 // [{name, service, import}] from `nm-vpn types`
    property var vpnNeed: []                  // secret keys a pending connect asks for
    property string vpnNeedUuid: ""
    property string vpnNeedName: ""
    property string vpnNeedType: ""
    property var importCandidates: []         // config files found by refreshImportCandidates()
    property var _helperCb: null
    property var _helperResult: null          // parsed answer, handed to the callback once the process has exited
    property bool _helperExited: false
    property string _helperPayload: ""
    readonly property bool busy: nmUpProc.running || nmScanConnectProc.running || nmDownProc.running || helperProc.running
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
    function formatBytes(b) {
        let v = Number(b) || 0
        if (v <= 0) return "0 B"
        const units = ["B", "KB", "MB", "GB", "TB"]
        let u = 0
        while (v >= 1024 && u < units.length - 1) { v /= 1024; u++ }
        return (u === 0 ? Math.round(v) : (Math.round(v * 10) / 10)) + " " + units[u]
    }
    function formatRate(bps) { return formatBytes(bps) + "/s" }

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
    function toggleWifi() {
        if (root.nmRadioProc.running) return
        root.nmRadioProc.command = ["nmcli", "radio", "wifi", root.wifiEnabled ? "off" : "on"]
        root.nmRadioProc.running = true
    }
    // Connects through nm-vpn. Secrets set to Ask come back as `need`: the
    // Network Center prompts and calls this again with them. Without nm-vpn,
    // plain nmcli (no prompt).
    function vpnConnect(uuid, secrets) {
        const v = root.vpnConnections.filter(x => x.uuid === uuid)[0]
        const name = v ? v.name : ""
        root.lastError = ""
        if (!root.helperAvailable) {
            root.nmVpnUpProc.command = ["nmcli", "connection", "up", "uuid", uuid]
            root.nmVpnUpProc.running = true
            return
        }
        root.connecting = true
        root.connectingSsid = name
        root._runHelper("connect", { uuid: uuid, secrets: secrets || {} }, r => {
            root.connecting = false
            root.connectingSsid = ""
            if (r.ok) root.vpnCancelNeed()
            else if (r.need && r.need.length > 0) {
                root.vpnNeedUuid = uuid
                root.vpnNeedName = name
                root.vpnNeedType = r.type || ""
                root.vpnNeed = r.need             // last: listeners see the fields above
            } else {
                root.vpnCancelNeed()
                root.reportError(r.error || "VPN connection failed")
            }
            root.pollProc.running = true
            root.dataUpdated()
        })
    }
    function vpnCancelNeed() { root.vpnNeed = []; root.vpnNeedUuid = ""; root.vpnNeedName = ""; root.vpnNeedType = "" }
    function vpnLoad(uuid, cb) { root._runHelper("get", { uuid: uuid }, cb) }
    function vpnSave(request, cb) {
        root._runHelper(request.uuid ? "update" : "add", request, r => { if (r.ok) root.vpnProc.running = true; if (cb) cb(r) })
    }
    function vpnImport(type, path, cb) {
        root._runHelper("import", { type: type, path: path }, r => { if (r.ok) root.vpnProc.running = true; if (cb) cb(r) })
    }
    function loadVpnTypes() {
        root._runHelper("types", {}, r => { if (r.ok) { root.vpnTypes = r.types; root.dataUpdated() } })
    }
    function refreshImportCandidates() {
        if (root.importScanProc.running) return
        root.importScanProc.environment = ({ EXTS: VpnSchema.importExtensions(root.vpnTypes).join(" ") })
        root.importScanProc.running = true
    }
    function _runHelper(cmd, request, cb) {
        const done = cb || function () {}
        if (!root.helperAvailable) { done({ ok: false, error: "nm-vpn is not installed — run update" }); return }
        if (root.helperProc.running) { done({ ok: false, error: "Busy — try again" }); return }
        root._helperCb = done
        root._helperResult = null
        root._helperExited = false
        root._helperPayload = JSON.stringify(request || {})
        root.helperProc.command = ["nm-vpn", cmd]
        root.helperProc.running = true
        root.helperWatch.restart()
    }
    // Parses the answer. The callback is not run here: the process is still
    // running, so a callback that starts another request would get "Busy".
    function _helperDone(text) {
        const lines = (text || "").trim().split("\n")
        let r = null
        try { r = JSON.parse(lines[lines.length - 1]) } catch (e) { r = null }
        if (!r || typeof r !== "object") r = { ok: false, error: "nm-vpn gave no answer" }
        root._helperResult = r
        root._helperFinish(false)
    }
    // Runs the callback once, after both the answer and the exit have arrived
    // (force: the process failed to start, so neither will).
    function _helperFinish(force) {
        const cb = root._helperCb
        if (!cb) return
        if (!force && (root._helperResult === null || !root._helperExited || root.helperProc.running)) return
        const r = root._helperResult || { ok: false, error: "nm-vpn could not start" }
        root._helperCb = null
        root._helperResult = null
        root.helperWatch.stop()
        cb(r)
    }
    function vpnDisconnect(uuid) { root.nmVpnDownProc.command = ["nmcli", "connection", "down", "uuid", uuid]; root.nmVpnDownProc.running = true }
    function vpnDelete(uuid) { root.nmVpnDelProc.command = ["nmcli", "connection", "delete", "uuid", uuid]; root.nmVpnDelProc.running = true }
    function refresh() { root.pollProc.running = true; root.knownProc.running = true; root.vpnProc.running = true; if (root.helperAvailable) root.loadVpnTypes() }

    property Process pollProc: Process {
        running: true
        command: ["sh", "-c", "nmcli -t -f DEVICE,TYPE,STATE,CONNECTION device 2>/dev/null; echo '---IP---'; nmcli -t -f IP4.ADDRESS device show 2>/dev/null | head -n 5; echo '---VPN---'; nmcli -t -f NAME,TYPE connection show --active 2>/dev/null | grep -E ':(vpn|wireguard)$' || true; echo '---WIFI---'; nmcli -t -f IN-USE,SIGNAL,SSID device wifi list --rescan no 2>/dev/null | head -n 20; echo '---RADIO---'; nmcli radio wifi"]
        stdout: StdioCollector {
            onStreamFinished: {
                const txt = this.text
                if (!txt || txt.trim().length === 0) { root.available = false; return }
                root.available = true
                const parts = txt.split("---IP---")
                const devSection = parts[0] || ""
                const ipPart = (parts[1] || "").split("---VPN---")[0] || ""
                const vpnPart = (parts[1] || "").split("---VPN---")[1] || ""
                const wifiRaw = (parts[1] || "").split("---WIFI---")[1] || ""
                const wifiPart = wifiRaw.split("---RADIO---")[0] || ""
                const radioPart = wifiRaw.split("---RADIO---")[1] || ""
                if (radioPart.trim() !== "") root.wifiEnabled = radioPart.trim() === "enabled"
                const lines = devSection.trim().split("\n").filter(Boolean)
                let ethName = ""
                let wifiName = ""
                let ethIface = ""
                let wifiIface = ""
                for (const l of lines) {
                    const segs = l.split(":")
                    if (segs.length < 4) continue
                    const dev = segs[0], t = segs[1], state = segs[2], name = segs.slice(3).join(":")
                    if (state.indexOf("connected") === -1) continue
                    if (t === "ethernet") { if (!ethName) { ethName = name; ethIface = dev } }
                    else if (t === "wifi") { if (!wifiName) { wifiName = name; wifiIface = dev } }
                }
                // Ethernet takes precedence when both wired and wifi are connected
                if (ethName !== "") { root.connected = true; root.type = "ethernet"; root.essid = ethName; root.iface = ethIface }
                else if (wifiName !== "") { root.connected = true; root.type = "wifi"; root.essid = wifiName; root.iface = wifiIface }
                else { root.connected = false; root.type = "none"; root.essid = ""; root.iface = ""; root.rxRate = 0; root.txRate = 0 }
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
                if (root.iface !== "" && !root.trafficProc.running) root.trafficProc.running = true
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
        command: ["sh", "-c", "nmcli -t -f NAME,UUID,TYPE connection show 2>/dev/null | grep -E ':(vpn|wireguard)$'"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = this.text.trim().split("\n").filter(Boolean)
                root.vpnConnections = lines.map(l => {
                    const p = root.splitTerse(l)
                    return ({ name: p[0] || "", uuid: p[1] || "", type: p[2] || "", active: false })
                }).filter(v => v.name && v.uuid)
                root.dataUpdated()
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
    property Process nmRadioProc: Process {
        stdout: StdioCollector { onStreamFinished: root.pollProc.running = true }
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

    // nm-vpn is its own package (quickshell/scripts/nm-vpn.nix). Without it,
    // VPNs can still be listed, connected and deleted through nmcli.
    property Process vpnProbe: Process {
        command: ["sh", "-c", "command -v nm-vpn >/dev/null 2>&1 && echo 1 || echo 0"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.helperAvailable = this.text.trim() === "1"
                if (root.helperAvailable) root.loadVpnTypes()
                root.dataUpdated()
            }
        }
    }
    // One nm-vpn request at a time. The JSON request (secrets included) goes
    // to its stdin only and is dropped as soon as it has been written.
    property Process helperProc: Process {
        stdinEnabled: true
        onStarted: {
            root.helperProc.write(root._helperPayload)
            root._helperPayload = ""
            root.helperProc.stdinEnabled = false
        }
        stdout: StdioCollector { onStreamFinished: root._helperDone(this.text) }
        onExited: (exitCode, exitStatus) => {
            root._helperPayload = ""
            root.helperProc.stdinEnabled = true   // ready for the next request
            root._helperExited = true
            Qt.callLater(root._helperFinish, false)   // after `running` has dropped
        }
    }
    // FailedToStart never emits `exited`; `running` still drops to false. If a
    // request is still pending shortly after start and the process is gone,
    // finish it with an error.
    property Timer helperWatch: Timer {
        interval: 1500
        onTriggered: { if (root._helperCb && !root.helperProc.running) root._helperFinish(true) }
    }
    // Config files for the import view, newest first. EXTS holds the
    // extensions vpnSchema.js gives for the installed, import-capable types.
    property Process importScanProc: Process {
        command: ["sh", "-c", 'set --; for e in $EXTS; do [ $# -gt 0 ] && set -- "$@" -o; set -- "$@" -iname "*$e"; done; '
            + '[ $# -eq 0 ] && exit 0; '
            + 'for d in "$HOME/Downloads" "$HOME/Documents"; do [ -d "$d" ] && find "$d" -maxdepth 2 -type f \\( "$@" \\) -printf "%T@ %p\\n" 2>/dev/null; done '
            + '| sort -rn | head -n 200 | cut -d" " -f2-']
        stdout: StdioCollector {
            onStreamFinished: { root.importCandidates = this.text.split("\n").filter(Boolean); root.dataUpdated() }
        }
    }

    // Traffic for the current active connection: totals from /proc/net/dev,
    // rates derived from successive polls (bytes/sec).
    property Process trafficProc: Process {
        command: ["sh", "-c", "cat /proc/net/dev 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                const dev = root.iface
                if (!dev) return
                const lines = this.text.split("\n")
                let rx = -1, tx = -1
                for (let i = 0; i < lines.length; i++) {
                    const line = lines[i].trim()
                    if (line.indexOf(dev + ":") !== 0) continue
                    const fields = line.slice(line.indexOf(":") + 1).trim().split(/\s+/)
                    if (fields.length < 9) return
                    rx = parseFloat(fields[0]); tx = parseFloat(fields[8])
                    break
                }
                if (rx < 0 || tx < 0) return
                const now = Date.now()
                if (root._trafficIface !== dev) {
                    root._trafficIface = dev
                    root._prevRx = rx; root._prevTx = tx; root._prevTs = now
                    root.rxTotal = rx; root.txTotal = tx
                    root.rxRate = 0; root.txRate = 0
                    root.dataUpdated()
                    return
                }
                const dt = (now - root._prevTs) / 1000
                if (root._prevRx >= 0 && dt > 0.3) {
                    let drx = rx - root._prevRx, dtx = tx - root._prevTx
                    if (drx < 0) drx = 0
                    if (dtx < 0) dtx = 0
                    root.rxRate = drx / dt
                    root.txRate = dtx / dt
                    root._prevRx = rx; root._prevTx = tx; root._prevTs = now
                }
                root.rxTotal = rx; root.txTotal = tx
                root.dataUpdated()
            }
        }
    }

    property Timer pollTimer: Timer { interval: 5000; running: true; repeat: true; onTriggered: root.pollProc.running = true }
    property Timer trafficTimer: Timer {
        interval: 2000; running: true; repeat: true
        onTriggered: { if (root.iface !== "" && !root.trafficProc.running) root.trafficProc.running = true }
    }
    Component.onCompleted: { root.knownProc.running = true; root.vpnProc.running = true; root.vpnProbe.running = true }
}
