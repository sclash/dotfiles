import QtQuick
import QtTest
import "../services/airPodsParse.js" as Parse

// Pure-logic tests for the AirPods status parser (services/airPodsParse.js).
// Headless; no daemon, no Bluetooth device.
TestCase {
    name: "AirPodsParse"

    readonly property string fixture: '{"schema_version":1,"connected":true,"device_name":"Test AirPods","model_name":"AirPods 5","model_number":"A3439","is_pro_series":false,"is_headset":false,"supports_noise_off":true,"supports_noise_control":true,"supports_adaptive":true,"supports_conversational_awareness":true,"supports_one_bud_anc":true,"noise_mode":1,"adaptive_noise_level":60,"one_bud_anc_mode":true,"conversational_awareness":true,"ear_detection_behavior":0,"lid_state":0,"left":{"available":true,"charging":false,"in_ear":true,"level":93},"right":{"available":true,"charging":true,"in_ear":false,"level":97},"case":{"available":true,"charging":false,"level":82},"headset":{"available":false,"charging":false,"level":0}}'

    // --- parseStatus(): failures still return the full Status shape ---
    function test_empty_file() {
        const s = Parse.parseStatus("")
        compare(s.ok, false)
        verify(s.lastError.length > 0)
    }
    function test_non_json() {
        const s = Parse.parseStatus("{not json")
        compare(s.ok, false)
        verify(s.lastError.length > 0)
    }
    function test_missing_schema() {
        const s = Parse.parseStatus('{"connected":true}')
        compare(s.ok, false)
        verify(s.lastError.indexOf("schema_version") !== -1)
    }
    function test_newer_schema() {
        const s = Parse.parseStatus('{"schema_version":2,"connected":true}')
        compare(s.ok, false)
        compare(s.schemaTooNew, true)
        verify(s.lastError.indexOf("2") !== -1)
    }

    // --- parseStatus(): a known schema, connected or not ---
    function test_disconnected() {
        const s = Parse.parseStatus('{"schema_version":1,"connected":false}')
        compare(s.ok, true)
        compare(s.connected, false)
        compare(s.left.level, -1)
    }
    function test_airpods5_fixture() {
        const s = Parse.parseStatus(fixture)
        compare(s.ok, true)
        compare(s.modelName, "AirPods 5")
        compare(s.modelNumber, "A3439")
        compare(s.noiseMode, 1)
        compare(s.left.level, 93)
        compare(s.left.inEar, true)
        compare(s.right.level, 97)
        compare(s.right.charging, true)
        compare(s.caseBattery.level, 82)
        compare(s.adaptiveNoiseLevel, 60)
        compare(s.conversationalAwareness, true)
        compare(s.oneBudANC, true)
        compare(s.lidState, 0)
    }
    function test_headset_fixture() {
        const s = Parse.parseStatus('{"schema_version":1,"connected":true,"device_name":"Test Max","model_name":"AirPods Max","model_number":"A3184","is_headset":true,"headset":{"available":true,"charging":false,"level":64}}')
        compare(s.ok, true)
        compare(s.isHeadset, true)
        compare(s.headsetBattery.level, 64)
        compare(s.caseBattery.level, -1)
    }
    function test_available_false_pod() {
        const s = Parse.parseStatus('{"schema_version":1,"connected":true,"left":{"available":false,"charging":true,"in_ear":true,"level":50}}')
        compare(s.left.level, -1)
        compare(s.left.charging, false)
        compare(s.left.inEar, false)
    }
    function test_capability_fallbacks() {
        const s = Parse.parseStatus('{"schema_version":1,"connected":true,"is_pro_series":true,"model_name":"AirPods Pro"}')
        compare(s.supportsNoiseControl, true)
        compare(s.supportsNoiseOff, true)
        compare(s.supportsAdaptive, true)
        compare(s.supportsConversationalAwareness, true)
        compare(s.supportsOneBudANC, true)
    }

    // --- availableModes(): the cycle order, filtered by capabilities ---
    function test_available_modes() {
        compare(Parse.availableModes(true, true, true).join(","), "0,2,3,1")
        compare(Parse.availableModes(true, false, false).join(","), "2,1")
        compare(Parse.availableModes(false, true, true).join(","), "")
    }

    // --- verbs and labels ---
    function test_verbs() {
        compare(Parse.noiseModeVerb(1), "noise:anc")
        compare(Parse.earDetectionVerb(1), "ear:both")
        compare(Parse.noiseModeVerb(9), "")
        compare(Parse.earDetectionVerb(9), "")
    }
    function test_labels() {
        compare(Parse.noiseModeName(2), "Transparency")
        compare(Parse.earDetectionName(2), "Never pause")
        compare(Parse.levelText(-1), "--")
        compare(Parse.levelFraction(-1), 0)
        compare(Parse.lidText(0), "Open")
        compare(Parse.podMeta({ charging: true }), "Charging")
    }
    function test_elide_error() {
        const out = Parse.elideError(new Array(201).join("x"))
        compare(out.length, 138)
        compare(out, new Array(138).join("x") + "…")
    }

    // --- defaultStatus(): every field the panel reads is present ---
    function test_default_status() {
        const s = Parse.defaultStatus()
        const fields = ["ok", "lastError", "schemaVersion", "schemaTooNew", "connected",
            "deviceName", "modelName", "modelNumber", "isProSeries", "isHeadset",
            "supportsNoiseOff", "supportsNoiseControl", "supportsAdaptive",
            "supportsConversationalAwareness", "supportsOneBudANC", "noiseMode",
            "adaptiveNoiseLevel", "oneBudANC", "conversationalAwareness",
            "earDetectionBehavior", "lidState", "left", "right", "caseBattery", "headsetBattery"]
        for (let i = 0; i < fields.length; ++i)
            verify(s.hasOwnProperty(fields[i]), "missing " + fields[i])
        compare(s.left.level, Parse.LEVEL_UNKNOWN)
        compare(s.right.level, Parse.LEVEL_UNKNOWN)
    }
}
