import QtQuick
import QtTest
import "../services/screenCastParse.js" as Parse

// Pure-logic tests for the ScreenCast parser (services/screenCastParse.js).
// These run headless and need neither a cast device nor the GND daemon.
TestCase {
    name: "ScreenCastParse"

    function sinkReply() {
        return '{"type":"aa{sv}","data":['
            + '{"uuid":{"type":"s","data":"11111111-1111-1111-1111-111111111111"},'
            + '"display-name":{"type":"s","data":"Living room TV"},'
            + '"priority":{"type":"u","data":2},'
            + '"state":{"type":"u","data":4096},'
            + '"protocol":{"type":"u","data":1}},'
            + '{"uuid":{"type":"s","data":"22222222-2222-2222-2222-222222222222"},'
            + '"display-name":{"type":"s","data":"Projector"},'
            + '"priority":{"type":"u","data":1},'
            + '"state":{"type":"u","data":0},'
            + '"protocol":{"type":"u","data":3}}'
            + ']}'
    }

    // --- parseDisplays() ---

    function test_empty_reply_is_empty() {
        compare(Parse.parseDisplays("").length, 0)
    }

    function test_invalid_json_is_empty() {
        compare(Parse.parseDisplays("not json").length, 0)
    }

    function test_non_array_is_empty() {
        compare(Parse.parseDisplays('{"type":"u","data":5}').length, 0)
    }

    function test_parses_two_sinks() {
        const sinks = Parse.parseDisplays(sinkReply())
        compare(sinks.length, 2)
        compare(sinks[0].uuid, "11111111-1111-1111-1111-111111111111")
        compare(sinks[0].name, "Living room TV")
        compare(sinks[0].priority, 2)
        compare(sinks[0].state, 4096)
        compare(sinks[0].protocol, 1)
        compare(sinks[1].name, "Projector")
        compare(sinks[1].protocol, 3)
    }

    function test_accepts_nested_array_encoding() {
        const nested = '{"type":"aa{sv}","data":[[{"uuid":{"type":"s","data":"abc"},'
            + '"display-name":{"type":"s","data":"TV"}}]]}'
        const sinks = Parse.parseDisplays(nested)
        compare(sinks.length, 1)
        compare(sinks[0].uuid, "abc")
        compare(sinks[0].name, "TV")
    }

    function test_skips_entries_without_uuid() {
        const reply = '{"type":"aa{sv}","data":[{"display-name":{"type":"s","data":"ghost"}}]}'
        compare(Parse.parseDisplays(reply).length, 0)
    }

    function test_accepts_plain_values_and_already_parsed_json() {
        const raw = [{ uuid: "abc", "display-name": "TV", priority: 0, state: 0, protocol: 1 }]
        const sinks = Parse.parseDisplays(raw)
        compare(sinks.length, 1)
        compare(sinks[0].name, "TV")
    }

    // --- parseUnitName() ---

    function test_parses_start_stream_reply() {
        compare(Parse.parseUnitName('s "gnome-network-displays-stream-abc.service"'),
            "gnome-network-displays-stream-abc.service")
    }

    function test_empty_unit_reply() {
        compare(Parse.parseUnitName(""), "")
        compare(Parse.parseUnitName("garbage"), "")
    }

    // --- isTransientBusError() ---

    function test_transient_bus_errors() {
        verify(Parse.isTransientBusError(
            "Failed to get property Displays on interface org.gnome.NetworkDisplays.Manager: The name is not activatable"))
        verify(Parse.isTransientBusError(
            "The name org.gnome.NetworkDisplays.Manager was not provided by any .service files"))
        verify(Parse.isTransientBusError("org.freedesktop.DBus.Error.ServiceUnknown"))
        verify(Parse.isTransientBusError("No such name"))
    }

    function test_non_transient_bus_errors() {
        verify(!Parse.isTransientBusError(""))
        verify(!Parse.isTransientBusError("Unknown interface org.gnome.NetworkDisplays.Manager"))
        verify(!Parse.isTransientBusError("Access denied"))
    }

    // --- labels ---

    function test_protocol_labels() {
        compare(Parse.protocolLabel(1), "Wi-Fi Display")
        compare(Parse.protocolLabel(2), "Wi-Fi Display (MICE)")
        compare(Parse.protocolLabel(3), "Chromecast")
        compare(Parse.protocolLabel(99), "Unknown")
    }

    function test_state_labels() {
        compare(Parse.stateLabel(0), "Ready")
        compare(Parse.stateLabel(0x1000), "Streaming")
        compare(Parse.stateLabel(0x10000), "Error")
        compare(Parse.stateLabel(123), "Unknown")
    }
}
