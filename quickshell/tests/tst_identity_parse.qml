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

    // --- parseChoices() / renderChoices() ---
    // ~/.local/state/identity/choices: `method=on|off`; a missing key means
    // "follow the hardware default".
    function test_choices_absent_or_garbage_are_defaults() {
        const c = Parse.parseChoices("")
        compare(c.fingerprint, "")
        compare(c.face, "")
        compare(Parse.parseChoices("ABSENT").face, "")
        compare(Parse.parseChoices("face=maybe\nnonsense\n").face, "")
    }
    function test_choices_read_values_last_wins() {
        const c = Parse.parseChoices("fingerprint=off\nface=on\nface=off\n")
        compare(c.fingerprint, "off")
        compare(c.face, "off")
        compare(Parse.parseChoices(" face = on \n").face, "on")
    }
    function test_choices_round_trip() {
        const text = Parse.renderChoices({ fingerprint: "off", face: "" })
        compare(text, "fingerprint=off\n")
        compare(Parse.parseChoices(text).fingerprint, "off")
        compare(Parse.renderChoices({ fingerprint: "", face: "" }), "")
    }

    // --- methodState() ---
    function test_method_state() {
        compare(Parse.methodState(false, ""), "unavailable")
        compare(Parse.methodState(false, "on"), "unavailable")
        compare(Parse.methodState(true, ""), "enabled")      // hardware default
        compare(Parse.methodState(true, "on"), "enabled")
        compare(Parse.methodState(true, "off"), "disabled")
    }

    // --- effectiveAuth() ---
    function eff(over) {
        return Parse.effectiveAuth(Object.assign({
            fingerprintPresent: false, fingerprintChoice: "",
            irPresent: false, faceChoice: "", faceModelCount: 0
        }, over))
    }
    function test_effective_nothing_present() {
        const e = eff({})
        compare(e.fingerprint, false)
        compare(e.pamModule, "hyprlock")
        compare(e.face, false)
    }
    function test_effective_fingerprint_default_on_when_present() {
        compare(eff({ fingerprintPresent: true }).fingerprint, true)
        compare(eff({ fingerprintPresent: true, fingerprintChoice: "off" }).fingerprint, false)
        compare(eff({ fingerprintPresent: false, fingerprintChoice: "on" }).fingerprint, false)
    }
    function test_effective_face_needs_camera_choice_and_a_model() {
        compare(eff({ irPresent: true, faceModelCount: 1 }).pamModule, "hyprlock-face")
        compare(eff({ irPresent: true, faceModelCount: 1 }).face, true)
        compare(eff({ irPresent: true, faceModelCount: 0 }).pamModule, "hyprlock")
        compare(eff({ irPresent: true, faceModelCount: 2, faceChoice: "off" }).pamModule, "hyprlock")
        compare(eff({ irPresent: false, faceModelCount: 2, faceChoice: "on" }).pamModule, "hyprlock")
    }

    // --- renderHyprlockAuth() ---
    function test_render_hyprlock_password_only() {
        const t = Parse.renderHyprlockAuth({ fingerprint: false, pamModule: "hyprlock", face: false })
        verify(t.indexOf("enabled = false") !== -1)
        verify(t.indexOf("module = hyprlock\n") !== -1)
        verify(t.indexOf("label {") === -1)
    }
    function test_render_hyprlock_face_and_fingerprint() {
        const t = Parse.renderHyprlockAuth({ fingerprint: true, pamModule: "hyprlock-face", face: true })
        verify(t.indexOf("enabled = true") !== -1)
        verify(t.indexOf("module = hyprlock-face") !== -1)
        verify(t.indexOf("label {") !== -1)          // "press Enter" hint
        verify(t.indexOf("Enter") !== -1)
    }

    // --- parseHowdyDevicePath() ---
    function test_howdy_device_path() {
        compare(Parse.parseHowdyDevicePath("[core]\ndisabled=false\n\n[video]\ncertainty=3.5\ndevice_path=/dev/v4l/ir0\n"), "/dev/v4l/ir0")
        compare(Parse.parseHowdyDevicePath("[video]\ndevice_path = /dev/video2\n"), "/dev/video2")
        compare(Parse.parseHowdyDevicePath("[other]\ndevice_path=/dev/x\n"), "")
        compare(Parse.parseHowdyDevicePath("ABSENT"), "")
    }

    // --- parseHowdyModels() ---
    // /var/lib/howdy/models/<user>.dat, Howdy 3.0.0 cli/add.py.
    function test_howdy_models() {
        const out = Parse.parseHowdyModels('[{"time": 1793000000, "label": "Initial model", "id": 0, "data": [[0.1]]}, {"time": 1793000100, "label": "glasses", "id": 3, "data": [[0.2]]}]')
        compare(out.length, 2)
        compare(out[0].id, 0)
        compare(out[0].label, "Initial model")
        compare(out[1].id, 3)
        compare(out[1].time, 1793000100)
        compare(out[1].data, undefined)               // encodings are not kept
    }
    function test_howdy_models_garbage() {
        compare(Parse.parseHowdyModels("").length, 0)
        compare(Parse.parseHowdyModels("ABSENT").length, 0)
        compare(Parse.parseHowdyModels("{not json").length, 0)
        compare(Parse.parseHowdyModels('{"id": 1}').length, 0)
    }

    // --- howdyMessage() ---
    function test_howdy_message() {
        const dark = Parse.howdyMessage("\nPlease look straight into the camera\nCamera saw only black frames - is IR emitter working?\n")
        compare(dark.needsEmitter, true)
        compare(dark.text, "Camera saw only black frames - is IR emitter working?")
        const noface = Parse.howdyMessage("Please look straight into the camera\nNo face detected, aborting\n")
        compare(noface.needsEmitter, false)
        compare(noface.text, "No face detected, aborting")
        compare(Parse.howdyMessage("").text, "")
    }

    // --- validatePasswordForm() (mandatory checks only; policy is separate) ---
    function test_password_form_mandatory_checks() {
        compare(Parse.validatePasswordForm("", "new-pass-1", "new-pass-1"), "Enter your current password")
        compare(Parse.validatePasswordForm("old", "", ""), "Enter a new password")
        compare(Parse.validatePasswordForm("old", "new-pass-1", "new-pass-2"), "The new passwords do not match")
        compare(Parse.validatePasswordForm("old", "new-pass-1", "new-pass-1"), Parse.passwordPolicy("old", "new-pass-1"))
    }

    // --- passwordPolicy(): only leading/trailing whitespace is refused ---
    function test_password_policy_edge_spaces() {
        const msg = "The new password starts or ends with a space"
        compare(Parse.passwordPolicy("old", " leading"), msg)
        compare(Parse.passwordPolicy("old", "trailing "), msg)
        compare(Parse.passwordPolicy("old", "\ttab"), msg)
        compare(Parse.validatePasswordForm("old", "x ", "x "), msg)
    }
    function test_password_policy_no_length_or_charset_limits() {
        compare(Parse.passwordPolicy("old", "a"), "")                  // any length
        compare(Parse.passwordPolicy("old", "è ß ü 密码"), "")          // inner spaces, non-ASCII
        compare(Parse.passwordPolicy("old", "old"), "")                // same as current: passwd decides
    }

    // --- passwdResult() ---
    function test_passwd_result() {
        compare(Parse.passwdResult("OK\n").ok, true)
        compare(Parse.passwdResult("BAD_CURRENT").ok, false)
        compare(Parse.passwdResult("BAD_CURRENT").message, "Current password is wrong")
        compare(Parse.passwdResult("REJECTED BAD PASSWORD: too short").message, "Rejected: BAD PASSWORD: too short")
        compare(Parse.passwdResult("ERROR passwd not found").message, "Error: passwd not found")
        compare(Parse.passwdResult("").ok, false)
        compare(Parse.passwdResult("").message, "Error: no answer from identity-passwd")
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
