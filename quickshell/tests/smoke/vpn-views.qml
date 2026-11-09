import QtQuick
import Quickshell
import "services"
import "components/launchers/network"   // scanned so the views find sibling components (VpnRow, ...)
import "components/launchers"           // SecretField
// Views are created by path (make() and Qt.createComponent).

// Smoke test for NetworkService's VPN API and the Network Center VPN views,
// run inside Quickshell from a temporary config root (see
// tests/smoke-vpn-views.sh: stub nm-vpn and nmcli, temporary HOME). Steps
// run one per timer tick so helper calls can finish in between. Prints one
// `SMOKE OK|FAIL <name>` line per check, then `SMOKE DONE`, and quits.
ShellRoot {
    id: shell
    property int failures: 0
    property int step: 0
    property var tv: null
    property var iv: null
    property var sp: null
    property var fv: null
    property string importedUuid: ""
    property bool fvSaved: false
    property bool loaded: false
    property bool chained: false

    function check(name, cond, detail) {
        console.log((cond ? "SMOKE OK   " : "SMOKE FAIL ") + name + (cond || !detail ? "" : " — " + detail))
        if (!cond) failures++
    }
    function make(file) {
        const c = Qt.createComponent("components/launchers/network/" + file)
        if (c.status !== Component.Ready) { check(file + " loads", false, c.errorString()); return null }
        const o = c.createObject(win.contentItem, { width: 600 })
        check(file + " instantiates", o !== null)
        return o
    }
    function key(view, k) {
        const e = { key: k, text: "", modifiers: 0, accepted: false }
        view.handleKey(e)
        return e.accepted
    }
    function findFields(item, out) {
        for (let i = 0; i < item.children.length; i++) {
            const ch = item.children[i]
            if (ch.hasOwnProperty("placeholder") && ch.hasOwnProperty("input")) out.push(ch)
            findFields(ch, out)
        }
        return out
    }

    property var steps: [
        function () {
            check("service: nm-vpn found on PATH", NetworkService.helperAvailable)
            check("service: types loaded from nm-vpn", NetworkService.vpnTypes.length === 4, JSON.stringify(NetworkService.vpnTypes))
            check("service: the VPN list carries the type",
                  NetworkService.vpnConnections.some(v => v.name === "Home WG" && v.type === "wireguard"),
                  JSON.stringify(NetworkService.vpnConnections))
            check("service: Wi-Fi profiles are not VPNs", !NetworkService.vpnConnections.some(v => v.name === "Cafe"))
            NetworkService.vpnConnect("uuid-l2tp", {})
        },
        function () {
            check("service: Ask secrets come back as need",
                  NetworkService.vpnNeed.length === 1 && NetworkService.vpnNeed[0] === "ipsec-psk", JSON.stringify(NetworkService.vpnNeed))
            check("service: need names the profile",
                  NetworkService.vpnNeedUuid === "uuid-l2tp" && NetworkService.vpnNeedName === "Office" && NetworkService.vpnNeedType === "l2tp")
            check("service: not connecting while it asks", !NetworkService.connecting)
            NetworkService.vpnConnect("uuid-l2tp", { "ipsec-psk": "smoke-secret-1" })
        },
        function () {
            check("service: need cleared once connected", NetworkService.vpnNeed.length === 0)
            NetworkService.refreshImportCandidates()
        },
        function () {
            const c = NetworkService.importCandidates
            check("service: import candidates found",
                  c.some(p => p.endsWith("/Downloads/office.ovpn")) && c.some(p => p.endsWith("/Downloads/wg0.conf")), JSON.stringify(c))
            check("service: other files are not candidates", !c.some(p => p.endsWith("notes.txt")))
        },
        function () {
            const c = NetworkService.importCandidates.filter(p => p.endsWith("/Downloads/office.ovpn"))[0]
            NetworkService.vpnImport("openvpn", c, r => NetworkService.vpnLoad(r.uuid, r2 => { shell.chained = r2.ok === true }))
        },
        function () {
            check("service: a callback can start the next helper request", shell.chained)
        },
        function () {
            const tv = shell.make("VpnTypeView.qml")
            if (!tv) return
            check("types: Import first, then 4 types", tv.rows.length === 5 && tv.rows[0].kind === "import", JSON.stringify(tv.rows))
            const last = tv.rows[tv.rows.length - 1]
            check("types: advanced-only types last", last.name === "fortisslvpn" && last.note === "advanced", JSON.stringify(last))
            let picked = ""
            tv.pickType.connect(n => picked = n)
            shell.key(tv, Qt.Key_J)
            shell.key(tv, Qt.Key_Return)
            check("types: j + Enter picks a type", picked === tv.rows[1].name, picked)
            let asked = false
            tv.importRequested.connect(() => asked = true)
            shell.key(tv, Qt.Key_K)
            shell.key(tv, Qt.Key_Return)
            check("types: Enter on Import asks for a file", asked)
            let back = false
            tv.back.connect(() => back = true)
            shell.key(tv, Qt.Key_Escape)
            check("types: Esc goes back", back)
            tv.destroy()
            shell.iv = shell.make("VpnImportView.qml")
            if (shell.iv) shell.iv.imported.connect(u => shell.importedUuid = u)
        },
        function () {
            const iv = shell.iv
            if (!iv) return
            check("import: lists the two candidates", iv.files.length === 2, JSON.stringify(iv.files))
            iv.sel = iv.files.findIndex(p => p.endsWith(".ovpn"))
            shell.key(iv, Qt.Key_Return)            // only OpenVPN claims .ovpn: imports at once
        },
        function () {
            const iv = shell.iv
            if (!iv) return
            check("import: .ovpn imports as OpenVPN at once", shell.importedUuid === "uuid-imported", shell.importedUuid)
            iv.sel = iv.files.findIndex(p => p.endsWith(".conf"))
            shell.key(iv, Qt.Key_Return)
            check("import: .conf asks which type", iv.choosingPath.endsWith("wg0.conf") && iv.typeChoices.length === 2,
                  JSON.stringify(iv.typeChoices))
            shell.key(iv, Qt.Key_Escape)
            check("import: Esc leaves the type question", iv.choosingPath === "")
            let back = false
            iv.back.connect(() => back = true)
            shell.key(iv, Qt.Key_Escape)
            check("import: a second Esc goes back", back)
            iv.destroy()
            shell.sp = shell.make("VpnSecretPrompt.qml")
            NetworkService.vpnConnect("uuid-l2tp", {})
        },
        function () {
            const sp = shell.sp
            if (!sp) return
            const f = shell.findFields(sp, [])
            check("prompt: one masked field per Ask secret", sp.visible && f.length === 1 && f[0].input.echoMode === TextInput.Password,
                  "visible=" + sp.visible + " fields=" + f.length)
            check("prompt: labelled from the schema", f.length === 1 && f[0].placeholder === "Pre-shared key", f.length ? f[0].placeholder : "")
            if (f.length === 1) {
                f[0].text = "smoke-secret-2"
                sp.submit()
                check("prompt: field cleared on submit", f[0].text === "")
            }
        },
        function () {
            check("prompt: hidden once connected", shell.sp !== null && !shell.sp.visible)
            if (shell.sp) shell.sp.destroy()
        },
        // --- view checks are added below by later tasks ---
        function () {
            console.log("SMOKE DONE failures=" + shell.failures)
            Qt.quit()
        }
    ]

    FloatingWindow {
        id: win
        visible: true
        implicitWidth: 620
        implicitHeight: 640
    }

    // The singleton is created on first use: start its probes now and give
    // them time before the first step (the real shell touches it at startup).
    Component.onCompleted: NetworkService.refresh()
    Timer {
        interval: 1000
        repeat: true
        running: true
        onTriggered: { const f = shell.steps[shell.step++]; if (f) f() }
    }
}
