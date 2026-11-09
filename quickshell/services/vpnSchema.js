.pragma library

// VPN types the Network Center draws forms for, and pure helpers that turn
// form state into `nm-vpn add|update` requests. No Qt, no processes:
// unit-tested headless by tests/tst_vpn_schema.qml.
// Spec: docs/superpowers/specs/2026-11-09-native-vpn-design.md §8.
//
// Field kinds: text | secret | bool | choice | file | number.
// Plugin types keep fields in vpn.data / vpn.secrets under `key`; bools are
// stored as "yes"/"no". WireGuard (`native: true`) and COMMON fields use the
// setting paths nm-vpn understands. A type with no entry here is still usable:
// its form is Name plus the Advanced rows.
// `default` is for new profiles only. When an existing profile lacks a key,
// the form shows `absent` (else off for a bool, the default for a choice,
// empty otherwise) and a save leaves the key out until that field is edited:
// the plugin's own meaning of a missing key (no IPsec, no inner IP, TLS) wins.
// tests/test-vpn-schema-keys.sh reads this file line by line: keep each type
// header (`    name: { … fields: [`) and each field (`{ key: "…", … }`) on one line.

var COMMON = [
    { key: "ipv4.never-default", label: "Use only for resources on its network", kind: "bool", default: false, common: true },
]

// WireGuard peer fields are hidden for profiles with more than one peer
// (nm-vpn reports "peer.count"); those are changed by re-importing.
var ONE_PEER = { "peer.count": ["", "0", "1"] }

var TYPES = {
    l2tp: { label: "L2TP/IPsec", service: "org.freedesktop.NetworkManager.l2tp", importExt: [], fields: [
        { key: "gateway", label: "Gateway", kind: "text", required: true, placeholder: "vpn.example.com" },
        { key: "user", label: "Username", kind: "text" },
        { key: "password", label: "Password", kind: "secret" },
        { key: "ipsec-enabled", label: "Use IPsec", kind: "bool", default: true },
        { key: "ipsec-psk", label: "Pre-shared key", kind: "secret", showIf: { "ipsec-enabled": true } },
        { key: "ipsec-gateway-id", label: "Gateway ID", kind: "text", showIf: { "ipsec-enabled": true } },
    ] },
    openvpn: { label: "OpenVPN", service: "org.freedesktop.NetworkManager.openvpn", importExt: [".ovpn", ".conf"], fields: [
        { key: "remote", label: "Gateway", kind: "text", required: true, placeholder: "vpn.example.com:1194" },
        { key: "connection-type", label: "Authentication", kind: "choice", default: "password", absent: "tls", options: [{ value: "password", label: "Password" }, { value: "tls", label: "Certificates" }, { value: "password-tls", label: "Password and certificates" }, { value: "static-key", label: "Static key" }] },
        { key: "username", label: "Username", kind: "text", showIf: { "connection-type": ["password", "password-tls"] } },
        { key: "password", label: "Password", kind: "secret", showIf: { "connection-type": ["password", "password-tls"] } },
        { key: "ca", label: "CA certificate", kind: "file", showIf: { "connection-type": ["password", "tls", "password-tls"] } },
        { key: "cert", label: "User certificate", kind: "file", showIf: { "connection-type": ["tls", "password-tls"] } },
        { key: "key", label: "Private key", kind: "file", showIf: { "connection-type": ["tls", "password-tls"] } },
        { key: "cert-pass", label: "Private key password", kind: "secret", showIf: { "connection-type": ["tls", "password-tls"] } },
        { key: "static-key", label: "Static key", kind: "file", showIf: { "connection-type": "static-key" } },
        { key: "local-ip", label: "Local IP", kind: "text", showIf: { "connection-type": "static-key" } },
        { key: "remote-ip", label: "Remote IP", kind: "text", showIf: { "connection-type": "static-key" } },
    ] },
    strongswan: { label: "IKEv2 (strongSwan)", service: "org.freedesktop.NetworkManager.strongswan", importExt: [], fields: [
        { key: "address", label: "Gateway", kind: "text", required: true, placeholder: "vpn.example.com" },
        { key: "method", label: "Authentication", kind: "choice", default: "eap", options: [{ value: "eap", label: "Username and password (EAP)" }, { value: "psk", label: "Pre-shared key" }, { value: "key", label: "Certificate and private key" }, { value: "agent", label: "Certificate and ssh-agent" }, { value: "smartcard", label: "Smartcard" }] },
        { key: "user", label: "Username", kind: "text", showIf: { "method": ["eap", "psk"] } },
        { key: "password", label: "Password", kind: "secret", showIf: { "method": ["eap", "psk", "key"] } },
        { key: "certificate", label: "Server or CA certificate", kind: "file" },
        { key: "usercert", label: "User certificate", kind: "file", showIf: { "method": ["key", "agent"] } },
        { key: "userkey", label: "Private key", kind: "file", showIf: { "method": "key" } },
        { key: "virtual", label: "Request an inner IP address", kind: "bool", default: true },
    ] },
    wireguard: { label: "WireGuard", native: true, service: "", importExt: [".conf"], fields: [
        { key: "wireguard.private-key", label: "Private key", kind: "secret", required: true },
        { key: "ipv4.addresses", label: "Addresses", kind: "text", required: true, placeholder: "10.0.0.2/32, fd00::2/128" },
        { key: "ipv4.dns", label: "DNS servers", kind: "text", placeholder: "10.0.0.1" },
        { key: "wireguard.listen-port", label: "Listen port", kind: "number" },
        { key: "peer.public-key", label: "Peer public key", kind: "text", required: true, showIf: ONE_PEER },
        { key: "peer.endpoint", label: "Peer endpoint", kind: "text", placeholder: "vpn.example.com:51820", showIf: ONE_PEER },
        { key: "peer.allowed-ips", label: "Allowed IPs", kind: "text", default: "0.0.0.0/0, ::/0", showIf: ONE_PEER },
        { key: "peer.preshared-key", label: "Peer pre-shared key", kind: "secret", askable: false, showIf: ONE_PEER },
        { key: "peer.persistent-keepalive", label: "Keepalive (seconds)", kind: "number", showIf: ONE_PEER },
    ] },
}

