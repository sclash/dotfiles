import QtQuick
import QtTest
import "../services/airPodsLifecycle.js" as Lifecycle

TestCase {
    name: "AirPodsLifecycle"
    function test_runs_when_airpods_connected() { compare(Lifecycle.shouldRun(true, false, false), true) }
    function test_runs_when_panel_open() { compare(Lifecycle.shouldRun(false, true, false), true) }
    function test_runs_when_status_still_connected() { compare(Lifecycle.shouldRun(false, false, true), true) }
    function test_idle_when_nothing_wants_it() { compare(Lifecycle.shouldRun(false, false, false), false) }
    function test_start_when_wanted_and_inactive() { compare(Lifecycle.nextAction(true, false), "start") }
    function test_stop_when_unwanted_and_active() { compare(Lifecycle.nextAction(false, true), "stop") }
    function test_none_when_in_sync() { compare(Lifecycle.nextAction(true, true), "none"); compare(Lifecycle.nextAction(false, false), "none") }
}
