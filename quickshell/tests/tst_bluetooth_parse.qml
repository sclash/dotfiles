import QtQuick
import QtTest
import "../services/bluetoothParse.js" as BluetoothParse

// Pure-logic tests for the BlueZ `bluetoothctl` info-section parser
// (services/bluetoothParse.js). Headless; no adapter, no paired device.
TestCase {
    name: "BluetoothParse"

    readonly property string info: "===INFO:88:10:32:1B:01:34\nDevice 88:10:32:1B:01:34 (public)\nUUID: Service Discovery Serve.. (00001000-0000-1000-8000-00805f9b34fb)\nUUID: Vendor specific           (74ec2172-0bad-4d01-8f77-997b2be0722a)\n===INFO:AA:BB:CC:DD:EE:FF\nDevice AA:BB:CC:DD:EE:FF (public)\nUUID: Audio Sink                (0000110b-0000-1000-8000-00805f9b34fb)\n"

    function test_parse_blocks() {
        const parsed = BluetoothParse.parseInfo(info)
        verify(parsed.hasOwnProperty("88:10:32:1B:01:34"))
        verify(parsed.hasOwnProperty("AA:BB:CC:DD:EE:FF"))
    }
    function test_airpods_uuid() {
        const block = BluetoothParse.parseInfo(info)["88:10:32:1B:01:34"]
        compare(block.isAirPods, true)
        verify(block.uuids.indexOf(BluetoothParse.AIRPODS_UUID) !== -1)
    }
    function test_non_airpods() {
        const block = BluetoothParse.parseInfo(info)["AA:BB:CC:DD:EE:FF"]
        compare(block.isAirPods, false)
        verify(block.uuids.indexOf("0000110b-0000-1000-8000-00805f9b34fb") !== -1)
    }
    function test_empty() {
        compare(Object.keys(BluetoothParse.parseInfo("")).length, 0)
    }
    function test_is_airpods_helper() {
        compare(BluetoothParse.isAirPods([BluetoothParse.AIRPODS_UUID]), true)
        compare(BluetoothParse.isAirPods([]), false)
    }
}
