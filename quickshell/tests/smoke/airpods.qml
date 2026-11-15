import QtQuick
import Quickshell
import Quickshell.Io
import "services"
import "services/airPodsParse.js" as Parse

// Smoke test for AirPodsService, run inside Quickshell from a temporary config
// root (see tests/smoke-airpods.sh: fixture status.json, stub librepods-ctl,
// lifecycle disabled). Steps run one per timer tick so each ctl verb finishes
// before the next is sent. Prints one `SMOKE OK|FAIL <name>` line per check,
// then `SMOKE DONE`, and quits.
ShellRoot {
    id: shell
    property int failures: 0
    property int step: 0
    property var view: null

    readonly property string headsetFixture: '{"schema_version":1,"connected":true,"device_name":"Test Max","model_name":"AirPods Max","model_number":"A3184","is_headset":true,"headset":{"available":true,"charging":false,"level":88}}'
    readonly property string headsetOffFixture: '{"schema_version":1,"connected":false,"device_name":"Test Max","model_name":"AirPods Max","model_number":"A3184","is_headset":true,"headset":{"available":false,"charging":false,"level":0}}'

    function check(name, cond, detail) {
        console.log((cond ? "SMOKE OK   " : "SMOKE FAIL ") + name + (cond || !detail ? "" : " — " + detail))
        if (!cond) failures++
    }

    // The service reads one status path, so the second device shape replaces
    // the fixture on disk; refresh() runs after the write finishes.
    function writeStatus(json) {
        writeProc.command = ["sh", "-c", "printf '%s' \"$1\" > \"$2\"", "sh", json, AirPodsService.statePath]
        writeProc.running = true
    }

    property var steps: [
        function () {
            check("service: fixture loaded", AirPodsService.daemonActive && AirPodsService.connected)
            check("service: reachable", AirPodsService.daemonReachable)
            check("service: model", AirPodsService.modelName === "AirPods 5" && AirPodsService.modelNumber === "A3439")
            check("service: battery", AirPodsService.leftPod.level === 93 && AirPodsService.rightPod.level === 97
                  && AirPodsService.caseBattery.level === 82)
            check("service: in-ear/charging", AirPodsService.leftPod.inEar && AirPodsService.rightPod.charging)
            check("service: battery known", AirPodsService.hasAirPods && AirPodsService.hasBattery)
            check("service: noise mode", AirPodsService.noiseMode === 3)
            check("service: modes", AirPodsService.availableModes().length === 4,
                  JSON.stringify(AirPodsService.availableModes()))
        },
        function () {
            AirPodsService.setAdaptiveNoiseLevel(65)
            check("service: adaptive level is optimistic", AirPodsService.adaptiveNoiseLevel === 65)
        },
        function () {
            check("service: adaptive level sent", AirPodsService.actionStatus === "adaptive:65" && !AirPodsService.busy,
                  AirPodsService.actionStatus)
            AirPodsService.setConversationalAwareness(true)
        },
        function () {
            check("service: CA sent", AirPodsService.actionStatus === "ca:on", AirPodsService.actionStatus)
            AirPodsService.setOneBudANC(true)
        },
        function () {
            check("service: one-bud sent", AirPodsService.actionStatus === "onebud:on", AirPodsService.actionStatus)
            AirPodsService.setEarDetectionBehavior(1)
        },
        function () {
            check("service: ctl failure surfaces", AirPodsService.lastError.indexOf("stub failure") !== -1,
                  AirPodsService.lastError)
        },
        // The view is created by path, like the VPN smoke creates its views.
        // Its `n` key is the producer of the smoke's `noise:anc` verb.
        function () {
            const c = Qt.createComponent("components/launchers/airpods/AirPodsView.qml")
            const view = c.status === Component.Ready
                ? c.createObject(win.contentItem, { width: 600, height: 640 })
                : null
            shell.view = view
            check("view: loads", view !== null, c.errorString())
            if (!view) return
            check("view: nav order",
                  view.navItems.map(i => i.kind).join(",")
                      === "mode,mode,mode,mode,adaptive,ca,onebud,ear,refresh",
                  JSON.stringify(view.navItems))
            check("view: mode labels",
                  view.navItems.filter(i => i.kind === "mode").map(i => i.label).join(",")
                      === "Off,Transparency,Adaptive,Noise Cancellation")
            view.handleKey({ key: Qt.Key_J, text: "j", modifiers: 0, accepted: false })
            check("view: j moves the cursor", view.selIndex === 1)
            view.handleKey({ key: Qt.Key_N, text: "n", modifiers: 0, accepted: false })
            view.handleKey({ key: Qt.Key_B, text: "b", modifiers: 0, accepted: false })
            view.handleKey({ key: Qt.Key_E, text: "e", modifiers: 0, accepted: false })
            view.handleKey({ key: Qt.Key_Slash, text: "/", modifiers: 0, accepted: false })
            check("view: filter opens", view.filterActive)
            let closed = false
            view.closeRequested.connect(() => closed = true)
            view.handleKey({ key: Qt.Key_Escape, text: "", modifiers: 0, accepted: false })
            check("view: Esc clears the filter", !view.filterActive && !closed)
            view.handleKey({ key: Qt.Key_Escape, text: "", modifiers: 0, accepted: false })
            check("view: second Esc closes", closed)
        },
        // The bar badge, also created by path. The fixture's lowest known
        // level is the case at 82 %.
        function () {
            const c = Qt.createComponent("components/bar/AirPodsIcon.qml")
            const badge = c.status === Component.Ready
                ? c.createObject(win.contentItem)
                : null
            check("badge: loads", badge !== null, c.errorString())
            if (!badge) return
            check("badge: visible with battery", badge.visible)
            check("badge: lowest level is the case", badge.lowestLevel === 82)
            check("badge: text carries the percentage", badge.batteryText.indexOf("82%") !== -1)
        },
        // A headset has one battery row, connected or not; the second fixture
        // is a readable disconnect that still says is_headset true.
        function () {
            shell.writeStatus(shell.headsetFixture)
        },
        function () {
            check("service: headset fixture adopted",
                  AirPodsService.isHeadset && AirPodsService.connected,
                  "isHeadset=" + AirPodsService.isHeadset + " connected=" + AirPodsService.connected)
        },
        function () {
            const rows = shell.view.batteryRows
            check("view: connected headset has one row",
                  rows.length === 1 && rows[0].label === "Headset", JSON.stringify(rows))
            check("view: connected headset level",
                  rows.length === 1 && rows[0].level === 88, JSON.stringify(rows))
        },
        function () {
            shell.writeStatus(shell.headsetOffFixture)
        },
        function () {
            check("service: disconnected headset keeps isHeadset",
                  AirPodsService.isHeadset && !AirPodsService.connected,
                  "isHeadset=" + AirPodsService.isHeadset + " connected=" + AirPodsService.connected)
        },
        function () {
            const rows = shell.view.batteryRows
            check("view: disconnected headset has one row",
                  rows.length === 1 && rows[0].label === "Headset", JSON.stringify(rows))
            check("view: disconnected headset level is --",
                  rows.length === 1 && rows[0].level === Parse.LEVEL_UNKNOWN
                      && Parse.levelText(rows[0].level) === "--",
                  JSON.stringify(rows))
        },
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

    // The headset fixtures replace the status file in place.
    Process {
        id: writeProc
        command: []
        onExited: AirPodsService.refresh()
    }

    Timer {
        interval: 1000
        repeat: true
        running: true
        onTriggered: {
            const at = shell.step++
            const f = shell.steps[at]
            if (!f) return
            // A missing singleton throws here; count it instead of ending with
            // a clean-looking SMOKE DONE failures=0.
            try {
                f()
            } catch (e) {
                shell.check("step " + at + " threw", false, String(e))
            }
        }
    }

    // The singleton is created on first use: instantiate it now and load the
    // fixture before the first step.
    Component.onCompleted: AirPodsService.refresh()
}
