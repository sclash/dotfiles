import QtQuick
import Quickshell
import "services"

// Smoke test for AirPodsService, run inside Quickshell from a temporary config
// root (see tests/smoke-airpods.sh: fixture status.json, stub librepods-ctl,
// lifecycle disabled). Steps run one per timer tick so each ctl verb finishes
// before the next is sent. Prints one `SMOKE OK|FAIL <name>` line per check,
// then `SMOKE DONE`, and quits.
ShellRoot {
    id: shell
    property int failures: 0
    property int step: 0

    function check(name, cond, detail) {
        console.log((cond ? "SMOKE OK   " : "SMOKE FAIL ") + name + (cond || !detail ? "" : " — " + detail))
        if (!cond) failures++
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
        function () {
            console.log("SMOKE DONE failures=" + shell.failures)
            Qt.quit()
        }
    ]

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
