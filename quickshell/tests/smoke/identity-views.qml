import QtQuick
import Quickshell
import "services"
import "components/launchers/identity" // scanned the way IdentityManager.qml imports it

// Smoke test for the Identity Manager views, run inside Quickshell itself
// from a temporary config root holding copies of components/, services/
// and theme/ (Quickshell only loads files under its config root, and its
// modules are built into the binary, so qmltestrunner cannot load
// them). Driven by tests/smoke-identity-views.sh with QT_QPA_PLATFORM=offscreen
// and a temporary HOME. Prints one `SMOKE OK|FAIL <name>` line per check,
// then `SMOKE DONE`, and quits. Machine-dependent values are not asserted.
ShellRoot {
    id: shell
    property int failures: 0

    function check(name, cond, detail) {
        console.log((cond ? "SMOKE OK   " : "SMOKE FAIL ") + name + (cond || !detail ? "" : " — " + detail))
        if (!cond) failures++
    }
    function make(file) {
        const c = Qt.createComponent("components/launchers/identity/" + file)
        if (c.status !== Component.Ready) {
            check(file + " loads", false, c.errorString())
            return null
        }
        const o = c.createObject(win.contentItem, { width: 600 })
        check(file + " instantiates", o !== null)
        return o
    }
    function key(view, k) {
        const e = { key: k, text: "", accepted: false }
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

    function run() {
        // --- MethodsView ---
        const m = make("MethodsView.qml")
        if (m) {
            check("methods: has height", m.implicitHeight > 0, "implicitHeight=" + m.implicitHeight)
            key(m, Qt.Key_J)
            check("methods: j moves down", m.sel === 1)
            key(m, Qt.Key_End)
            check("methods: End selects fingerprint", m.sel === 2)
            let opened = ""
            m.openMethod.connect(n => opened = n)
            key(m, Qt.Key_Return)
            check("methods: Enter opens the method", opened === "fingerprint", opened)
            let closed = false
            m.closeRequested.connect(() => closed = true)
            key(m, Qt.Key_Escape)
            check("methods: Esc closes", closed)
            m.destroy()
        }

        // --- PasswordView ---
        const p = make("PasswordView.qml")
        if (p) {
            check("password: has height", p.implicitHeight > 0)
            const f = findFields(p, [])
            check("password: three masked fields", f.length === 3 && f.every(x => x.input.echoMode === TextInput.Password), "fields=" + f.length)
            if (f.length === 3) {
                f[0].text = "old-secret"; f[1].text = "new-secret-1"; f[2].text = "new-secret-2"
                p.submit()
                if (IdentityService.passwordAvailable) {
                    check("password: mismatch is refused", p.formError === "The new passwords do not match", p.formError)
                    check("password: confirm cleared on mismatch", f[2].text === "")
                    check("password: nothing sent to passwd", !IdentityService.passwordBusy && IdentityService.passwordMessage === "")
                } else {
                    check("password: submit is inert without identity-passwd", !IdentityService.passwordBusy)
                }
                p.reset()
                check("password: reset clears every field", f.every(x => x.text === ""))
            }
            let back = false
            p.back.connect(() => back = true)
            key(p, Qt.Key_Escape)
            check("password: Esc goes back", back)
            p.destroy()
        }

        // --- FaceView ---
        const fv = make("FaceView.qml")
        if (fv) {
            check("face: has height", fv.implicitHeight > 0)
            fv.reset()
            check("face: starts in list mode", fv.mode === "list")
            check("face: unavailable state matches service", fv.available === (IdentityService.faceState !== "unavailable"))
            let back = false
            fv.back.connect(() => back = true)
            key(fv, Qt.Key_Escape)
            check("face: Esc goes back", back)
            fv.destroy()
        }

        // --- FingerprintView ---
        const fp = make("FingerprintView.qml")
        if (fp) {
            check("fingerprint: has height", fp.implicitHeight > 0)
            fp.reset()
            check("fingerprint: toggle row first", fp.navItems.length >= 1 && fp.navItems[0].kind === "toggle")
            if (IdentityService.fingerprintState === "unavailable") {
                const before = IdentityService.choices.fingerprint
                key(fp, Qt.Key_T)
                check("fingerprint: toggle inert without a reader", IdentityService.choices.fingerprint === before)
            }
            let back = false
            fp.back.connect(() => back = true)
            key(fp, Qt.Key_Escape)
            check("fingerprint: Esc goes back", back)
            fp.destroy()
        }

        // --- the launcher shell (layer surface; created closed, never shown) ---
        const lc = Qt.createComponent("components/launchers/IdentityManager.qml")
        check("IdentityManager.qml compiles", lc.status === Component.Ready, lc.errorString())
        if (lc.status === Component.Ready) {
            const l = lc.createObject(shell)
            check("IdentityManager instantiates closed", l !== null && l.isOpen === false)
            if (l) l.destroy()
        }

        console.log("SMOKE DONE failures=" + failures)
        Qt.quit()
    }

    FloatingWindow {
        id: win
        visible: true
        implicitWidth: 620
        implicitHeight: 640
    }

    // The singleton is created on first use; start its probe now and let it
    // finish before checking views (the real shell touches it at startup).
    Component.onCompleted: IdentityService.refresh()
    // A choice written through the service; smoke-identity-views.sh checks
    // the files it produces in the temporary HOME.
    Timer { interval: 1200; running: true; onTriggered: IdentityService.setChoice("face", false) }
    Timer { interval: 3000; running: true; onTriggered: shell.run() }
}
