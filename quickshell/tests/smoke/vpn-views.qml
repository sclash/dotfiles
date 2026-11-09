import QtQuick
import Quickshell
import "services"
// Views are created by path (make() and Qt.createComponent), so the
// components/launchers/network directory needs no import here and may not
// exist yet when this file is first added (Task 6).

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
