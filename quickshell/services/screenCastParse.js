.pragma library

// Pure parsing helpers for ScreenCastService.qml. Kept out of the QML file so
// they can be unit-tested headless (tests/tst_screencast_parse.qml).

// busctl --json=short wraps every value as {"type": T, "data": D}. Unwrap one
// level; leave plain values untouched.
function unwrap(value) {
    if (value && typeof value === "object" && !Array.isArray(value)
        && Object.prototype.hasOwnProperty.call(value, "type")
        && Object.prototype.hasOwnProperty.call(value, "data"))
        return value.data
    return value
}

// Parses the org.gnome.NetworkDisplays.Manager Displays property
// (aa{sv}) from a busctl --json=short reply (string or already-parsed JSON).
// Returns [{uuid, name, priority, state, protocol}].
function parseDisplays(reply) {
    let payload = reply
    if (typeof payload === "string") {
        const text = payload.trim()
        if (text === "") return []
        try { payload = JSON.parse(text) } catch (e) { return [] }
    }

    let list = unwrap(payload)
    if (!Array.isArray(list)) return []
    // Accept both encodings busctl may use for aa{sv}:
    //   [ {uuid: {...}, ...}, ... ]      (array elements are dicts)
    //   [ [ {uuid: {...}, ...}, ... ] ]  (one array wrapping the list)
    if (list.length === 1 && Array.isArray(list[0])) list = list[0]

    const out = []
    for (let i = 0; i < list.length; i++) {
        const item = list[i]
        if (!item || typeof item !== "object" || Array.isArray(item)) continue

        const sink = {}
        const keys = Object.keys(item)
        for (let k = 0; k < keys.length; k++) sink[keys[k]] = unwrap(item[keys[k]])

        if (!sink.uuid) continue
        out.push({
            uuid: String(sink.uuid),
            name: String(sink["display-name"] !== undefined ? sink["display-name"]
                : (sink.name !== undefined ? sink.name : "Unknown display")),
            priority: Number(sink.priority || 0),
            state: Number(sink.state || 0),
            protocol: Number(sink.protocol || 0)
        })
    }
    return out
}

// Extracts the unit name from a StartStream reply: `s "…unit.service"`.
function parseUnitName(reply) {
    const m = /"([^"]+\.service)"/.exec(String(reply || ""))
    return m ? m[1] : ""
}

// True when a busctl failure means "the daemon is not up yet" rather than a real
// configuration error. Those are worth a short retry: the unit is Type=dbus, so
// `systemctl start` returns only after the name is owned, but a daemon that
// crashes between `is-active` and `get-property` still races.
function isTransientBusError(text) {
    const s = String(text || "").toLowerCase()
    if (s === "") return false
    return s.indexOf("not activat") >= 0
        || s.indexOf("not provided by any .service files") >= 0
        || s.indexOf("no such name") >= 0
        || s.indexOf("serviceunknown") >= 0
        || s.indexOf("unknownservice") >= 0
        || s.indexOf("could not activate") >= 0
}

function protocolLabel(protocol) {
    switch (Number(protocol)) {
    case 1: return "Wi-Fi Display"
    case 2: return "Wi-Fi Display (MICE)"
    case 3: return "Chromecast"
    default: return "Unknown"
    }
}

function stateLabel(state) {
    switch (Number(state)) {
    case 0: return "Ready"
    case 0x50: return "Preparing"
    case 0x100: return "Pairing"
    case 0x110: return "Connecting"
    case 0x120: return "Starting"
    case 0x1000: return "Streaming"
    case 0x10000: return "Error"
    default: return "Unknown"
    }
}