function typeInfo(name) { return Object.prototype.hasOwnProperty.call(TYPES, name) ? TYPES[name] : null }
function hasSchema(name) { return typeInfo(name) !== null }
function typeLabel(name) { const t = typeInfo(name); return t ? t.label : String(name || "") }
function isNative(name) { const t = typeInfo(name); return !!(t && t.native) }
function allFields(name) { const t = typeInfo(name); return (t ? t.fields : []).concat(COMMON) }
function fieldByKey(name, key) {
    const fs = allFields(name)
    for (let i = 0; i < fs.length; i++) if (fs[i].key === key) return fs[i]
    return null
}
function labelFor(name, key) { const f = fieldByKey(name, key); return f ? f.label : key }

function defaults(name) {
    const out = {}
    allFields(name).forEach(f => {
        if (f.kind === "secret") return
        if (f.default !== undefined) out[f.key] = f.default
        else out[f.key] = f.kind === "bool" ? false : ""
    })
    return out
}
function defaultModes(name) {
    const m = {}
    allFields(name).forEach(f => { if (f.kind === "secret") m[f.key] = "save" })
    return m
}

function isShown(field, values) {
    if (!field.showIf) return true
    for (const k in field.showIf) {
        const want = field.showIf[k]
        const have = values[k] === undefined ? "" : values[k]
        if (Array.isArray(want) ? want.indexOf(have) === -1 : have !== want) return false
    }
    return true
}
function fieldsFor(name, values) { return allFields(name).filter(f => isShown(f, values)) }

function toBool(v) { return v === true || v === "yes" || v === "true" || v === "1" }
function cycleChoice(field, value, step) {
    const o = field.options || []
    if (o.length === 0) return value
    let i = -1
    for (let j = 0; j < o.length; j++) if (o[j].value === value) i = j
    i = i < 0 ? 0 : (i + step + o.length) % o.length
    return o[i].value
}
function choiceLabel(field, value) {
    const o = (field.options || []).filter(x => x.value === value)[0]
    return o ? o.label : String(value || "")
}

// Form value shown for a key an existing profile lacks.
function absentValue(f) {
    if (f.absent !== undefined) return f.absent
    if (f.kind === "bool") return false
    if (f.kind === "choice" && f.default !== undefined) return f.default
    return ""
}

// `nm-vpn get` profile → form state. Secret values never come back, only
// their modes ("save" | "ask" | "unset"); `stored` marks saved ones.
// `absent` marks the schema keys the profile lacks (see `absent` above).
function fromProfile(p) {
    const name = p.type
    const values = {}
    const absent = {}
    const modes = defaultModes(name)
    const stored = {}
    const data = p.data || {}
    const native = p.native || {}
    const src = {}
    for (const k in data) src[k] = data[k]
    for (const k in native) src[k] = native[k]
    allFields(name).forEach(f => {
        if (f.kind === "secret" || src.hasOwnProperty(f.key)) return
        values[f.key] = absentValue(f)
        absent[f.key] = true
    })
    for (const k in src) {
        const f = fieldByKey(name, k)
        if (f && f.kind === "secret") continue
        values[k] = f && f.kind === "bool" ? toBool(src[k]) : String(src[k])
    }
    const secrets = p.secrets || {}
    const advanced = []
    for (const k in secrets) {
        const mode = secrets[k] === "ask" ? "ask" : "save"
        if (fieldByKey(name, k)) { modes[k] = mode; stored[k] = secrets[k] === "save" }
        else advanced.push({ key: k, value: "", secret: true, mode: mode, stored: secrets[k] === "save", existing: true })
    }
    for (const k in data) {
        if (fieldByKey(name, k) || /-flags$/.test(k) || secrets.hasOwnProperty(k)) continue
        advanced.push({ key: k, value: String(data[k]), secret: false, mode: "save", stored: false, existing: true })
    }
    advanced.sort((a, b) => a.key < b.key ? -1 : (a.key > b.key ? 1 : 0))
    return { type: name, uuid: p.uuid || "", name: p.name || "", values: values, modes: modes, stored: stored, advanced: advanced, absent: absent }
}

