import QtQuick
import QtTest
import "../services/powerProfileRule.js" as Rule

// Pure-logic tests for the power-profile auto rule (services/powerProfileRule.js).
// Inputs mirror the fields the service reads from BatteryService/PowerProfiles;
// `onAc` is plugged || charging; `low` is the hysteresis latch (true once the
// battery dropped to <= 20 on battery).
TestCase {
    name: "PowerProfileRule"

    function o(onAc, capacity, hasPerformance, available) {
        return {
            available: available === undefined ? true : available,
            onAc: onAc,
            capacity: capacity,
            hasPerformance: hasPerformance === undefined ? true : hasPerformance
        }
    }

    // --- target() ---

    function test_on_ac_is_performance() {
        compare(Rule.target(o(true, 80), false), "performance")
    }

    function test_on_ac_without_performance_profile_is_balanced() {
        compare(Rule.target(o(true, 80, false), false), "balanced")
    }

    function test_no_battery_is_performance() {
        compare(Rule.target(o(false, -1, true, false), false), "performance")
    }

    function test_on_battery_mid_is_balanced() {
        compare(Rule.target(o(false, 50), false), "balanced")
    }

    function test_on_battery_at_20_is_power_saver() {
        compare(Rule.target(o(false, 20), false), "power-saver")
    }

    function test_on_battery_21_not_latched_is_balanced() {
        compare(Rule.target(o(false, 21), false), "balanced")
    }

    function test_on_battery_22_latched_stays_power_saver() {
        compare(Rule.target(o(false, 22), true), "power-saver")
    }

    function test_on_battery_25_latched_recovers_to_balanced() {
        compare(Rule.target(o(false, 25), true), "balanced")
    }

    function test_unknown_capacity_is_balanced() {
        compare(Rule.target(o(false, -1), true), "balanced")
    }

    // --- latch() ---

    function test_latch_sets_at_20_on_battery() {
        verify(Rule.latch(o(false, 20), false))
    }

    function test_latch_holds_above_20_on_battery() {
        verify(Rule.latch(o(false, 22), true))
    }

    function test_latch_clears_on_ac() {
        verify(!Rule.latch(o(true, 10), true))
    }

    function test_latch_stays_off_mid_battery() {
        verify(!Rule.latch(o(false, 50), false))
    }
}
