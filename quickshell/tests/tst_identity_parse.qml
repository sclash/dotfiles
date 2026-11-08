import QtQuick
import QtTest
import "../services/identityParse.js" as Parse

// Pure-logic tests for the Identity Manager parsers
// (services/identityParse.js). Headless; no fprintd or reader needed.
TestCase {
    name: "IdentityParse"

    // --- parseEnrolled() ---
    // Formats are from fprintd 1.94.5 utils/list.c.
    function test_parses_enrolled_fingers() {
        const out = Parse.parseEnrolled(
            "found 1 devices\nDevice at /net/reactivated/Fprint/Device/0\n"
            + "Using device /net/reactivated/Fprint/Device/0\n"
            + "Fingerprints for user asergi on Synaptics Sensors (press):\n"
            + " - #0: right-index-finger\n - #1: left-thumb\n")
        compare(out.length, 2)
        compare(out[0], "right-index-finger")
        compare(out[1], "left-thumb")
    }

    function test_no_fingers_is_empty() {
        compare(Parse.parseEnrolled(
            "User asergi has no fingers enrolled for Synaptics Sensors.\n").length, 0)
    }

    function test_garbage_is_empty() {
        compare(Parse.parseEnrolled("").length, 0)
        compare(Parse.parseEnrolled("totally unrelated output").length, 0)
    }

    // --- listError() ---
    function test_no_device_error() {
        compare(Parse.listError("No devices available\n"), "nodevice")
    }
    function test_daemon_errors() {
        compare(Parse.listError("Impossible to get devices: GDBus.Error:org.freedesktop.DBus.Error.ServiceUnknown\n"), "daemon")
        compare(Parse.listError("Failed to connect to session bus: x\n"), "daemon")
        compare(Parse.listError("Failed to get Fprintd manager: x\n"), "daemon")
    }
    function test_list_failure() {
        compare(Parse.listError("ListEnrolledFingers failed: x\n"), "listfail")
    }
    function test_no_error_on_normal_output() {
        compare(Parse.listError("Fingerprints for user asergi on X (press):\n - #0: right-thumb\n"), "")
    }

    // --- parseAuthEnabled() ---
    function test_absent_means_enabled() {
        compare(Parse.parseAuthEnabled("ABSENT"), true)
        compare(Parse.parseAuthEnabled(""), true)
        compare(Parse.parseAuthEnabled("garbage"), true)
    }
    function test_reads_enabled_values() {
        compare(Parse.parseAuthEnabled("auth {\n    fingerprint {\n        enabled = false\n    }\n}\n"), false)
        compare(Parse.parseAuthEnabled("auth {\n    fingerprint {\n        enabled = true\n    }\n}\n"), true)
        compare(Parse.parseAuthEnabled("enabled = 0"), false)
        compare(Parse.parseAuthEnabled("enabled = 1"), true)
    }

    // --- enrollStageLabel() ---
    function test_stage_labels() {
        compare(Parse.enrollStageLabel("enroll-stage-passed"), "Stage passed - lift and place again")
        compare(Parse.enrollStageLabel("enroll-retry-scan"), "Please retry fingerprint scan")
        compare(Parse.enrollStageLabel("enroll-swipe-too-short"), "Swipe too short - try again")
        compare(Parse.enrollStageLabel("enroll-finger-not-centered"), "Finger not centered - try again")
        compare(Parse.enrollStageLabel("enroll-remove-and-retry"), "Remove your finger and try again")
        compare(Parse.enrollStageLabel("enroll-too-fast"), "Too fast - try again")
        compare(Parse.enrollStageLabel("enroll-completed"), "Enrolled")
        compare(Parse.enrollStageLabel("enroll-failed"), "Enrollment failed")
        compare(Parse.enrollStageLabel("enroll-duplicate"), "Finger already enrolled")
        compare(Parse.enrollStageLabel("enroll-data-full"), "Fingerprint storage full")
        compare(Parse.enrollStageLabel("enroll-disconnected"), "Device disconnected")
        compare(Parse.enrollStageLabel("enroll-unknown-error"), "Unknown error")
    }
    function test_unknown_stage_passthrough() {
        compare(Parse.enrollStageLabel("enroll-what"), "enroll-what")
    }

    // --- fingerLabel() / FINGERS ---
    function test_finger_labels() {
        compare(Parse.fingerLabel("right-index-finger"), "Right Index Finger")
        compare(Parse.fingerLabel("left-thumb"), "Left Thumb")
        compare(Parse.fingerLabel("weird"), "weird")
    }
    function test_fingers_list() {
        compare(Parse.FINGERS.length, 10)
        verify(Parse.FINGERS.indexOf("right-index-finger") !== -1)
        verify(Parse.FINGERS.indexOf("left-little-finger") !== -1)
    }
}
