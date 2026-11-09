import QtQuick
import QtTest
import "../services/vpnSchema.js" as Schema

// Pure-logic tests for services/vpnSchema.js (Network Center VPN forms).
// Headless; no NetworkManager, no nm-vpn.
TestCase {
    name: "VpnSchema"

    function l2tpState() {
        return { type: "l2tp", uuid: "", name: "Office", values: Schema.defaults("l2tp"),
                 modes: Schema.defaultModes("l2tp"), stored: {}, secretValues: {}, advanced: [] }
    }
    function wgState() {
        const s = { type: "wireguard", uuid: "", name: "Home", values: Schema.defaults("wireguard"),
                    modes: Schema.defaultModes("wireguard"), stored: {}, secretValues: {}, advanced: [] }
        s.values["ipv4.addresses"] = "10.0.0.2/32"
        s.values["peer.public-key"] = "PUB"
        return s
    }
    readonly property var installed: [
        { name: "openvpn", "import": true }, { name: "wireguard", "import": true }, { name: "l2tp", "import": false }
    ]

    function test_defaults_fill_every_non_secret_field() {
        const d = Schema.defaults("l2tp")
        compare(d["ipsec-enabled"], true)
        compare(d.gateway, "")
        verify(!d.hasOwnProperty("password"))
        compare(d["ipv4.never-default"], false)
    }
    function test_default_modes_are_save() {
        const m = Schema.defaultModes("l2tp")
        compare(m.password, "save")
        compare(m["ipsec-psk"], "save")
    }
    function test_showIf_bool() {
        const v = Schema.defaults("l2tp")
        verify(Schema.fieldsFor("l2tp", v).some(f => f.key === "ipsec-psk"))
        v["ipsec-enabled"] = false
        verify(!Schema.fieldsFor("l2tp", v).some(f => f.key === "ipsec-psk"))
    }
    function test_showIf_list_of_values() {
        const v = Schema.defaults("openvpn")
        const keys = () => Schema.fieldsFor("openvpn", v).map(f => f.key)
        verify(keys().indexOf("username") !== -1)
        verify(keys().indexOf("cert") === -1)
        v["connection-type"] = "tls"
        verify(keys().indexOf("username") === -1)
        verify(keys().indexOf("cert") !== -1)
        v["connection-type"] = "static-key"
        verify(keys().indexOf("static-key") !== -1)
        verify(keys().indexOf("ca") === -1)
    }
    function test_build_request_l2tp() {
        const s = l2tpState()
        s.values.gateway = " vpn.example.com "
        s.values.user = "alice"
        s.secretValues = { password: "pw", "ipsec-psk": "" }
        s.modes["ipsec-psk"] = "ask"
        const r = Schema.buildRequest(s)
        compare(r.type, "l2tp")
        compare(r.name, "Office")
        compare(r.data.gateway, "vpn.example.com")
        compare(r.data["ipsec-enabled"], "yes")
        verify(!r.data.hasOwnProperty("ipsec-gateway-id"))      // empty text is left out
        compare(r.secrets.password.mode, "save")
        compare(r.secrets.password.value, "pw")
        compare(r.secrets["ipsec-psk"].mode, "ask")
        compare(r.native["ipv4.never-default"], "no")
        verify(!r.hasOwnProperty("uuid"))
    }
    function test_build_request_leaves_hidden_fields_out() {
        const s = l2tpState()
        s.values.gateway = "g"
        s.values["ipsec-enabled"] = false
        s.values["ipsec-gateway-id"] = "gw"
        s.secretValues = { "ipsec-psk": "x" }
        const r = Schema.buildRequest(s)
        verify(!r.secrets.hasOwnProperty("ipsec-psk"))
        verify(!r.data.hasOwnProperty("ipsec-gateway-id"))
        compare(r.data["ipsec-enabled"], "no")
    }
    function test_build_request_wireguard_is_native() {
        const s = wgState()
        s.uuid = "u1"
        s.secretValues = { "wireguard.private-key": "k", "peer.preshared-key": "" }
        s.modes["peer.preshared-key"] = "ask"
        const r = Schema.buildRequest(s)
        compare(r.uuid, "u1")
        compare(Object.keys(r.data).length, 0)
        compare(r.native["ipv4.addresses"], "10.0.0.2/32")
        compare(r.native["peer.allowed-ips"], "0.0.0.0/0, ::/0")
        compare(r.secrets["wireguard.private-key"].value, "k")
        compare(r.secrets["peer.preshared-key"].mode, "save")   // not askable
    }
    function test_build_request_advanced_rows() {
        const s = l2tpState()
        s.values.gateway = "g"
        s.advanced = [
            { key: "lcp-echo-interval", value: "30", secret: false, mode: "save" },
            { key: "  ", value: "x", secret: false, mode: "save" },
            { key: "machine-certpass", value: "cp", secret: true, mode: "ask" },
        ]
        const r = Schema.buildRequest(s)
        compare(r.data["lcp-echo-interval"], "30")
        compare(Object.keys(r.data).filter(k => k.trim() === "").length, 0)
        compare(r.secrets["machine-certpass"].mode, "ask")
        compare(r.secrets["machine-certpass"].value, "cp")
    }
    function test_from_profile() {
        const p = { uuid: "u", name: "Office", type: "l2tp",
            data: { gateway: "g", "ipsec-enabled": "no", "password-flags": "0", "ipsec-psk-flags": "2", "lcp-echo-interval": "30" },
            secrets: { password: "save", "ipsec-psk": "ask", "machine-certpass": "unset" },
            native: { "ipv4.never-default": "yes" }, user: {} }
        const s = Schema.fromProfile(p)
        compare(s.uuid, "u")
        compare(s.name, "Office")
        compare(s.values.gateway, "g")
        compare(s.values["ipsec-enabled"], false)
        compare(s.values["ipv4.never-default"], true)
        compare(s.modes.password, "save")
        compare(s.modes["ipsec-psk"], "ask")
        compare(s.stored.password, true)
        compare(s.stored["ipsec-psk"], false)
        compare(s.advanced.map(r => r.key).join(","), "lcp-echo-interval,machine-certpass")
        const cp = s.advanced[1]
        verify(cp.secret)
        compare(cp.value, "")
        compare(cp.mode, "save")
        compare(cp.stored, false)
        verify(cp.existing)
    }
    function test_from_profile_unknown_type_is_all_advanced() {
        const s = Schema.fromProfile({ uuid: "u", name: "F", type: "fortisslvpn",
            data: { gateway: "g", "password-flags": "2" }, secrets: { password: "ask" }, native: {}, user: {} })
        compare(s.advanced.map(r => r.key).join(","), "gateway,password")
        compare(s.advanced[1].mode, "ask")
    }
    function test_validate_name_and_required_text() {
        const s = l2tpState()
        s.name = " "
        compare(Schema.validate(s).key, "name")
        s.name = "Office"
        const e = Schema.validate(s)
        compare(e.key, "gateway")
        compare(e.message, "Gateway is required")
        s.values.gateway = "g"
        compare(Schema.validate(s), null)
    }
    function test_validate_required_secret_respects_ask_and_stored() {
        const s = wgState()
        compare(Schema.validate(s).key, "wireguard.private-key")
        s.modes["wireguard.private-key"] = "ask"
        compare(Schema.validate(s), null)
        s.modes["wireguard.private-key"] = "save"
        s.stored = { "wireguard.private-key": true }
        compare(Schema.validate(s), null)
    }
    function test_validate_number() {
        const s = wgState()
        s.secretValues = { "wireguard.private-key": "k" }
        s.values["wireguard.listen-port"] = "51x"
        compare(Schema.validate(s).message, "Listen port must be a whole number")
        s.values["wireguard.listen-port"] = "51820"
        compare(Schema.validate(s), null)
    }
    function test_validate_advanced() {
        const s = l2tpState()
        s.values.gateway = "g"
        s.advanced = [{ key: "a b", value: "1", secret: false, mode: "save" }]
        compare(Schema.validate(s).key, "advanced")
        s.advanced = [{ key: "password-flags", value: "0", secret: false, mode: "save" }]
        compare(Schema.validate(s).key, "advanced")
        s.advanced = [{ key: "gateway", value: "x", secret: false, mode: "save" }]
        compare(Schema.validate(s).message, "Key \"gateway\" is already in the form")
        s.advanced = [{ key: "x", value: "1", secret: false, mode: "save" }, { key: "x", value: "2", secret: false, mode: "save" }]
        compare(Schema.validate(s).message, "Key \"x\" appears twice")
        s.advanced = [{ key: "x", value: "1", secret: false, mode: "save" }]
        compare(Schema.validate(s), null)
    }
    function test_wireguard_multi_peer_hides_peer_fields() {
        const s = wgState()
        s.secretValues = { "wireguard.private-key": "k" }
        s.values["peer.count"] = "2"
        s.values["peer.public-key"] = ""
        verify(!Schema.fieldsFor("wireguard", s.values).some(f => f.key.indexOf("peer.") === 0))
        compare(Schema.validate(s), null)
    }
    function test_type_for_path() {
        compare(Schema.typeForPath("/x/office.OVPN", installed), "openvpn")
        compare(Schema.typeForPath("/x/wg0.conf", installed), "")          // OpenVPN and WireGuard both claim .conf
        compare(Schema.typeForPath("/x/wg0.conf", [installed[1]]), "wireguard")
        compare(Schema.typeForPath("/x/notes.txt", installed), "")
        compare(Schema.typeForPath("/x/noext", installed), "")
    }
    function test_import_extensions() {
        compare(Schema.importExtensions(installed).join(","), ".ovpn,.conf")
        compare(Schema.importExtensions([{ name: "l2tp", "import": false }]).length, 0)
    }
    function test_picker_types_order() {
        const t = Schema.pickerTypes([{ name: "wireguard", "import": true }, { name: "fortisslvpn", "import": false }, { name: "l2tp", "import": false }])
        compare(t.map(x => x.label).join(","), "L2TP/IPsec,WireGuard,fortisslvpn")
        verify(t[2].advancedOnly)
        verify(!t[0].advancedOnly)
    }
    function test_cycle_choice_and_label() {
        const f = Schema.fieldByKey("openvpn", "connection-type")
        compare(Schema.cycleChoice(f, "password", 1), "tls")
        compare(Schema.cycleChoice(f, "password", -1), "static-key")
        compare(Schema.choiceLabel(f, "tls"), "Certificates")
    }
    function test_label_for() {
        compare(Schema.labelFor("l2tp", "ipsec-psk"), "Pre-shared key")
        compare(Schema.labelFor("fortisslvpn", "otp"), "otp")
    }
}
