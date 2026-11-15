import QtQuick
import Quickshell
import Quickshell.Io
import "services"

// Offscreen lifecycle smoke for AirPodsService, run by
// tests/smoke-airpods-lifecycle.sh. A stub systemctl in $tmp/bin logs every
// start/stop and writes a fixture status.json on the first start; a stub
// bluetoothctl reports no devices, so only the panel can want the daemon.
// No real service, no real systemctl and no real AirPods.
//
// Each phase waits for `ready()` before it runs once. The phases walk the
// service through open, close, a failed start, a panel retry and the start
// timeout, so the stub's start/stop log can also be checked in order.
ShellRoot {
    id: shell
    property int failures: 0
    property int phase: 0
    property int tries: 0

    function check(name, cond, detail) {
        console.log((cond ? "SMOKE OK   " : "SMOKE FAIL ") + name + (cond || !detail ? "" : " — " + detail))
        if (!cond) failures++
    }

    function writeStatus(json) {
        writeProc.command = ["sh", "-c", "printf '%s' \"$1\" > \"$2\"", "sh", json, AirPodsService.statePath]
        writeProc.running = true
    }

    function finish() {
        console.log("SMOKE DONE failures=" + shell.failures)
        Qt.quit()
    }

    property var phases: [
        {
            name: "open the panel",
            ready: function () { return !AirPodsService.panelOpen },
            run: function () { AirPodsService.notePanelOpen() }
        },
        {
            name: "the first start writes the status file",
            ready: function () {
                return AirPodsService.daemonActive && !AirPodsService.daemonStarting
            },
            run: function () {
                shell.check("lifecycle: open starts the daemon", AirPodsService.daemonActive)
                shell.check("lifecycle: the fixture is disconnected", !AirPodsService.connected)
                shell.check("lifecycle: a good start is not marked failed", !AirPodsService.startFailed)
            }
        },
        {
            name: "open the panel again while it is open",
            ready: function () { return AirPodsService.panelOpen && AirPodsService.daemonActive },
            run: function () { AirPodsService.notePanelOpen() }
        },
        {
            name: "the second open kept the same daemon",
            ready: function () { return true },
            run: function () {
                shell.check("lifecycle: a second open does not start again", AirPodsService.daemonActive)
            }
        },
        {
            name: "close the panel",
            ready: function () { return AirPodsService.panelOpen && AirPodsService.daemonActive },
            run: function () { AirPodsService.notePanelClosed() }
        },
        {
            name: "close stops the unit when no AirPods are connected",
            ready: function () { return !AirPodsService.daemonActive },
            run: function () {
                shell.check("lifecycle: close stops the daemon", !AirPodsService.daemonActive)
            }
        },
        {
            name: "open for a failing start",
            ready: function () { return !AirPodsService.panelOpen && !AirPodsService.daemonActive },
            run: function () { AirPodsService.notePanelOpen() }
        },
        {
            name: "the failed start is recorded",
            ready: function () { return AirPodsService.startFailed },
            run: function () {
                shell.check("lifecycle: a failed start is marked failed", AirPodsService.startFailed)
                shell.check("lifecycle: a failed start reports systemctl's error",
                            AirPodsService.lifecycleError.indexOf("failed") !== -1,
                            AirPodsService.lifecycleError)
            }
        },
        {
            name: "simulate the next Bluetooth poll",
            ready: function () { return AirPodsService.startFailed && !AirPodsService.lifecycleBusy },
            run: function () {
                BluetoothService.dataUpdated()
                AirPodsService.refresh()
                AirPodsService.reconcile()
            }
        },
        {
            name: "the poll did not retry",
            ready: function () { return true },
            run: function () {
                shell.check("lifecycle: the poll does not retry a failed start",
                            AirPodsService.startFailed && !AirPodsService.daemonStarting,
                            "startFailed=" + AirPodsService.startFailed
                                + " daemonStarting=" + AirPodsService.daemonStarting)
            }
        },
        {
            name: "retry from the panel",
            ready: function () { return AirPodsService.startFailed && !AirPodsService.lifecycleBusy },
            run: function () {
                AirPodsService.notePanelOpen()
                shell.check("lifecycle: a panel retry clears the old error",
                            AirPodsService.lifecycleError === "", AirPodsService.lifecycleError)
            }
        },
        {
            name: "the retry starts but never writes",
            ready: function () {
                return AirPodsService.startFailed
                    && AirPodsService.lifecycleError.indexOf("did not start") !== -1
            },
            run: function () {
                shell.check("lifecycle: the start timeout marks the start failed",
                            AirPodsService.startFailed)
                shell.check("lifecycle: the timeout reports the journal hint",
                            AirPodsService.lifecycleError.indexOf("journalctl") !== -1,
                            AirPodsService.lifecycleError)
                shell.check("lifecycle: the timeout ends the connecting state",
                            !AirPodsService.daemonStarting)
            }
        },
        {
            name: "wait for the timeout stop",
            ready: function () { return !AirPodsService.lifecycleBusy },
            run: function () {}
        },
        {
            name: "write a late status",
            ready: function () { return !AirPodsService.lifecycleBusy },
            run: function () { shell.writeStatus('{"schema_version":1,"connected":false}') }
        },
        {
            name: "the late status is adopted",
            ready: function () { return AirPodsService.daemonActive },
            run: function () {
                shell.check("lifecycle: a late status clears startFailed", !AirPodsService.startFailed)
                shell.check("lifecycle: a late status clears the timeout error",
                            AirPodsService.lifecycleError === "", AirPodsService.lifecycleError)
            }
        },
        {
            name: "close after the late status",
            ready: function () { return AirPodsService.panelOpen && AirPodsService.daemonActive },
            run: function () { AirPodsService.notePanelClosed() }
        },
        {
            name: "the late daemon stops too",
            ready: function () { return !AirPodsService.daemonActive },
            run: function () {
                shell.check("lifecycle: close stops the late daemon", !AirPodsService.daemonActive)
            }
        }
    ]

    function tick() {
        if (shell.phase >= shell.phases.length) return
        const p = shell.phases[shell.phase]
        let ready = false
        try {
            ready = p.ready()
        } catch (e) {
            shell.check(p.name + " ready threw", false, String(e))
            shell.finish()
            return
        }
        if (!ready) {
            if (++shell.tries > 80) {
                shell.check(p.name + " timed out", false, "")
                shell.finish()
            }
            return
        }
        shell.tries = 0
        try {
            p.run()
        } catch (e) {
            shell.check(p.name + " threw", false, String(e))
            shell.finish()
            return
        }
        shell.phase++
        if (shell.phase >= shell.phases.length) shell.finish()
    }

    Timer {
        interval: 100
        repeat: true
        running: true
        onTriggered: shell.tick()
    }

    // Test-only writer: the service reads one status path, so the late-status
    // phase replaces the fixture on disk.
    Process {
        id: writeProc
        command: []
        onExited: AirPodsService.refresh()
    }

    Component.onCompleted: AirPodsService.refresh()
}
