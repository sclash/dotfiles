import QtQuick
import QtTest
import "../services/lowBatteryRule.js" as Rule

// Pure-logic tests for the low-battery hibernate prompt (services/lowBatteryRule.js).
TestCase {
    name: "LowBatteryRule"

    function o(discharging, minutes, capacity, available) {
        return {
            available: available === undefined ? true : available,
            discharging: discharging,
            minutes: minutes,
            capacity: capacity
        }
    }

    // --- dismissed() latch ---

    function test_dismiss_holds_while_discharging() {
        compare(Rule.dismissed(o(true, 3, 4), true), true)
    }

    function test_dismiss_rearms_on_ac() {
        compare(Rule.dismissed(o(false, -1, 4), true), false)
    }

    function test_dismiss_rearms_without_battery() {
        compare(Rule.dismissed(o(true, 3, 4, false), true), false)
    }

    // --- shown() gating ---

    function test_never_shown_without_hibernate() {
        compare(Rule.shown(o(true, 1, 1), false, false), false)
    }

    function test_never_shown_on_ac() {
        compare(Rule.shown(o(false, 1, 1), false, true), false)
    }

    function test_never_shown_when_dismissed() {
        compare(Rule.shown(o(true, 1, 1), true, true), false)
    }

    function test_unknown_readings_never_critical() {
        compare(Rule.critical(o(true, -1, -1)), false)
    }

    function test_healthy_battery_not_critical() {
        compare(Rule.critical(o(true, 180, 80)), false)
    }

    // --- critical() thresholds ---

    function test_percent_floor_fires_without_estimate() {
        compare(Rule.critical(o(true, -1, 5)), true)
    }

    function test_just_above_percent_floor_without_estimate() {
        compare(Rule.critical(o(true, -1, 6)), false)
    }

    function test_few_minutes_left_under_gate_fires() {
        compare(Rule.critical(o(true, 5, 15)), true)
    }

    function test_load_spike_above_gate_does_not_fire() {
        compare(Rule.critical(o(true, 2, 40)), false)
    }

    function test_enough_minutes_under_gate_does_not_fire() {
        compare(Rule.critical(o(true, 6, 10)), false)
    }

    function test_minutes_with_unknown_capacity_does_not_fire() {
        compare(Rule.critical(o(true, 3, -1)), false)
    }

    function test_low_but_charging_never_critical() {
        compare(Rule.critical(o(false, 2, 3)), false)
    }

    function test_critical_and_hibernate_possible_is_shown() {
        compare(Rule.shown(o(true, 3, 4), false, true), true)
    }
}