// Form state → `nm-vpn add|update` request. Hidden fields are left out, so on
// update nm-vpn removes their data keys; secrets left out are kept as they are.
// Keys in `state.absent` stay out unless `state.touched` marks them edited.
function buildRequest(state) {
    const name = state.type
    const native = isNative(name)
    const req = { type: name, name: String(state.name || "").trim(), data: {}, secrets: {}, native: {}, user: {} }
    if (state.uuid) req.uuid = state.uuid
    const sv = state.secretValues || {}
    const absent = state.absent || {}
    const touched = state.touched || {}
    const shown = fieldsFor(name, state.values)
    shown.forEach(f => {
        if (f.kind === "secret") {
            const mode = f.askable === false ? "save" : (state.modes[f.key] === "ask" ? "ask" : "save")
            req.secrets[f.key] = { mode: mode, value: String(sv[f.key] || "") }
            return
        }
        if (absent[f.key] && !touched[f.key]) return
        const v = state.values[f.key]
        const s = f.kind === "bool" ? (toBool(v) ? "yes" : "no") : String(v === undefined || v === null ? "" : v).trim()
        if (s === "") return
        if (native || f.common) req.native[f.key] = s
        else req.data[f.key] = s
    })
    const adv = state.advanced || []
    adv.forEach(r => {
        const k = String(r.key || "").trim()
        if (k === "") return
        if (r.secret) req.secrets[k] = { mode: r.mode === "ask" ? "ask" : "save", value: String(r.value || "") }
        else req.data[k] = String(r.value === undefined || r.value === null ? "" : r.value)
    })
    return req
}

// First problem in the form, or null.
function validate(state) {
    if (String(state.name || "").trim() === "") return { key: "name", message: "Name is required" }
    const shown = fieldsFor(state.type, state.values)
    const sv = state.secretValues || {}
    const stored = state.stored || {}
    for (let i = 0; i < shown.length; i++) {
        const f = shown[i]
        if (f.kind === "secret") {
            if (!f.required) continue
            if (f.askable !== false && state.modes[f.key] === "ask") continue
            if (stored[f.key]) continue
            if (String(sv[f.key] || "") === "") return { key: f.key, message: f.label + " is required" }
            continue
        }
        const v = String(state.values[f.key] === undefined || state.values[f.key] === null ? "" : state.values[f.key]).trim()
        if (f.required && v === "") return { key: f.key, message: f.label + " is required" }
        if (f.kind === "number" && v !== "" && !/^[0-9]+$/.test(v)) return { key: f.key, message: f.label + " must be a whole number" }
    }
    const seen = {}
    const adv = state.advanced || []
    for (let i = 0; i < adv.length; i++) {
        const k = String(adv[i].key || "").trim()
        if (k === "") continue
        if (/\s/.test(k)) return { key: "advanced", message: "Key \"" + k + "\" contains a space" }
        if (/-flags$/.test(k)) return { key: "advanced", message: "\"" + k + "\" is set by the Save | Ask chip" }
        if (fieldByKey(state.type, k)) return { key: "advanced", message: "Key \"" + k + "\" is already in the form" }
        if (seen[k]) return { key: "advanced", message: "Key \"" + k + "\" appears twice" }
        seen[k] = true
    }
    return null
}

function importableTypes(installed) { return (installed || []).filter(t => t["import"]) }
function importExtensions(installed) {
    const out = []
    importableTypes(installed).forEach(t => {
        const info = typeInfo(t.name)
        ;(info ? info.importExt : []).forEach(e => { if (out.indexOf(e) === -1) out.push(e) })
    })
    return out
}
// The one installed, import-capable type whose schema claims this file's
// extension, or "" when none or several do (the import view then asks).
function typeForPath(path, installed) {
    const m = /(\.[^./]+)$/.exec(String(path || "").toLowerCase())
    if (!m) return ""
    const hits = importableTypes(installed).filter(t => {
        const info = typeInfo(t.name)
        return info !== null && info.importExt.indexOf(m[1]) !== -1
    })
    return hits.length === 1 ? hits[0].name : ""
}
// Types for the picker: schema types by label, then the advanced-only ones.
function pickerTypes(installed) {
    return (installed || []).map(t => ({ name: t.name, label: typeLabel(t.name), advancedOnly: !hasSchema(t.name), "import": !!t["import"] }))
        .sort((a, b) => {
            if (a.advancedOnly !== b.advancedOnly) return a.advancedOnly ? 1 : -1
            return a.label < b.label ? -1 : (a.label > b.label ? 1 : 0)
        })
}
