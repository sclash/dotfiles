.pragma library

// Pure parsing helpers for BluetoothService.qml: read the info section of the
// poll command, where every connected device contributes one
// "===INFO:<address>" block, and tell AirPods apart by the Apple AAP UUID.
// No QML imports, no filesystem, no process, so every function here runs
// headless (tests/tst_bluetooth_parse.qml).

// Apple Accessory Protocol, the service AirPods publish over classic BR/EDR.
const AIRPODS_UUID = "74ec2172-0bad-4d01-8f77-997b2be0722a"

// "UUID: Vendor specific           (74ec2172-0bad-4d01-8f77-997b2be0722a)".
// The label between "UUID:" and the parenthesis is free text, so only the
// UUID itself is captured.
const UUID_LINE = /UUID:[^\n]*\(([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})\)/g

function isAirPods(uuids) {
    const list = uuids || []
    for (let i = 0; i < list.length; ++i) {
        if (String(list[i]).toLowerCase() === AIRPODS_UUID) return true
    }
    return false
}

// Map of uppercase address to { uuids, isAirPods }, one entry per
// "===INFO:<address>" marker. An empty or block-less text yields {}.
function parseInfo(text) {
    const out = {}
    const parts = String(text || "").split("===INFO:")
    // parts[0] is whatever came before the first marker.
    for (let i = 1; i < parts.length; ++i) {
        const block = parts[i]
        const newline = block.indexOf("\n")
        const address = (newline === -1 ? block : block.substring(0, newline)).trim().toUpperCase()
        if (address === "") continue
        const body = newline === -1 ? "" : block.substring(newline + 1)
        const uuids = []
        let match
        UUID_LINE.lastIndex = 0
        while ((match = UUID_LINE.exec(body)) !== null) uuids.push(match[1].toLowerCase())
        out[address] = { uuids: uuids, isAirPods: isAirPods(uuids) }
    }
    return out
}
