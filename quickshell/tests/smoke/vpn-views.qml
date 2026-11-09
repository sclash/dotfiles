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
    property var mp: null
    property var fv: null
    property var fv2: null
    property string importedUuid: ""
    property bool fvSaved: false
    property bool loaded: false
    property bool chained: false
    property var nc: null
    property var ncFields: []

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
    function findByName(item, name) {
        if (item.objectName === name) return item
        for (let i = 0; i < item.children.length; i++) {
            const hit = findByName(item.children[i], name)
            if (hit) return hit
        }
        return null
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
            NetworkService.vpnConnect("uuid-l2tp", {}, "split")
        },
        function () {
            check("service: the mode survives the need handshake",
                  NetworkService.vpnNeedMode === "split", NetworkService.vpnNeedMode)
            NetworkService.vpnConnect("uuid-l2tp", { "ipsec-psk": "smoke-secret-1" },
                                      NetworkService.vpnNeedMode)
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
        function () {
            const fv = shell.make("VpnFormView.qml")
            shell.fv = fv
            if (!fv) return
            fv.saved.connect(() => shell.fvSaved = true)
            fv.startAdd("l2tp")
            check("form: l2tp stops in schema order",
                  JSON.stringify(fv.visibleKeys()) === JSON.stringify(["gateway", "user", "password", "ipsec-enabled", "ipsec-psk", "ipsec-gateway-id", "ipv4.never-default"]),
                  JSON.stringify(fv.visibleKeys()))
            const ipsec = fv.stopFor("ipsec-enabled")
            ipsec.checked = false
            ipsec.edited(false)
            check("form: turning IPsec off hides the PSK", fv.visibleKeys().indexOf("ipsec-psk") === -1, JSON.stringify(fv.visibleKeys()))
            fv.save()
            check("form: a missing name blocks Save", fv.formError === "Name is required", fv.formError)
            fv.stopFor("name").edited("Smoke")
            fv.save()
            check("form: a missing gateway blocks Save", fv.formError === "Gateway is required", fv.formError)
            fv.stopFor("gateway").edited("smoke.example.com")
            const pwf = shell.findFields(fv.stopFor("password"), [])
            check("form: the password is a masked field", pwf.length === 1 && pwf[0].input.echoMode === TextInput.Password)
            if (pwf.length === 1) pwf[0].text = "smoke-secret-3"
            fv.save()
            check("form: typed secrets are cleared once handed over", pwf.length === 1 && pwf[0].text === "")
            check("form: busy while saving", fv.busy)
        },
        function () {
            check("form: saved", shell.fvSaved)
            NetworkService.vpnLoad("uuid-l2tp", r => { if (r.ok) { shell.fv.startEdit(r.profile); shell.loaded = true } })
        },
        function () {
            const fv = shell.fv
            if (!fv) return
            check("form: edit is prefilled", shell.loaded && fv.uuid === "uuid-l2tp" && fv.name === "Office" && fv.values.gateway === "vpn.example.com")
            const pwf = shell.findFields(fv.stopFor("password"), [])
            check("form: a saved secret shows a placeholder, never a value",
                  pwf.length === 1 && pwf[0].text === "" && pwf[0].placeholder === "saved · leave empty to keep", pwf.length ? pwf[0].placeholder : "")
            check("form: an Ask secret keeps its mode", fv.stopFor("ipsec-psk").mode === "ask")
            check("form: unknown keys go to Advanced", fv.advanced.some(r => r.key === "lcp-echo-interval"))
            fv.stopFor("user").edited("bob")
            shell.key(fv, Qt.Key_Escape)
            check("form: Esc with changes asks first", fv.confirmText !== "")
            let back = false
            fv.back.connect(() => back = true)
            shell.key(fv, Qt.Key_Y)
            check("form: y discards and goes back", back && fv.type === "")
            fv.destroy()
        },
        function () {
            const f = shell.make("VpnFormView.qml")
            if (!f) return
            shell.fv2 = f
            f.startAdd("l2tp")
            f.stopFor("name").edited("Stale")
            f.reset()
            f.startAdd("l2tp")
            check("form: a reused form clears the Name box", f.stopFor("name").boxText() === "" && f.name === "", f.stopFor("name").boxText())
            f.stopFor("name").edited("X")
            f.stopFor("gateway").edited("g.example.com")
            f.save()
            check("form: a reused form saves a new name", f.formError === "" && f.busy, f.formError)
            f.destroy()
        },
        function () {
            const f = shell.make("VpnFormView.qml")
            if (!f) return
            f.startAdd("l2tp")
            const ps = f.stopFor("ipsec-psk")
            const pf = shell.findFields(ps, [])
            if (pf.length === 1) pf[0].text = "typed-then-ask"
            ps.modeToggled()
            check("form: switching a secret to Ask clears it", ps.asking && pf.length === 1 && pf[0].text === "" && f.collectSecrets()["ipsec-psk"] === undefined, JSON.stringify(f.collectSecrets()))
            f.destroy()
        },
        function () {
            shell.mp = shell.make("VpnModePrompt.qml")
            if (!shell.mp) return
            const got = []
            shell.mp.picked.connect((u, m) => got.push([u, m]))
            shell.mp.open("uuid-l2tp", "Office")
            check("mode prompt: opens at All traffic", shell.mp.visible && shell.mp.selectedMode === "full")
            shell.key(shell.mp, Qt.Key_J)
            check("mode prompt: j selects VPN-only", shell.mp.selectedMode === "split")
            shell.key(shell.mp, Qt.Key_Return)
            check("mode prompt: Enter emits the choice",
                  got.length === 1 && got[0][0] === "uuid-l2tp" && got[0][1] === "split", JSON.stringify(got))
            check("mode prompt: hides after choosing", !shell.mp.visible)
            let cancelled = false
            shell.mp.cancelled.connect(() => cancelled = true)
            shell.mp.open("uuid-l2tp", "Office")
            shell.key(shell.mp, Qt.Key_Escape)
            check("mode prompt: Esc cancels", cancelled && !shell.mp.visible)
            shell.mp.destroy()
        },
        function () {
            check("service: no nm-connection-editor entry points left",
                  typeof NetworkService.launchEditor === "undefined" && typeof NetworkService.vpnAdd === "undefined")
            const c = Qt.createComponent("components/launchers/NetworkCenter.qml")
            check("NetworkCenter.qml compiles", c.status === Component.Ready, c.errorString())
            if (c.status !== Component.Ready) return
            const nc = c.createObject(shell)
            check("NetworkCenter instantiates closed", nc !== null && nc.isOpen === false)
            if (!nc) return
            check("network: starts on the main view", nc.top === "home")
            nc.openAdd()
            check("network: Add VPN opens the type picker", nc.top === "types", nc.top)
            nc.openForm("openvpn")
            check("network: picking a type opens the form above it", nc.top === "form" && nc.stack.length === 2, JSON.stringify(nc.stack))
            check("network: views below the top park left", nc.parkFor("types") === -60 && nc.parkFor("home") === -60 && nc.parkFor("import") === 60)
            nc.popView()
            check("network: Esc returns one level", nc.top === "types")
            nc.resetVpnViews()
            check("network: closing resets the stack", nc.top === "home" && nc.stack.length === 0)
            nc.open()
            nc.openForm("l2tp")
            shell.nc = nc
        },
        function () {                       // the slide has faded in; opening's own helper calls are done
            const nc = shell.nc
            shell.ncFields = shell.findFields(nc.contentItem, []).filter(f => f.visible)   // the form's (others are hidden dialogs)
            for (const f of shell.ncFields) f.text = "typed-secret"
            check("network: the form has masked fields to fill", shell.ncFields.length > 0)
            NetworkService.vpnConnect("uuid-l2tp", {})
        },
        function () {
            const nc = shell.nc
            if (!nc) return
            NetworkService.vpnCancelNeed()
            nc.resetVpnViews()
            nc.view = "vpn"
            nc.updateModels()
            const vpnIdx = nc.navItems.findIndex(it => it.kind === "vpn")
            check("network: /vpn has a selectable VPN", vpnIdx !== -1, JSON.stringify(nc.navItems))
            NetworkService.vpnActive = false
            NetworkService.vpnName = ""
            nc.selIndex = vpnIdx
            nc.activate()
            check("network: activating a VPN opens the mode prompt", nc.modePromptOpen)
            const mp = shell.findByName(nc.contentItem, "vpnModePrompt")
            check("network: the mode prompt is reachable", mp !== null && mp.visible)
            if (mp) { mp.sel = 0; mp.choose() }
        },
        function () {
            const nc = shell.nc
            if (!nc) return
            check("network: the prompt's mode reaches the service",
                  NetworkService.vpnNeedMode === "full", NetworkService.vpnNeedMode)
            NetworkService.vpnCancelNeed()
            nc.resetVpnViews()
            const wgIdx = nc.navItems.findIndex(it => it.kind === "vpn" && nc.filteredVpn[it.idx].type === "wireguard")
            check("network: the list carries the WireGuard profile", wgIdx !== -1, JSON.stringify(nc.navItems))
            nc.selIndex = wgIdx
            nc.activate()
            check("network: WireGuard skips the mode prompt", !nc.modePromptOpen)
            const vpnIdx = nc.navItems.findIndex(it => it.kind === "vpn")
            NetworkService.vpnActive = true
            NetworkService.vpnName = "Office"
            nc.selIndex = vpnIdx
            nc.activate()
            check("network: an active VPN disconnects without the prompt", !nc.modePromptOpen)
            NetworkService.vpnActive = false
            NetworkService.vpnName = ""
            NetworkService.helperAvailable = false
            nc.activate()
            check("network: without nm-vpn the prompt is skipped", !nc.modePromptOpen)
            NetworkService.helperAvailable = true
        },
        function () {
            const nc = shell.nc
            check("network: a secret prompt closes the form views", nc.top === "home" && nc.stack.length === 0, JSON.stringify(nc.stack) + " need=" + JSON.stringify(NetworkService.vpnNeed) + " open=" + nc.isOpen)
            check("network: typed form secrets are cleared when the prompt takes over",
                  shell.ncFields.every(f => f.text !== "typed-secret"))   // a cleared field is "", a rebuilt one is gone
            nc.close()
            nc.destroy()
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
