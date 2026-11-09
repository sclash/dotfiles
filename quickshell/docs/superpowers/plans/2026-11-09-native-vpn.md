# Network Center — Native VPN Management Implementation Plan (Plan 1 of 2)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add, import, edit, delete and connect VPNs entirely inside the Quickshell Network Center (`SUPER+W`, `/vpn`), for every installed NetworkManager VPN type plus WireGuard, and remove `networkmanagerapplet` (`nm-connection-editor`, `nm-applet`).

**Architecture:** A Python helper, `nm-vpn`, talks to NetworkManager through libnm (PyGObject). It reads one JSON request on stdin and prints one JSON line, so secrets never reach argv. It connects with `nmcli … passwd-file` on a pipe. `vpnSchema.js` holds the plugin knowledge as pure data plus pure functions. `NetworkService.qml` wraps the helper. New views in `components/launchers/network/` slide over the Network Center's list (STYLE.md §2.5).

**Tech Stack:** NixOS (pinned flake), NetworkManager/nmcli 1.56, libnm via PyGObject, Python 3 (stdlib only for tests), Quickshell 0.3.2 QML, Qt Quick Test, bash test scripts, NixOS VM tests (`pkgs.testers.runNixOSTest`).

**Spec:** `quickshell/docs/superpowers/specs/2026-11-09-native-vpn-design.md`

**Amendments made during execution (these override the task text below):**
- `import` is a reserved word for Qt 6.11's QML parser: quote every `import` object key (`"import":`) and use `t["import"]` in all QML/JS.
- SSTP is dropped: `networkmanager-sstp` is flagged insecure (CVE-2026-91838) in the pinned nixpkgs and broke evaluation of the whole system. It isn't installed, has no schema entry, and docs must not list it as offered. Spec §11, §13 and §14 mention it and are amended in Task 10.
- `nixos/tests/test-vpn.sh` also asserts that the whole system evaluates (`systemEvaluates`).
- `VpnChip`'s property is `isSecond`, not `onSecond`: a property named `on<Name>` clashes with QML's change handler for `<name>`, so the chip failed to load.
- `NetworkService` runs a helper callback only after the helper process has exited, so a callback can start the next request.
- `nixos/configuration.nix` creates an empty `/etc/strongswan.conf`: without it charon-nm and nm-l2tp's IPsec starter can't start.
- `LibnmBackend.load()` marks `secrets_unreadable` when the secrets fetch fails, and `save()` then refuses (fix approved by the user).

**Plan 2 (not this plan):** the OpenConnect plugin and its login step (spec §10). It's written after Task 5, because it depends on two answers the VM test gives: whether `passwd-file` works through a pipe, and whether `nm-openconnect` accepts `form:*` secrets. Until then `networkmanager-openconnect` isn't installed, so nothing half-works.

## Global Constraints

- Repo root is the worktree `/home/asergi/dotfiles/.worktrees/native-vpn` (branch `native-vpn`). All paths below are relative to it. The QML root is `quickshell/`.
- Never touch `~/dotfiles` (the live checkout), `/etc/nixos` or `~/.config/sops`. No rebuilds (`nixos-rebuild switch`) and no `nix-env`.
- **The live NetworkManager is read-only.** The only command allowed against it is `nm-vpn types` (it lists plugins). Anything that creates, changes or activates a profile runs in the NixOS VM test (Task 5) or against stubs.
- Commits happen only after the user approves executing this plan. Use Conventional Commits with short messages, end each commit message with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`, and never use `--no-verify`.
- `git add` every new file before any `nix eval` or `nix build` of the flake (a flake only sees tracked files).
- No hard-coded colours or glyphs outside `quickshell/theme/Theme.qml` and `Icons.qml`: use `Theme.*` and `Icons.*`. State is shown by borders (`STYLE.md` §2.1). The card is 620 px.
- One `Process` per job inside `quickshell/services/`. Views and launchers never start processes.
- Secrets: only on a helper's stdin and in `nmcli`'s passwd-file pipe. Never in argv, the environment, logs, test output or `nm-vpn` output. QML clears typed secrets as soon as they are handed over, on leaving a view and on close.
- Secret flags: Save → `0` (or `4` "not required" when there's no value), Ask → `2`. Reading: `1` or `2` → `ask`.
- Helper result lines: `{"ok": true, …}`, `{"ok": false, "error": "…"}`, or for connect `{"ok": false, "need": [keys], "type": "<type>"}`.
- Test hooks, tests only: `NM_VPN_FAKE_STATE`, `NM_VPN_NMCLI_BIN`, `NM_VPN_CONNECT_WAIT`.

## Review Focus

- No path where a secret value is printed: `nm-vpn get` output, error messages (scrubbed), `nmcli` argv, the smoke-test stub's argv log, QML properties that outlive submit.
- `update` semantics: an empty secret value keeps the stored one; a data key left out is removed, **except** `*-flags`; a WireGuard profile with more than one peer keeps its peers.
- Profiles made by `nm-connection-editor` (agent-owned secrets, flag `1`) must prompt instead of failing.
- Degraded states: without `nm-vpn`, list, connect and delete still work through `nmcli`, and Add shows `Not available`.

## File map

| File | Status | Responsibility |
|---|---|---|
| `quickshell/services/vpnSchema.js` | new | Per-type fields; form state ↔ helper request; validation; import type guess |
| `quickshell/tests/tst_vpn_schema.qml` | new | Unit tests for the schema |
| `quickshell/scripts/nm-vpn.py` | new | The helper: pure logic, JSON-file backend (tests), libnm backend |
| `quickshell/scripts/nm-vpn.nix` | new | Packages the helper (PyGObject, typelibs, nmcli on PATH) |
| `quickshell/tests/test_nm_vpn.py`, `test-nm-vpn.sh` | new | Helper unit and CLI tests (fake backend, fake nmcli) |
| `quickshell/tests/test-vpn-schema-keys.sh` | new | Every schema key exists in its plugin's binaries |
| `nixos/tests/test-vpn.sh` | new | Evaluated-config assertions (plugins, packages) |
| `nixos/tests/vpn-vm.nix`, `test-vpn-vm.sh` | new | NixOS VM test against a real NetworkManager |
| `quickshell/services/NetworkService.qml` | modify | VPN API over the helper; WireGuard active fix; editor removed |
| `quickshell/components/launchers/network/*.qml` | new | `VpnRow`, `VpnChip`, `VpnTypeView`, `VpnImportView`, `VpnSecretPrompt`, `VpnFieldStop`, `VpnAdvancedRow`, `VpnFormView` |
| `quickshell/tests/smoke/vpn-views.qml`, `smoke-vpn-views.sh` | new | Offscreen smoke test with stub `nm-vpn` and `nmcli` |
| `quickshell/components/launchers/NetworkCenter.qml` | modify | View stack, 620 px, `/vpn` rows, `e` edit, secret prompt |
| `nixos/configuration.nix`, `nixos/programs/quickshell.nix` | modify | Plugins; `nm-vpn`; remove `networkmanagerapplet` |
| `quickshell/specs/launchers/Network-Center.md`, `quickshell/specs/SPECS.md`, `README.md`, `AGENTS.md`, the design spec | modify | Docs and specs |

---

### Task 1: `vpnSchema.js` — the plugin knowledge

**Files:**
- Create: `quickshell/services/vpnSchema.js`
- Test: `quickshell/tests/tst_vpn_schema.qml` (picked up by `quickshell/tests/run.sh`)

**Interfaces:**
- Consumes: nothing.
- Produces (all top-level functions of a `.pragma library` file):
  - `typeInfo(name) → object|null`, `hasSchema(name) → bool`, `typeLabel(name) → string`, `isNative(name) → bool`
  - `allFields(name) → [field]` (schema fields + `COMMON`), `fieldByKey(name, key) → field|null`, `labelFor(name, key) → string`
  - `defaults(name) → {key: value}` (no secrets), `defaultModes(name) → {secretKey: "save"}`
  - `isShown(field, values) → bool`, `fieldsFor(name, values) → [field]`
  - `toBool(v) → bool`, `cycleChoice(field, value, step) → string`, `choiceLabel(field, value) → string`
  - `fromProfile(profile) → state` where state = `{type, uuid, name, values, modes, stored, advanced}` and each advanced row is `{key, value, secret, mode, stored, existing}`
  - `buildRequest(state) → request`, where state also carries `secretValues: {key: string}`. The request is `{type, name, uuid?, data, secrets: {k: {mode, value}}, native, user}`.
  - `validate(state) → null | {key, message}` (key `"name"`, a field key, or `"advanced"`)
  - `importableTypes(installed)`, `importExtensions(installed) → [".ovpn", …]`, `typeForPath(path, installed) → name|""`, `pickerTypes(installed) → [{name, label, advancedOnly, import}]`
  - Field object: `{key, label, kind: "text"|"secret"|"bool"|"choice"|"file"|"number", required?, default?, placeholder?, options?: [{value, label}], showIf?: {key: value|[values]}, askable?: false, common?: true}`

- [ ] **Step 1: Write the failing tests**

Create `quickshell/tests/tst_vpn_schema.qml`:

```qml
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
        { name: "openvpn", import: true }, { name: "wireguard", import: true }, { name: "l2tp", import: false }
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
        compare(Schema.importExtensions([{ name: "l2tp", import: false }]).length, 0)
    }
    function test_picker_types_order() {
        const t = Schema.pickerTypes([{ name: "wireguard", import: true }, { name: "fortisslvpn", import: false }, { name: "l2tp", import: false }])
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
```

- [ ] **Step 2: Run the tests to make sure they fail**

Run: `bash quickshell/tests/run.sh 2>&1 | tail -5`
Expected: FAIL. `VpnSchema` can't load `../services/vpnSchema.js` (file not found), and the other test files still pass.

- [ ] **Step 3: Write the implementation**

Create `quickshell/services/vpnSchema.js`:

```js
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
        { key: "connection-type", label: "Authentication", kind: "choice", default: "password", options: [{ value: "password", label: "Password" }, { value: "tls", label: "Certificates" }, { value: "password-tls", label: "Password and certificates" }, { value: "static-key", label: "Static key" }] },
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
    sstp: { label: "SSTP", service: "org.freedesktop.NetworkManager.sstp", importExt: [], fields: [
        { key: "gateway", label: "Gateway", kind: "text", required: true, placeholder: "vpn.example.com" },
        { key: "user", label: "Username", kind: "text" },
        { key: "password", label: "Password", kind: "secret" },
        { key: "domain", label: "NT domain", kind: "text" },
        { key: "ca-cert", label: "CA certificate", kind: "file" },
        { key: "ignore-cert-warn", label: "Ignore certificate warnings", kind: "bool", default: false },
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

// `nm-vpn get` profile → form state. Secret values never come back, only
// their modes ("save" | "ask" | "unset"); `stored` marks saved ones.
function fromProfile(p) {
    const name = p.type
    const values = defaults(name)
    const modes = defaultModes(name)
    const stored = {}
    const data = p.data || {}
    const native = p.native || {}
    const src = {}
    for (const k in data) src[k] = data[k]
    for (const k in native) src[k] = native[k]
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
    return { type: name, uuid: p.uuid || "", name: p.name || "", values: values, modes: modes, stored: stored, advanced: advanced }
}

// Form state → `nm-vpn add|update` request. Hidden fields are left out, so on
// update nm-vpn removes their data keys; secrets left out are kept as they are.
function buildRequest(state) {
    const name = state.type
    const native = isNative(name)
    const req = { type: name, name: String(state.name || "").trim(), data: {}, secrets: {}, native: {}, user: {} }
    if (state.uuid) req.uuid = state.uuid
    const sv = state.secretValues || {}
    const shown = fieldsFor(name, state.values)
    shown.forEach(f => {
        if (f.kind === "secret") {
            const mode = f.askable === false ? "save" : (state.modes[f.key] === "ask" ? "ask" : "save")
            req.secrets[f.key] = { mode: mode, value: String(sv[f.key] || "") }
            return
        }
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

function importableTypes(installed) { return (installed || []).filter(t => t.import) }
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
    return (installed || []).map(t => ({ name: t.name, label: typeLabel(t.name), advancedOnly: !hasSchema(t.name), import: !!t.import }))
        .sort((a, b) => {
            if (a.advancedOnly !== b.advancedOnly) return a.advancedOnly ? 1 : -1
            return a.label < b.label ? -1 : (a.label > b.label ? 1 : 0)
        })
}
```

The `;(info ? …)` leading semicolon stops the line from being parsed as a call on the previous line. Keep it.

- [ ] **Step 4: Run the tests to make sure they pass**

Run: `bash quickshell/tests/run.sh 2>&1 | tail -5`
Expected: `Totals: N passed, 0 failed`. Every `VpnSchema::test_*` passes, along with the existing suites.

- [ ] **Step 5: Commit**

```bash
git add quickshell/services/vpnSchema.js quickshell/tests/tst_vpn_schema.qml
git commit -m "feat(network): add VPN schema with unit tests

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 2: `nm-vpn` helper — protocol, logic and test backend

**Files:**
- Create: `quickshell/scripts/nm-vpn.py`
- Create: `quickshell/tests/test_nm_vpn.py`, `quickshell/tests/test-nm-vpn.sh`

**Interfaces:**
- Consumes: nothing (stdlib only; libnm arrives in Task 3).
- Produces:
  - CLI: `nm-vpn types|get|add|update|import|connect`, with one JSON request on stdin and one JSON line on stdout (shapes in Global Constraints and spec §7). `get` reports secret modes as `"save" | "ask" | "unset"`.
  - Internal record `rec` (what both backends load and store): `{uuid, name, type, service, data: {str: str}, secrets: {key: value}, native: {str: str}, user: {str: str}}`. Plugin secret flags live in `data["<key>-flags"]`. WireGuard flags live in `native["wireguard.private-key-flags"]` and `native["peer.preshared-key-flags"]`. WireGuard `native` also carries `peer.count` and `connection.interface-name`.
  - Backend interface (Task 3 implements it with libnm): `types() → [{name, service, import}]`, `load(uuid) → rec` (secret values included), `create(rec) → uuid`, `save(rec)`, `import_file(type, path) → uuid`.
  - Pure functions: `scrub`, `request_secrets`, `mode_from_flags(flags, stored)`, `plan_secret(mode, value, current_flags, has_stored) → (flags, value|None)`, `get_flags`, `set_flags`, `secret_keys(rec)`, `describe(rec)`, `ask_keys(rec)`, `apply_request(rec, req)`, `new_record(req, service)`, `passwd_lines(rec, secrets)`, `nmcli_message(text)`, `split_list(text)`, `wg_ifname(name)`, `parse_edit(req, need_uuid)`.
  - Exceptions: `Failure(message)`, reported as `{"ok": false, "error": message}`.

- [ ] **Step 1: Write the failing tests**

Create `quickshell/tests/test_nm_vpn.py`:

```python
"""Tests for quickshell/scripts/nm-vpn.py: the pure logic, and the CLI against
the JSON-file backend (NM_VPN_FAKE_STATE) with a fake nmcli. No
NetworkManager is touched. Run: bash quickshell/tests/test-nm-vpn.sh"""
import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
HELPER = os.path.join(HERE, "..", "scripts", "nm-vpn.py")
_spec = importlib.util.spec_from_file_location("nm_vpn", HELPER)
nv = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(nv)

# Records argv and the passwd-file content; fails when FAKE_NMCLI_FAIL is set.
FAKE_NMCLI = r"""#!/usr/bin/env bash
printf '%s\n' "$@" > "$FAKE_NMCLI_ARGS"
pf=""; prev=""
for a in "$@"; do [[ $prev == passwd-file ]] && pf=$a; prev=$a; done
if [[ -n $pf ]]; then cat "$pf" > "$FAKE_NMCLI_PASSWD"; else : > "$FAKE_NMCLI_PASSWD"; fi
if [[ -n ${FAKE_NMCLI_FAIL:-} ]]; then
  echo "Error: Connection activation failed: $FAKE_NMCLI_FAIL" >&2
  exit 4
fi
echo "Connection successfully activated (D-Bus active path: /x/1)"
"""


def l2tp(**over):
    rec = {"uuid": "u", "name": "Office", "type": "l2tp", "service": "org.freedesktop.NetworkManager.l2tp",
           "data": {"gateway": "g", "user": "alice", "password-flags": "0", "ipsec-psk-flags": "2"},
           "secrets": {"password": "stored-pw"}, "native": {"ipv4.never-default": "no"}, "user": {}}
    rec.update(over)
    return rec


def edit(**over):
    req = {"type": "l2tp", "name": "Office", "data": {"gateway": "g"}, "secrets": {}, "native": {}, "user": {}}
    req.update(over)
    return req


class PureLogic(unittest.TestCase):
    def test_mode_from_flags(self):
        self.assertEqual(nv.mode_from_flags(0, True), "save")
        self.assertEqual(nv.mode_from_flags(0, False), "unset")
        self.assertEqual(nv.mode_from_flags(2, True), "ask")
        self.assertEqual(nv.mode_from_flags(1, True), "ask")   # agent-owned: nothing supplies it any more
        self.assertEqual(nv.mode_from_flags(4, False), "unset")

    def test_plan_secret(self):
        self.assertEqual(nv.plan_secret("ask", "x", 0, True), (2, ""))
        self.assertEqual(nv.plan_secret("save", "pw", 2, False), (0, "pw"))
        self.assertEqual(nv.plan_secret("save", "", 0, True), (0, None))
        self.assertEqual(nv.plan_secret("save", "", 2, False), (4, ""))
        self.assertEqual(nv.plan_secret("save", "", 0, False), (4, ""))

    def test_secret_keys_come_from_flags_and_values(self):
        self.assertEqual(nv.secret_keys(l2tp()), ["ipsec-psk", "password"])
        wg = {"type": "wireguard", "data": {}, "secrets": {}, "native": {"peer.public-key": "P"}, "user": {}}
        self.assertEqual(nv.secret_keys(wg), ["wireguard.private-key", "peer.preshared-key"])

    def test_describe_never_contains_values(self):
        d = nv.describe(l2tp())
        self.assertEqual(d["secrets"], {"password": "save", "ipsec-psk": "ask"})
        self.assertNotIn("stored-pw", json.dumps(d))

    def test_ask_keys(self):
        self.assertEqual(nv.ask_keys(l2tp()), ["ipsec-psk"])
        wg = {"type": "wireguard", "data": {}, "secrets": {},
              "native": {"peer.public-key": "P", "wireguard.private-key-flags": "2", "peer.preshared-key-flags": "2"}, "user": {}}
        self.assertEqual(nv.ask_keys(wg), ["wireguard.private-key"])   # a peer PSK is never asked

    def test_apply_keeps_flags_and_removes_absent_data(self):
        rec = nv.apply_request(l2tp(), edit(name="Office 2"))
        self.assertEqual(rec["name"], "Office 2")
        self.assertNotIn("user", rec["data"])
        self.assertEqual(rec["data"]["password-flags"], "0")
        self.assertEqual(rec["data"]["ipsec-psk-flags"], "2")
        self.assertEqual(rec["secrets"], {"password": "stored-pw"})   # secrets left out are kept

    def test_apply_secret_modes(self):
        rec = nv.apply_request(l2tp(), edit(secrets={"password": {"mode": "ask", "value": ""},
                                                     "ipsec-psk": {"mode": "save", "value": "psk"}}))
        self.assertEqual(rec["data"]["password-flags"], "2")
        self.assertNotIn("password", rec["secrets"])
        self.assertEqual(rec["data"]["ipsec-psk-flags"], "0")
        self.assertEqual(rec["secrets"]["ipsec-psk"], "psk")

    def test_apply_wireguard_multi_peer_keeps_peers(self):
        rec = {"uuid": "w", "name": "WG", "type": "wireguard", "service": None, "data": {}, "secrets": {"wireguard.private-key": "K"},
               "native": {"peer.count": "2", "peer.public-key": "P1", "connection.interface-name": "wg0",
                          "wireguard.private-key-flags": "0", "ipv4.addresses": "10.0.0.2/32"}, "user": {}}
        req = {"type": "wireguard", "name": "WG2", "data": {}, "secrets": {},
               "native": {"ipv4.addresses": "10.0.0.3/32", "peer.public-key": "OTHER"}, "user": {}}
        out = nv.apply_request(rec, req)
        self.assertEqual(out["native"]["peer.public-key"], "P1")
        self.assertEqual(out["native"]["peer.count"], "2")
        self.assertEqual(out["native"]["connection.interface-name"], "wg0")
        self.assertEqual(out["native"]["ipv4.addresses"], "10.0.0.3/32")
        self.assertEqual(out["secrets"]["wireguard.private-key"], "K")

    def test_apply_rejects_unknown_wireguard_secret(self):
        rec = {"uuid": "w", "name": "WG", "type": "wireguard", "service": None, "data": {}, "secrets": {}, "native": {}, "user": {}}
        with self.assertRaises(nv.Failure):
            nv.apply_request(rec, {"type": "wireguard", "name": "WG", "data": {}, "native": {}, "user": {},
                                   "secrets": {"password": {"mode": "save", "value": "x"}}})

    def test_passwd_lines(self):
        self.assertEqual(nv.passwd_lines(l2tp(), {"ipsec-psk": "a:b"}), "vpn.secrets.ipsec-psk:a:b\n")
        wg = {"type": "wireguard"}
        self.assertEqual(nv.passwd_lines(wg, {"wireguard.private-key": "K"}), "wireguard.private-key:K\n")
        with self.assertRaises(nv.Failure):
            nv.passwd_lines(l2tp(), {"ipsec-psk": "two\nlines"})

    def test_scrub_and_nmcli_message(self):
        self.assertEqual(nv.scrub("bad pw and pw2", ["pw", "pw2"]), "bad *** and ***")
        self.assertEqual(nv.nmcli_message("Warning: x\nError: Connection activation failed: boom\n"),
                         "Connection activation failed: boom")
        self.assertEqual(nv.nmcli_message(""), "")

    def test_wg_ifname_and_split_list(self):
        self.assertEqual(nv.wg_ifname("Home VPN (laptop)"), "wg-homevpnlapto")   # 12 characters after "wg-"
        self.assertLessEqual(len(nv.wg_ifname("x" * 40)), 15)
        self.assertEqual(nv.wg_ifname("!!!"), "wg-vpn")
        self.assertEqual(nv.split_list("10.0.0.2/32, fd00::2/128  1.1.1.1"), ["10.0.0.2/32", "fd00::2/128", "1.1.1.1"])

    def test_parse_edit_validation(self):
        with self.assertRaises(nv.Failure):
            nv.parse_edit({"type": "l2tp"}, False)                          # no name
        with self.assertRaises(nv.Failure):
            nv.parse_edit(edit(user={"color": "red"}), False)               # user keys need quickshell.
        with self.assertRaises(nv.Failure):
            nv.parse_edit(edit(data={"bad key": "x"}), False)
        with self.assertRaises(nv.Failure):
            nv.parse_edit(edit(secrets={"password": {"mode": "maybe", "value": ""}}), False)
        ok = nv.parse_edit(edit(data={"form:main:group": "staff"}), False)
        self.assertEqual(ok["data"]["form:main:group"], "staff")


class Cli(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        d = self.tmp.name
        self.state = os.path.join(d, "state.json")
        with open(self.state, "w") as f:
            json.dump({
                "types": [
                    {"name": "l2tp", "service": "org.freedesktop.NetworkManager.l2tp", "import": False},
                    {"name": "openvpn", "service": "org.freedesktop.NetworkManager.openvpn", "import": True},
                    {"name": "wireguard", "service": None, "import": True},
                ],
                "profiles": {"u-office": {k: v for k, v in l2tp(secrets={"password": "stored-pw-1"}).items() if k != "uuid"}},
                "imports": {"office.ovpn": {"name": "office", "type": "openvpn", "service": "org.freedesktop.NetworkManager.openvpn",
                                            "data": {"remote": "ovpn.example.com", "connection-type": "password"},
                                            "secrets": {}, "native": {}, "user": {}}},
            }, f)
        self.ovpn = os.path.join(d, "office.ovpn")
        with open(self.ovpn, "w") as f:
            f.write("client\n")
        self.nmcli = os.path.join(d, "nmcli")
        with open(self.nmcli, "w") as f:
            f.write(FAKE_NMCLI)
        os.chmod(self.nmcli, 0o755)
        self.args_file = os.path.join(d, "nmcli-args")
        self.passwd_file = os.path.join(d, "nmcli-passwd")
        self.env = dict(os.environ, NM_VPN_FAKE_STATE=self.state, NM_VPN_NMCLI_BIN=self.nmcli,
                        FAKE_NMCLI_ARGS=self.args_file, FAKE_NMCLI_PASSWD=self.passwd_file)
        self.env.pop("FAKE_NMCLI_FAIL", None)

    def tearDown(self):
        self.tmp.cleanup()

    def stored(self, uuid):
        with open(self.state) as f:
            return json.load(f)["profiles"][uuid]

    def run_cli(self, cmd, req, **extra):
        p = subprocess.run([sys.executable, "-I", HELPER, cmd], input=req if isinstance(req, str) else json.dumps(req),
                           env=dict(self.env, **extra), capture_output=True, text=True, timeout=30)
        lines = [ln for ln in p.stdout.splitlines() if ln.strip()]
        self.assertEqual(len(lines), 1, p.stdout + p.stderr)
        self.assertEqual(p.returncode, 0, p.stderr)
        return json.loads(lines[0])

    def test_types(self):
        r = self.run_cli("types", {})
        self.assertTrue(r["ok"])
        self.assertEqual([t["name"] for t in r["types"]], ["l2tp", "openvpn", "wireguard"])

    def test_get_never_returns_secret_values(self):
        r = self.run_cli("get", {"uuid": "u-office"})
        self.assertEqual(r["profile"]["secrets"], {"password": "save", "ipsec-psk": "ask"})
        self.assertNotIn("stored-pw-1", json.dumps(r))

    def test_get_unknown_uuid(self):
        r = self.run_cli("get", {"uuid": "nope"})
        self.assertFalse(r["ok"])
        self.assertIn("No VPN profile", r["error"])

    def test_add_then_store(self):
        r = self.run_cli("add", edit(name="New", secrets={"password": {"mode": "save", "value": "new-pw-2"},
                                                          "ipsec-psk": {"mode": "ask", "value": ""}}))
        self.assertEqual(r, {"ok": True, "uuid": "fake-2"})
        s = self.stored("fake-2")
        self.assertEqual(s["data"]["password-flags"], "0")
        self.assertEqual(s["data"]["ipsec-psk-flags"], "2")
        self.assertEqual(s["secrets"], {"password": "new-pw-2"})

    def test_add_empty_save_is_not_required(self):
        self.run_cli("add", edit(secrets={"password": {"mode": "save", "value": ""}}))
        self.assertEqual(self.stored("fake-2")["data"]["password-flags"], "4")

    def test_add_unknown_type(self):
        r = self.run_cli("add", edit(type="fortisslvpn"))
        self.assertFalse(r["ok"])
        self.assertIn("not installed", r["error"])

    def test_update_empty_secret_keeps_stored(self):
        r = self.run_cli("update", edit(uuid="u-office", name="Renamed", secrets={"password": {"mode": "save", "value": ""}}))
        self.assertTrue(r["ok"], r)
        s = self.stored("u-office")
        self.assertEqual(s["name"], "Renamed")
        self.assertEqual(s["secrets"]["password"], "stored-pw-1")
        self.assertNotIn("user", s["data"])          # left out → removed
        self.assertIn("ipsec-psk-flags", s["data"])  # flags are never dropped

    def test_update_to_ask_drops_stored(self):
        self.run_cli("update", edit(uuid="u-office", secrets={"password": {"mode": "ask", "value": ""}}))
        s = self.stored("u-office")
        self.assertEqual(s["data"]["password-flags"], "2")
        self.assertNotIn("password", s["secrets"])

    def test_update_type_mismatch(self):
        r = self.run_cli("update", edit(uuid="u-office", type="openvpn"))
        self.assertFalse(r["ok"])

    def test_import(self):
        r = self.run_cli("import", {"type": "openvpn", "path": self.ovpn})
        self.assertTrue(r["ok"], r)
        self.assertEqual(self.stored(r["uuid"])["type"], "openvpn")

    def test_import_missing_file(self):
        r = self.run_cli("import", {"type": "openvpn", "path": self.ovpn + ".nope"})
        self.assertFalse(r["ok"])
        self.assertIn("No such file", r["error"])

    def test_connect_needs_ask_secrets_first(self):
        r = self.run_cli("connect", {"uuid": "u-office"})
        self.assertEqual(r, {"ok": False, "need": ["ipsec-psk"], "type": "l2tp"})
        self.assertFalse(os.path.exists(self.args_file))   # nmcli never ran

    def test_connect_passes_secrets_on_a_pipe(self):
        r = self.run_cli("connect", {"uuid": "u-office", "secrets": {"ipsec-psk": "psk-secret-3"}})
        self.assertEqual(r, {"ok": True})
        with open(self.args_file) as f:
            args = f.read()
        self.assertNotIn("psk-secret-3", args)
        self.assertIn("passwd-file", args)
        self.assertIn("u-office", args)
        with open(self.passwd_file) as f:
            self.assertEqual(f.read(), "vpn.secrets.ipsec-psk:psk-secret-3\n")

    def test_connect_without_ask_secrets_has_no_passwd_file(self):
        self.run_cli("update", edit(uuid="u-office", secrets={"ipsec-psk": {"mode": "save", "value": "p"}}))
        self.assertEqual(self.run_cli("connect", {"uuid": "u-office"}), {"ok": True})
        with open(self.args_file) as f:
            self.assertNotIn("passwd-file", f.read())

    def test_connect_error_is_scrubbed(self):
        r = self.run_cli("connect", {"uuid": "u-office", "secrets": {"ipsec-psk": "psk-secret-3"}},
                         FAKE_NMCLI_FAIL="rejected psk-secret-3")
        self.assertFalse(r["ok"])
        self.assertEqual(r["error"], "Connection activation failed: rejected ***")

    def test_bad_json(self):
        r = self.run_cli("get", "not json")
        self.assertFalse(r["ok"])
        self.assertIn("not JSON", r["error"])

    def test_usage(self):
        p = subprocess.run([sys.executable, "-I", HELPER], input="", env=self.env, capture_output=True, text=True, timeout=30)
        self.assertEqual(p.returncode, 2)
        self.assertFalse(json.loads(p.stdout.strip())["ok"])


if __name__ == "__main__":
    unittest.main()
```

Create `quickshell/tests/test-nm-vpn.sh`:

```bash
#!/usr/bin/env bash
# Runs the nm-vpn helper tests (tests/test_nm_vpn.py): pure logic, plus the
# CLI against a JSON-file backend and a fake nmcli. No NetworkManager is
# touched. Run from anywhere: bash quickshell/tests/test-nm-vpn.sh
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
if python3 -I "$here/test_nm_vpn.py" -v; then
  echo "OK (nm-vpn tests)"
else
  echo "nm-vpn tests failed"
  exit 1
fi
```

- [ ] **Step 2: Run the tests to make sure they fail**

Run: `bash quickshell/tests/test-nm-vpn.sh 2>&1 | tail -5`
Expected: FAIL with `FileNotFoundError` for `../scripts/nm-vpn.py`.

- [ ] **Step 3: Write the helper (pure logic, JSON-file backend, CLI)**

Create `quickshell/scripts/nm-vpn.py`. `LibnmBackend` is added in Task 3. Until then `make_backend()` raises `Failure` when `NM_VPN_FAKE_STATE` isn't set.

```python
"""nm-vpn: VPN profiles for the Quickshell Network Center (NetworkService.qml).

    nm-vpn types|get|add|update|import|connect   < one JSON request on stdin

Prints exactly one JSON line: {"ok": true, ...} or {"ok": false, "error": ...}.
`connect` answers {"ok": false, "need": [keys], "type": t} while secrets set to
Ask are missing. Secrets travel only on stdin and, when connecting, through
nmcli's passwd-file on a pipe: never in argv, the environment or the output.
Reads and writes go through libnm (PyGObject) over D-Bus; connecting runs
`nmcli connection up uuid U passwd-file /dev/fd/N`, which makes nmcli a
one-shot secret agent for that activation.

Secret flags (NMSettingSecretFlags): 1 agent-owned, 2 not saved, 4 not
required. Save writes 0 (4 when there is no value), Ask writes 2. Flags 1 or 2
read as "ask": with nm-applet gone nothing else can supply them.

Test hooks (tests only): NM_VPN_FAKE_STATE=<json file> replaces libnm with a
JSON-file backend; NM_VPN_NMCLI_BIN overrides nmcli; NM_VPN_CONNECT_WAIT
overrides the 90 s activation wait.

Spec: quickshell/docs/superpowers/specs/2026-11-09-native-vpn-design.md
"""

import json
import os
import re
import subprocess
import sys

FLAG_AGENT_OWNED = 1
FLAG_NOT_SAVED = 2
FLAG_NOT_REQUIRED = 4
ASK_FLAGS = FLAG_AGENT_OWNED | FLAG_NOT_SAVED
WIREGUARD = "wireguard"
WG_SECRETS = ("wireguard.private-key", "peer.preshared-key")
WG_ASKABLE = ("wireguard.private-key",)
NATIVE_KEEP = ("peer.count", "connection.interface-name")
MAX_PASSWD_BYTES = 60000
KEY_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.:+-]*$")


class Failure(Exception):
    """A problem to report as {"ok": false, "error": ...}."""


# ---------- pure logic (tests/test_nm_vpn.py) ----------

def scrub(text, secrets):
    """Replace every secret in text with ***, longest first."""
    out = text or ""
    for s in sorted({s for s in secrets if s}, key=len, reverse=True):
        out = out.replace(s, "***")
    return out


def request_secrets(req):
    """Every secret value in a request (add/update objects or connect strings)."""
    secrets = req.get("secrets") if isinstance(req, dict) else None
    if not isinstance(secrets, dict):
        return []
    out = []
    for v in secrets.values():
        if isinstance(v, dict):
            v = v.get("value", "")
        if isinstance(v, str) and v:
            out.append(v)
    return out


def mode_from_flags(flags, stored):
    if flags & ASK_FLAGS:
        return "ask"
    return "save" if stored else "unset"


def plan_secret(mode, value, current_flags, has_stored):
    """(flags, value) to write for one requested secret. value None keeps the
    stored one; "" removes it."""
    if mode == "ask":
        return FLAG_NOT_SAVED, ""
    if value:
        return 0, value
    if has_stored and not current_flags & ASK_FLAGS:
        return 0, None
    return FLAG_NOT_REQUIRED, ""


def _flags_place(rec, key):
    return ("native" if rec["type"] == WIREGUARD else "data"), key + "-flags"


def get_flags(rec, key):
    section, fkey = _flags_place(rec, key)
    try:
        return int(rec[section].get(fkey, "0") or 0)
    except ValueError:
        return 0


def set_flags(rec, key, flags):
    section, fkey = _flags_place(rec, key)
    rec[section][fkey] = str(flags)


def secret_keys(rec):
    """Every secret a profile has: WireGuard's fixed ones, or each plugin key K
    with a K-flags data item or a stored value."""
    if rec["type"] == WIREGUARD:
        keys = ["wireguard.private-key"]
        if rec["native"].get("peer.public-key"):
            keys.append("peer.preshared-key")
        return keys
    keys = {k[: -len("-flags")] for k in rec["data"] if k.endswith("-flags")}
    keys.update(rec["secrets"])
    return sorted(keys)


def describe(rec):
    """A profile for `get`: settings and secret modes, never secret values."""
    secrets = {k: mode_from_flags(get_flags(rec, k), bool(rec["secrets"].get(k))) for k in secret_keys(rec)}
    native = {k: v for k, v in rec["native"].items() if not k.endswith("-flags")}
    return {"uuid": rec["uuid"], "name": rec["name"], "type": rec["type"], "data": dict(rec["data"]),
            "secrets": secrets, "native": native, "user": dict(rec["user"])}


def ask_keys(rec):
    """Secrets a connect must be given (a WireGuard peer PSK is never asked)."""
    keys = [k for k, m in describe(rec)["secrets"].items() if m == "ask"]
    if rec["type"] == WIREGUARD:
        keys = [k for k in keys if k in WG_ASKABLE]
    return sorted(keys)


def apply_request(rec, req):
    """Merge a parsed add/update request into rec (mutated and returned).
    Data keys left out are removed, except *-flags; secrets left out are kept;
    a WireGuard profile with more than one peer keeps its peers."""
    rec["name"] = req["name"]
    if rec["type"] == WIREGUARD:
        multi = int(rec["native"].get("peer.count") or 0) > 1
        native = {k: v for k, v in rec["native"].items()
                  if k.endswith("-flags") or k in NATIVE_KEEP or (multi and k.startswith("peer."))}
        native.update({k: v for k, v in req["native"].items() if not (multi and k.startswith("peer."))})
        rec["native"] = native
    else:
        data = {k: v for k, v in rec["data"].items() if k.endswith("-flags")}
        data.update(req["data"])
        rec["data"] = data
        rec["native"] = dict(req["native"])
    rec["user"].update(req["user"])
    for key, s in req["secrets"].items():
        if rec["type"] == WIREGUARD and key not in WG_SECRETS:
            raise Failure("unknown WireGuard secret %s" % key)
        mode = "save" if key == "peer.preshared-key" else s["mode"]
        flags, value = plan_secret(mode, s["value"], get_flags(rec, key), bool(rec["secrets"].get(key)))
        set_flags(rec, key, flags)
        if value is None:
            continue
        if value:
            rec["secrets"][key] = value
        else:
            rec["secrets"].pop(key, None)
    return rec


def new_record(req, service):
    rec = {"uuid": None, "name": "", "type": req["type"], "service": service,
           "data": {}, "secrets": {}, "native": {}, "user": {}}
    return apply_request(rec, req)


def passwd_lines(rec, secrets):
    """nmcli passwd-file content for the given secrets."""
    out = []
    for key in sorted(secrets):
        value = secrets[key]
        if "\n" in value or "\r" in value:
            raise Failure("A secret cannot contain a line break")
        if rec["type"] == WIREGUARD:
            if key not in WG_ASKABLE:
                raise Failure("%s cannot be given when connecting" % key)
            out.append("%s:%s\n" % (key, value))
        else:
            out.append("vpn.secrets.%s:%s\n" % (key, value))
    return "".join(out)


def nmcli_message(text):
    """The most useful line of nmcli's output, without the "Error:" prefix."""
    lines = [ln.strip() for ln in (text or "").splitlines() if ln.strip()]
    errors = [ln for ln in lines if ln.startswith("Error:")]
    msg = errors[-1] if errors else (lines[-1] if lines else "")
    return msg[len("Error:"):].strip() if msg.startswith("Error:") else msg


def split_list(text):
    return [p for p in re.split(r"[,\s]+", text or "") if p]


def wg_ifname(name):
    """An interface name for a new WireGuard profile (at most 15 characters)."""
    base = re.sub(r"[^a-z0-9]", "", (name or "").lower())[:12]
    return "wg-" + (base or "vpn")


def need_str(req, key):
    v = req.get(key)
    if not isinstance(v, str) or not v.strip():
        raise Failure("missing %s" % key)
    return v.strip()


def str_map(value, what):
    if value is None:
        return {}
    if not isinstance(value, dict) or not all(isinstance(k, str) and isinstance(v, str) for k, v in value.items()):
        raise Failure("%s must map strings to strings" % what)
    return dict(value)


def parse_edit(req, need_uuid):
    out = {"type": need_str(req, "type"), "name": need_str(req, "name")}
    if need_uuid:
        out["uuid"] = need_str(req, "uuid")
    out["data"] = str_map(req.get("data"), "data")
    out["native"] = str_map(req.get("native"), "native")
    out["user"] = str_map(req.get("user"), "user")
    for k in out["user"]:
        if not k.startswith("quickshell."):
            raise Failure("user keys must start with quickshell.")
    raw = req.get("secrets") or {}
    if not isinstance(raw, dict):
        raise Failure("secrets must be an object")
    secrets = {}
    for k, v in raw.items():
        if not isinstance(v, dict) or v.get("mode") not in ("save", "ask") or not isinstance(v.get("value", ""), str):
            raise Failure("bad secret %s" % k)
        secrets[k] = {"mode": v["mode"], "value": v.get("value", "")}
    out["secrets"] = secrets
    for k in list(out["data"]) + list(secrets):
        if not KEY_RE.match(k):
            raise Failure("bad key %r" % k)
    return out


# ---------- connecting ----------

def nmcli_up(uuid, payload, secrets):
    """nmcli connection up, with payload (passwd-file lines) on a pipe."""
    nmcli = os.environ.get("NM_VPN_NMCLI_BIN", "nmcli")
    wait = int(os.environ.get("NM_VPN_CONNECT_WAIT", "90"))
    args = [nmcli, "--wait", str(wait), "connection", "up", "uuid", uuid]
    if len(payload.encode()) > MAX_PASSWD_BYTES:
        raise Failure("Secrets are too long")
    read_end = None
    fds = ()
    if payload:
        read_end, write_end = os.pipe()
        os.write(write_end, payload.encode())   # fits the pipe buffer, so this never blocks
        os.close(write_end)
        args += ["passwd-file", "/dev/fd/%d" % read_end]
        fds = (read_end,)
    try:
        proc = subprocess.run(args, pass_fds=fds, capture_output=True, text=True, timeout=wait + 15)
    except FileNotFoundError:
        raise Failure("nmcli not found")
    except subprocess.TimeoutExpired:
        raise Failure("Timed out connecting")
    finally:
        if read_end is not None:
            os.close(read_end)
    if proc.returncode != 0:
        msg = nmcli_message(proc.stderr) or nmcli_message(proc.stdout) or "nmcli exited with code %d" % proc.returncode
        raise Failure(scrub(msg, secrets))


# ---------- commands ----------

def service_for(backend, type_name):
    if type_name == WIREGUARD:
        return None
    for t in backend.types():
        if t["name"] == type_name:
            return t["service"]
    raise Failure("VPN type %s is not installed" % type_name)


def cmd_types(backend, req):
    return {"ok": True, "types": backend.types()}


def cmd_get(backend, req):
    return {"ok": True, "profile": describe(backend.load(need_str(req, "uuid")))}


def cmd_add(backend, req):
    r = parse_edit(req, need_uuid=False)
    rec = new_record(r, service_for(backend, r["type"]))
    return {"ok": True, "uuid": backend.create(rec)}


def cmd_update(backend, req):
    r = parse_edit(req, need_uuid=True)
    rec = backend.load(r["uuid"])
    if rec["type"] != r["type"]:
        raise Failure("%s is a %s profile, not %s" % (rec["name"], rec["type"], r["type"]))
    backend.save(apply_request(rec, r))
    return {"ok": True}


def cmd_import(backend, req):
    type_name = need_str(req, "type")
    path = os.path.expanduser(need_str(req, "path"))
    if not os.path.isfile(path):
        raise Failure("No such file: %s" % path)
    return {"ok": True, "uuid": backend.import_file(type_name, path)}


def cmd_connect(backend, req):
    uuid = need_str(req, "uuid")
    given = req.get("secrets") or {}
    if not isinstance(given, dict) or not all(isinstance(v, str) for v in given.values()):
        raise Failure("secrets must map keys to strings")
    rec = backend.load(uuid)
    asked = ask_keys(rec)
    missing = [k for k in asked if k not in given]
    if missing:
        return {"ok": False, "need": missing, "type": rec["type"]}
    wanted = {k: given[k] for k in asked}
    nmcli_up(uuid, passwd_lines(rec, wanted), list(wanted.values()))
    return {"ok": True}


HANDLERS = {"types": cmd_types, "get": cmd_get, "add": cmd_add, "update": cmd_update,
            "import": cmd_import, "connect": cmd_connect}


# ---------- backends ----------

class FakeBackend:
    """JSON-file stand-in for libnm (tests only: NM_VPN_FAKE_STATE)."""

    def __init__(self, path):
        self.path = path
        with open(path) as f:
            self.state = json.load(f)
        for k in ("types", "profiles", "imports"):
            self.state.setdefault(k, [] if k == "types" else {})

    def _write(self):
        with open(self.path, "w") as f:
            json.dump(self.state, f, indent=1, sort_keys=True)

    @staticmethod
    def _complete(rec):
        for k in ("data", "secrets", "native", "user"):
            rec.setdefault(k, {})
        rec.setdefault("service", None)
        return rec

    def types(self):
        return list(self.state["types"])

    def load(self, uuid):
        rec = self.state["profiles"].get(uuid)
        if rec is None:
            raise Failure("No VPN profile %s" % uuid)
        rec = self._complete(json.loads(json.dumps(rec)))
        rec["uuid"] = uuid
        return rec

    def _store(self, rec):
        stored = {k: v for k, v in rec.items() if k != "uuid"}
        # Like NetworkManager: only secrets with flags 0 are kept.
        stored["secrets"] = {k: v for k, v in rec["secrets"].items() if get_flags(rec, k) == 0}
        self.state["profiles"][rec["uuid"]] = stored
        self._write()

    def create(self, rec):
        rec["uuid"] = "fake-%d" % (len(self.state["profiles"]) + 1)
        self._store(rec)
        return rec["uuid"]

    def save(self, rec):
        self._store(rec)

    def import_file(self, type_name, path):
        src = self.state["imports"].get(os.path.basename(path))
        if src is None or src.get("type") != type_name:
            raise Failure("Cannot import %s as %s" % (os.path.basename(path), type_name))
        return self.create(self._complete(json.loads(json.dumps(src))))


def make_backend():
    fake = os.environ.get("NM_VPN_FAKE_STATE")
    if fake:
        return FakeBackend(fake)
    raise Failure("libnm backend not available")


# ---------- main ----------

def emit(result):
    sys.stdout.write(json.dumps(result) + "\n")
    sys.stdout.flush()


def main(argv):
    if len(argv) != 2 or argv[1] not in HANDLERS:
        emit({"ok": False, "error": "usage: nm-vpn <%s>" % "|".join(HANDLERS)})
        return 2
    raw = sys.stdin.read()
    try:
        req = json.loads(raw) if raw.strip() else {}
    except ValueError:
        emit({"ok": False, "error": "request is not JSON"})
        return 0
    if not isinstance(req, dict):
        emit({"ok": False, "error": "request must be a JSON object"})
        return 0
    secrets = request_secrets(req)
    try:
        result = HANDLERS[argv[1]](make_backend(), req)
    except Failure as e:
        result = {"ok": False, "error": scrub(str(e), secrets)}
    except Exception as e:  # never let a traceback (which may echo a request) escape
        result = {"ok": False, "error": scrub("internal error: %s" % e.__class__.__name__, secrets)}
    emit(result)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
```

- [ ] **Step 4: Run the tests to make sure they pass**

Run: `bash quickshell/tests/test-nm-vpn.sh 2>&1 | tail -5`
Expected: `OK` from unittest (every test listed `ok`), then `OK (nm-vpn tests)`.

- [ ] **Step 5: Commit**

```bash
git add quickshell/scripts/nm-vpn.py quickshell/tests/test_nm_vpn.py quickshell/tests/test-nm-vpn.sh
git commit -m "feat(network): add nm-vpn helper protocol with tests

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 3: libnm backend, packaging and the VPN plugins

**Files:**
- Modify: `quickshell/scripts/nm-vpn.py` (add `LibnmBackend`, change `make_backend`)
- Create: `quickshell/scripts/nm-vpn.nix`
- Modify: `nixos/programs/quickshell.nix` (the `let` block after `identity-passwd`, and `home.packages`)
- Modify: `nixos/configuration.nix:72`
- Create: `nixos/tests/test-vpn.sh`

**Interfaces:**
- Consumes: the backend interface and `rec` shape from Task 2.
- Produces: an `nm-vpn` package on the user's PATH, plus the system plugins `networkmanager-openvpn`, `-strongswan`, `-l2tp` and `-sstp`. `LibnmBackend` implements `types/load/create/save/import_file` against NetworkManager. Its correctness against a real daemon is proven in Task 5 (VM), not here.

- [ ] **Step 1: Write the failing evaluated-config test**

Create `nixos/tests/test-vpn.sh`:

```bash
#!/usr/bin/env bash
# Asserts the VPN wiring of the evaluated config: the NetworkManager VPN
# plugins the Network Center offers (/vpn), the nm-vpn helper in the user's
# packages, and services.strongswan kept for L2TP/IPsec.
# Run: bash nixos/tests/test-vpn.sh
set -uo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
STUB_DIR=$(mktemp -d)
trap 'rm -rf "$STUB_DIR"' EXIT
cp "$ROOT/nixos/tests/stub-machine.nix" "$STUB_DIR/hardware-configuration.nix"
printf '{ }\n' > "$STUB_DIR/machine.nix"

cat > "$STUB_DIR/check.nix" <<'NIX'
let
  root = builtins.getEnv "VPN_CHECK_ROOT";
  f = builtins.getFlake ("git+file://" + root + "?dir=nixos");
  c = f.nixosConfigurations.default.config;
  user = builtins.head (builtins.attrNames c.home-manager.users);
  names = ps: map (p: p.pname or p.name) ps;
in
{
  plugins = names c.networking.networkmanager.plugins;
  home = names c.home-manager.users.${user}.home.packages;
  strongswan = c.services.strongswan.enable;
}
NIX

result=$(VPN_CHECK_ROOT="$ROOT" DOTFILES_MACHINE_DIR="$STUB_DIR" \
  nix eval --impure --json --file "$STUB_DIR/check.nix")

failures=0
expect() { # jq-filter, description
  if [[ $(printf '%s' "$result" | jq -r "$1") == "true" ]]; then
    echo "OK   $2"
  else
    echo "FAIL $2 (result: $result)"
    failures=$((failures + 1))
  fi
}

expect '[.plugins[] | test("openvpn")] | any'    "the OpenVPN plugin is installed"
expect '[.plugins[] | test("l2tp")] | any'       "the L2TP plugin is installed"
expect '[.plugins[] | test("strongswan")] | any' "the strongSwan (IKEv2) plugin is installed"
expect '[.plugins[] | test("sstp")] | any'       "the SSTP plugin is installed"
expect '.home | index("nm-vpn") != null'         "nm-vpn is in the user's packages"
expect '.strongswan'                             "services.strongswan stays enabled (L2TP/IPsec)"

if ((failures)); then echo "$failures VPN config checks failed"; exit 1; fi
echo "OK (VPN config checks)"
```

- [ ] **Step 2: Run it to make sure it fails**

Run: `git add nixos/tests/test-vpn.sh && bash nixos/tests/test-vpn.sh`
Expected: `FAIL the OpenVPN plugin is installed`, plus FAILs for strongSwan, SSTP and nm-vpn. L2TP and strongswan pass. Exit 1.

- [ ] **Step 3: Add the libnm backend**

In `quickshell/scripts/nm-vpn.py`, add `import socket` to the imports (alphabetically after `re`). Then replace the whole `make_backend` function:

```python
def make_backend():
    fake = os.environ.get("NM_VPN_FAKE_STATE")
    if fake:
        return FakeBackend(fake)
    raise Failure("libnm backend not available")
```

with this (the libnm backend first, then `make_backend`):

```python
class LibnmBackend:
    """NetworkManager through libnm (PyGObject). Every D-Bus call has a 30 s
    timeout. Profiles are edited in place, so settings this helper doesn't
    manage (routes, proxy, permissions, ...) survive an update."""

    def __init__(self):
        try:
            import gi
            gi.require_version("NM", "1.0")
            from gi.repository import GLib, NM
        except (ImportError, ValueError) as e:
            raise Failure("libnm is not available: %s" % e)
        self.GLib, self.NM = GLib, NM
        try:
            self.client = NM.Client.new(None)
        except GLib.Error as e:
            raise Failure("NetworkManager is not reachable: %s" % e.message)
        self._plugins = None

    # --- plumbing ---
    def _call(self, start, finish):
        GLib = self.GLib
        loop = GLib.MainLoop()
        box = {}

        def done(src, res, *_):
            try:
                box["value"] = finish(src, res)
            except GLib.Error as e:
                box["error"] = e.message
            loop.quit()

        def expire():
            box.setdefault("error", "Timed out talking to NetworkManager")
            box["expired"] = True
            loop.quit()
            return False

        start(done)
        timer = GLib.timeout_add_seconds(30, expire)
        loop.run()
        if not box.get("expired"):
            GLib.source_remove(timer)
        if "error" in box:
            raise Failure(box["error"])
        return box.get("value")

    def plugins(self):
        if self._plugins is None:
            NM = self.NM
            out = []
            for info in NM.VpnPluginInfo.list_load():
                editor, can_import = None, False
                try:
                    editor = info.load_editor_plugin()
                    can_import = bool(editor.get_capabilities() & NM.VpnEditorPluginCapability.IMPORT)
                except self.GLib.Error:
                    pass
                out.append({"name": info.get_name(), "service": info.get_service(), "import": can_import, "_editor": editor})
            self._plugins = out
        return self._plugins

    def _type_for_service(self, service):
        for p in self.plugins():
            if p["service"] == service:
                return p["name"]
        return (service or "").rsplit(".", 1)[-1]

    def _remote(self, uuid):
        rc = self.client.get_connection_by_uuid(uuid)
        if rc is None:
            raise Failure("No VPN profile %s" % uuid)
        return rc

    def _add(self, conn):
        added = self._call(lambda cb: self.client.add_connection_async(conn, True, None, cb, None),
                           lambda src, res: src.add_connection_finish(res))
        return added.get_uuid()

    # --- interface ---
    def types(self):
        t = [{k: v for k, v in p.items() if not k.startswith("_")} for p in self.plugins()]
        t.append({"name": WIREGUARD, "service": None, "import": True})
        return t

    def load(self, uuid):
        rc = self._remote(uuid)
        ctype = rc.get_connection_type()
        if ctype == "vpn":
            setting_name = "vpn"
        elif ctype == "wireguard":
            setting_name = "wireguard"
        else:
            raise Failure("%s is not a VPN" % rc.get_id())
        try:   # secrets come back only for this caller; none at all is fine
            sec = self._call(lambda cb: rc.get_secrets_async(setting_name, None, cb, None),
                             lambda src, res: src.get_secrets_finish(res))
            if sec is not None:
                rc.update_secrets(setting_name, sec)
        except (Failure, self.GLib.Error):
            pass
        rec = {"uuid": uuid, "name": rc.get_id(), "service": None,
               "data": {}, "secrets": {}, "native": {}, "user": {}}
        if ctype == "vpn":
            s = rc.get_setting_vpn()
            rec["service"] = s.get_service_type()
            rec["type"] = self._type_for_service(rec["service"])
            for k in s.get_data_keys() or []:
                rec["data"][k] = s.get_data_item(k)
            for k in s.get_secret_keys() or []:
                rec["secrets"][k] = s.get_secret(k)
        else:
            rec["type"] = WIREGUARD
            self._read_wireguard(rc, rec)
        ip4 = rc.get_setting_ip4_config()
        if ip4 is not None:
            rec["native"]["ipv4.never-default"] = "yes" if ip4.get_never_default() else "no"
        s_user = rc.get_setting_by_name("user")
        if s_user is not None:
            for k in s_user.get_keys() or []:
                rec["user"][k] = s_user.get_data(k)
        return rec

    def _read_wireguard(self, conn, rec):
        n = rec["native"]
        s = conn.get_setting_by_name("wireguard")
        if s.get_private_key():
            rec["secrets"]["wireguard.private-key"] = s.get_private_key()
        n["wireguard.private-key-flags"] = str(int(s.get_private_key_flags()))
        if s.get_listen_port():
            n["wireguard.listen-port"] = str(s.get_listen_port())
        iface = conn.get_setting_connection().get_interface_name()
        if iface:
            n["connection.interface-name"] = iface
        addrs, dns = [], []
        for ip in (conn.get_setting_ip4_config(), conn.get_setting_ip6_config()):
            if ip is None:
                continue
            for i in range(ip.get_num_addresses()):
                a = ip.get_address(i)
                addrs.append("%s/%d" % (a.get_address(), a.get_prefix()))
            for i in range(ip.get_num_dns()):
                dns.append(ip.get_dns(i))
        if addrs:
            n["ipv4.addresses"] = ", ".join(addrs)
        if dns:
            n["ipv4.dns"] = ", ".join(dns)
        count = s.get_peers_len()
        n["peer.count"] = str(count)
        if count >= 1:
            p = s.get_peer(0)
            n["peer.public-key"] = p.get_public_key() or ""
            if p.get_endpoint():
                n["peer.endpoint"] = p.get_endpoint()
            ips = []
            for i in range(p.get_allowed_ips_len()):
                v = p.get_allowed_ip(i)
                ips.append(v[0] if isinstance(v, tuple) else v)
            if ips:
                n["peer.allowed-ips"] = ", ".join(ips)
            if p.get_persistent_keepalive():
                n["peer.persistent-keepalive"] = str(p.get_persistent_keepalive())
            n["peer.preshared-key-flags"] = str(int(p.get_preshared_key_flags()))
            if p.get_preshared_key():
                rec["secrets"]["peer.preshared-key"] = p.get_preshared_key()

    def _ip_settings(self, conn):
        NM = self.NM
        ip4 = conn.get_setting_ip4_config()
        if ip4 is None:
            ip4 = NM.SettingIP4Config.new()
            ip4.set_property("method", "auto")
            conn.add_setting(ip4)
        ip6 = conn.get_setting_ip6_config()
        if ip6 is None:
            ip6 = NM.SettingIP6Config.new()
            ip6.set_property("method", "auto")
            conn.add_setting(ip6)
        return ip4, ip6

    def _write_wireguard(self, conn, rec):
        NM, n = self.NM, rec["native"]
        s = conn.get_setting_by_name("wireguard")
        if s is None:
            s = NM.SettingWireGuard.new()
            conn.add_setting(s)
        s.set_property("private-key", rec["secrets"].get("wireguard.private-key"))
        s.set_property("private-key-flags", int(n.get("wireguard.private-key-flags", "0") or 0))
        s.set_property("listen-port", int(n.get("wireguard.listen-port") or 0))
        ip4, ip6 = self._ip_settings(conn)
        for ip in (ip4, ip6):
            ip.clear_addresses()
            ip.clear_dns()
        try:
            for a in split_list(n.get("ipv4.addresses", "")):
                v6 = ":" in a
                addr, _, prefix = a.partition("/")
                family = socket.AF_INET6 if v6 else socket.AF_INET
                (ip6 if v6 else ip4).add_address(NM.IPAddress.new(family, addr, int(prefix) if prefix else (128 if v6 else 32)))
        except (ValueError, self.GLib.Error) as e:
            raise Failure("Bad address: %s" % getattr(e, "message", e))
        for d in split_list(n.get("ipv4.dns", "")):
            (ip6 if ":" in d else ip4).add_dns(d)
        ip4.set_property("method", "manual" if ip4.get_num_addresses() else "disabled")
        ip6.set_property("method", "manual" if ip6.get_num_addresses() else "disabled")
        if int(n.get("peer.count") or 0) > 1:
            return                                  # several peers: left as imported
        s.clear_peers()
        if not n.get("peer.public-key"):
            return
        p = NM.WireGuardPeer.new()
        if not p.set_public_key(n["peer.public-key"], False):
            raise Failure("The peer public key is not a valid WireGuard key")
        if n.get("peer.endpoint") and not p.set_endpoint(n["peer.endpoint"], False):
            raise Failure("The peer endpoint must look like host:port")
        for ip in split_list(n.get("peer.allowed-ips", "")):
            if not p.append_allowed_ip(ip, False):
                raise Failure("Bad allowed IP %s" % ip)
        if n.get("peer.persistent-keepalive"):
            p.set_persistent_keepalive(int(n["peer.persistent-keepalive"]))
        psk = rec["secrets"].get("peer.preshared-key")
        if psk and not p.set_preshared_key(psk, False):
            raise Failure("The peer pre-shared key is not a valid WireGuard key")
        p.set_preshared_key_flags(int(n.get("peer.preshared-key-flags", "0") or 0))
        p.seal()
        s.append_peer(p)

    def _apply_to(self, conn, rec):
        NM = self.NM
        conn.get_setting_connection().set_property("id", rec["name"])
        if rec["type"] == WIREGUARD:
            self._write_wireguard(conn, rec)
        else:
            s = conn.get_setting_vpn()
            if s is None:
                s = NM.SettingVpn.new()
                conn.add_setting(s)
            s.set_property("service-type", rec["service"])
            for k in list(s.get_data_keys() or []):
                s.remove_data_item(k)
            for k in list(s.get_secret_keys() or []):
                s.remove_secret(k)
            for k, v in rec["data"].items():
                s.add_data_item(k, v)
            for k, v in rec["secrets"].items():
                s.add_secret(k, v)
        ip4, _ = self._ip_settings(conn)
        never = rec["native"].get("ipv4.never-default")
        if never is not None:
            ip4.set_property("never-default", never == "yes")
        if rec["user"]:
            s_user = conn.get_setting_by_name("user")
            if s_user is None:
                s_user = NM.SettingUser.new()
                conn.add_setting(s_user)
            for k, v in rec["user"].items():
                try:
                    s_user.set_data(k, v)
                except self.GLib.Error as e:
                    raise Failure("Bad user key %s: %s" % (k, e.message))

    def create(self, rec):
        NM = self.NM
        conn = NM.SimpleConnection.new()
        s_con = NM.SettingConnection.new()
        s_con.set_property("uuid", NM.utils_uuid_generate())
        s_con.set_property("type", "wireguard" if rec["type"] == WIREGUARD else "vpn")
        s_con.set_property("autoconnect", False)
        if rec["type"] == WIREGUARD:
            s_con.set_property("interface-name", rec["native"].get("connection.interface-name") or wg_ifname(rec["name"]))
        conn.add_setting(s_con)
        self._apply_to(conn, rec)
        return self._add(conn)

    def save(self, rec):
        rc = self._remote(rec["uuid"])            # load() already merged the secrets into rc
        conn = self.NM.SimpleConnection.new_clone(rc)
        self._apply_to(conn, rec)
        rc.replace_settings_from_connection(conn)
        self._call(lambda cb: rc.commit_changes_async(True, None, cb, None),
                   lambda src, res: src.commit_changes_finish(res))

    def import_file(self, type_name, path):
        NM, GLib = self.NM, self.GLib
        try:
            if type_name == WIREGUARD:
                conn = NM.conn_wireguard_import(path)
            else:
                p = next((p for p in self.plugins() if p["name"] == type_name), None)
                if p is None:
                    raise Failure("VPN type %s is not installed" % type_name)
                if not p["import"]:
                    raise Failure("%s cannot import files" % type_name)
                conn = p["_editor"].import_(path)
        except GLib.Error as e:
            raise Failure(e.message)
        return self._add(conn)


def make_backend():
    fake = os.environ.get("NM_VPN_FAKE_STATE")
    return FakeBackend(fake) if fake else LibnmBackend()
```

Notes for the implementer:
- `cmd_update` calls `backend.load()` and then `backend.save()` on the same `NM.Client` cache. `load()` fetched the secrets into the remote connection, and `save()` clones it, so secrets that `apply_request` didn't touch are written back unchanged.
- PyGObject exposes libnm's `import` as `import_` (because `import` is a Python keyword).

- [ ] **Step 4: Package the helper**

Create `quickshell/scripts/nm-vpn.nix`:

```nix
# nm-vpn: VPN profiles for the Quickshell Network Center (NetworkService.qml).
# Python + PyGObject, wrapped so libnm's typelib and nmcli are found.
# Tested by quickshell/tests/test-nm-vpn.sh and nixos/tests/test-vpn-vm.sh.
{ pkgs }:
let
  python = pkgs.python3.withPackages (ps: [ ps.pygobject3 ]);
  typelibs = pkgs.lib.makeSearchPath "lib/girepository-1.0" [
    pkgs.networkmanager
    pkgs.glib.out
    pkgs.gobject-introspection
  ];
in
pkgs.runCommand "nm-vpn" { nativeBuildInputs = [ pkgs.makeWrapper ]; } ''
  install -Dm644 ${./nm-vpn.py} $out/libexec/nm-vpn.py
  makeWrapper ${python}/bin/python3 $out/bin/nm-vpn \
    --add-flags $out/libexec/nm-vpn.py \
    --prefix GI_TYPELIB_PATH : ${typelibs} \
    --prefix PATH : ${pkgs.lib.makeBinPath [ pkgs.networkmanager ]}
''
```

In `nixos/programs/quickshell.nix`, replace:

```nix
  } (builtins.readFile ../../quickshell/scripts/identity-passwd.py);
in
```

with:

```nix
  } (builtins.readFile ../../quickshell/scripts/identity-passwd.py);

  # VPN profiles for the Network Center (NetworkService.qml): libnm through
  # PyGObject, secrets on stdin only. Tested by quickshell/tests/test-nm-vpn.sh
  # and nixos/tests/test-vpn-vm.sh.
  nm-vpn = import ../../quickshell/scripts/nm-vpn.nix { inherit pkgs; };
in
```

and replace:

```nix
    identity-passwd    # password changes for IdentityService (Identity Manager)
```

with:

```nix
    identity-passwd    # password changes for IdentityService (Identity Manager)
    nm-vpn             # VPN add/import/edit/connect for NetworkService (Network Center)
```

In `nixos/configuration.nix`, replace:

```nix
  networking.networkmanager.plugins = with pkgs; [ networkmanager-l2tp ];
```

with:

```nix
  # VPN types the Quickshell Network Center offers (/vpn); WireGuard is
  # built into NetworkManager.
  networking.networkmanager.plugins = with pkgs; [
    networkmanager-openvpn
    networkmanager-strongswan
    networkmanager-l2tp
    networkmanager-sstp
  ];
```

- [ ] **Step 5: Run the tests to make sure they pass**

Run:
```bash
git add quickshell/scripts/nm-vpn.nix
bash nixos/tests/test-vpn.sh
bash quickshell/tests/test-nm-vpn.sh 2>&1 | tail -1
nix flake check ./nixos --no-write-lock-file
```
Expected: six `OK` lines and then `OK (VPN config checks)`; `OK (nm-vpn tests)`; the flake check exits 0.

- [ ] **Step 6: Build the package and run `types`, read-only, against the live NetworkManager**

`types` only lists plugins. It creates and changes nothing.

```bash
out=$(nix build --no-link --print-out-paths --impure --expr \
  "import $PWD/quickshell/scripts/nm-vpn.nix { pkgs = (builtins.getFlake \"git+file://$PWD?dir=nixos\").inputs.nixpkgs.legacyPackages.\${builtins.currentSystem}; }")
printf '{}' | "$out/bin/nm-vpn" types
```
Expected: one line `{"ok": true, "types": [{"name": "l2tp", …, "import": …}, {"name": "wireguard", "service": null, "import": true}]}`. The live system only has the L2TP plugin until the user rebuilds. A `libnm is not available` error means a typelib isn't found. Run `grep GI_TYPELIB_PATH "$out/bin/nm-vpn"`, check that one of the listed directories holds `NM-1.0.typelib` and one holds `GLib-2.0.typelib`, then fix the `typelibs` list in `nm-vpn.nix`. Don't continue until `ok` is `true`.

- [ ] **Step 7: Commit**

```bash
git add quickshell/scripts/nm-vpn.py nixos/programs/quickshell.nix nixos/configuration.nix nixos/tests/test-vpn.sh
git commit -m "feat(network): libnm backend for nm-vpn, VPN plugins and packaging

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 4: Schema keys match the plugins

**Files:**
- Create: `quickshell/tests/test-vpn-schema-keys.sh`
- Modify (only if the test finds a wrong key): `quickshell/services/vpnSchema.js`, `quickshell/tests/tst_vpn_schema.qml`

**Interfaces:**
- Consumes: the one-line-per-field layout of `vpnSchema.js` (Task 1), and the plugin attribute names from Task 3.
- Produces: a permanent check that every `vpn.data`/`vpn.secrets` key in the schema exists in its plugin's binaries. A typo, or an upstream rename after a nixpkgs update, then fails here instead of at connect time.

- [ ] **Step 1: Write the test**

Create `quickshell/tests/test-vpn-schema-keys.sh`:

```bash
#!/usr/bin/env bash
# Every vpn.data / vpn.secrets key in services/vpnSchema.js must appear as a
# string in its NetworkManager plugin's binaries. Builds (usually fetches)
# the plugins from the flake's pinned nixpkgs. Native (WireGuard) and common
# fields are NetworkManager settings, not plugin keys, and are skipped.
# Run: bash quickshell/tests/test-vpn-schema-keys.sh
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
schema="$here/../services/vpnSchema.js"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

declare -A pkg=(
  [l2tp]=networkmanager-l2tp
  [openvpn]=networkmanager-openvpn
  [strongswan]=networkmanager-strongswan
  [sstp]=networkmanager-sstp
)

# "<type> <key>" for each plugin field, read from the one-line-per-field layout.
python3 - "$schema" > "$tmp/keys" <<'PY'
import re, sys
cur, native = None, False
for line in open(sys.argv[1]):
    m = re.match(r"^    ([a-z0-9]+): \{", line)
    if m:
        cur, native = m.group(1), "native: true" in line
        continue
    k = re.search(r'\{ key: "([^"]+)"', line)
    if cur and k and not native:
        print(cur, k.group(1))
PY

failures=0
for type in $(cut -d' ' -f1 "$tmp/keys" | sort -u); do
  attr=${pkg[$type]:-}
  if [[ -z $attr ]]; then echo "FAIL no plugin package known for schema type $type"; failures=$((failures + 1)); continue; fi
  out=$(nix build --no-link --print-out-paths --inputs-from "$root/nixos" "nixpkgs#$attr" 2>/dev/null | head -n 1)
  if [[ -z $out ]]; then echo "FAIL could not build $attr"; failures=$((failures + 1)); continue; fi
  find "$out" -type f \( -name '*.so*' -o -perm -u+x \) -exec strings {} + 2>/dev/null | sort -u > "$tmp/strings-$type"
  while read -r t key; do
    [[ $t == "$type" ]] || continue
    if grep -Fxq -- "$key" "$tmp/strings-$type"; then
      echo "OK   $type: $key"
    else
      echo "FAIL $type: \"$key\" is not a key of $attr"
      failures=$((failures + 1))
    fi
  done < "$tmp/keys"
done

if ((failures)); then echo "$failures schema key checks failed"; exit 1; fi
echo "OK (VPN schema keys match the plugins)"
```

- [ ] **Step 2: Run it**

Run: `bash quickshell/tests/test-vpn-schema-keys.sh`
Expected: an `OK` line per key. The L2TP keys were checked against the installed plugin while designing (spec §13), so they pass. The OpenVPN, strongSwan and SSTP keys come from those plugins' documentation and **may** show a FAIL.

- [ ] **Step 3: Fix any FAIL against the plugin's real key**

For each FAIL, find the real name in that plugin's strings, for example:
```bash
out=$(nix build --no-link --print-out-paths --inputs-from ./nixos nixpkgs#networkmanager-strongswan)
find "$out" -type f -name '*.so*' -exec strings {} + | sort -u | grep -iE 'cert|user|addr|method|virtual'
```
Change that field's `key` in `vpnSchema.js` (keep it one line). If you rename a key that `tst_vpn_schema.qml` mentions, update the test too. If a field has no matching key at all, delete it: Advanced still reaches any key the plugin has. Repeat Steps 2–3 until the whole test prints OK, then run `bash quickshell/tests/run.sh 2>&1 | tail -3` and expect `0 failed`.

- [ ] **Step 4: Commit**

```bash
git add quickshell/tests/test-vpn-schema-keys.sh quickshell/services/vpnSchema.js quickshell/tests/tst_vpn_schema.qml
git commit -m "test(network): check VPN schema keys against the plugins

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: NixOS VM test — real NetworkManager (answers spec §14)

**Files:**
- Create: `nixos/tests/vpn-vm.nix`, `nixos/tests/test-vpn-vm.sh`
- Modify (only if the VM finds a bug): `quickshell/scripts/nm-vpn.py`, `nixos/configuration.nix`

**Interfaces:**
- Consumes: `quickshell/scripts/nm-vpn.nix` (Task 3) and the evaluated `networking.networkmanager.plugins`.
- Produces: proof that `LibnmBackend` round-trips every type, plus written answers to three open questions. Record them in `## VM findings` at the end of this plan for Plan 2:
  1. Does `nmcli … passwd-file /dev/fd/N` (a pipe) work?
  2. Does `charon-nm` coexist with `services.strongswan`?
  3. What does `nm-vpn get` report for an imported OpenVPN profile?

- [ ] **Step 1: Write the VM test**

Create `nixos/tests/vpn-vm.nix`:

```nix
# NixOS VM test for nm-vpn against a real NetworkManager with the repo's VPN
# plugins (spec §14): libnm round-trips for every type, import, Save/Ask
# flags, passwd-file through a pipe, and charon-nm beside services.strongswan.
# Run by nixos/tests/test-vpn-vm.sh (needs KVM). Every value is a dummy.
{ pkgs, plugins }:
let
  nm-vpn = import ../../quickshell/scripts/nm-vpn.nix { inherit pkgs; };
in
pkgs.testers.runNixOSTest {
  name = "nm-vpn";
  nodes.machine = { ... }: {
    networking.networkmanager.enable = true;
    networking.networkmanager.plugins = plugins;
    services.strongswan.enable = true;
    users.users.alice = { isNormalUser = true; extraGroups = [ "networkmanager" ]; };
    environment.systemPackages = [ nm-vpn pkgs.wireguard-tools ];
    environment.etc."vpn-test/office.ovpn".text = ''
      client
      dev tun
      proto udp
      remote vpn.example.invalid 1194
      auth-user-pass
    '';
  };
  testScript = ''
    import json, shlex

    def vpn(cmd, req, env=""):
        line = "printf %s " + shlex.quote(json.dumps(req)) + " | su alice -s /bin/sh -c " + shlex.quote(env + " nm-vpn " + cmd)
        out = machine.succeed(line)
        lines = [l for l in out.splitlines() if l.strip()]
        assert len(lines) == 1, out
        return json.loads(lines[0])

    def ok(r):
        assert r.get("ok") is True, r
        return r

    def secrets_of(uuid):
        return machine.succeed(f"nmcli -s -g vpn.secrets connection show uuid {uuid}")

    machine.wait_for_unit("NetworkManager.service")
    machine.wait_until_succeeds("nmcli general status")

    with subtest("types lists the plugins and WireGuard"):
        t = {x["name"]: x for x in ok(vpn("types", {}))["types"]}
        for name in ("openvpn", "l2tp", "strongswan", "wireguard"):
            assert name in t, t
        assert t["openvpn"]["import"], t
        print("VM FINDING types: " + json.dumps(t))

    def roundtrip(type_name, data, key):
        req = {"type": type_name, "name": "t-" + type_name, "data": data,
               "secrets": {key: {"mode": "save", "value": "dummy-" + type_name}},
               "native": {"ipv4.never-default": "yes"}, "user": {"quickshell.vpn.test": "1"}}
        uuid = ok(vpn("add", req))["uuid"]
        p = ok(vpn("get", {"uuid": uuid}))["profile"]
        assert p["type"] == type_name, p
        for k, v in data.items():
            assert p["data"].get(k) == v, (k, p)
        assert p["secrets"].get(key) == "save", p
        assert "dummy-" not in json.dumps(p), p
        assert p["native"].get("ipv4.never-default") == "yes", p
        assert p["user"].get("quickshell.vpn.test") == "1", p
        assert "dummy-" + type_name in secrets_of(uuid)
        # an empty value keeps the stored secret
        req.update(uuid=uuid, name="t2-" + type_name, secrets={key: {"mode": "save", "value": ""}}, native={"ipv4.never-default": "no"})
        ok(vpn("update", req))
        assert "dummy-" + type_name in secrets_of(uuid)
        assert machine.succeed(f"nmcli -g connection.id connection show uuid {uuid}").strip() == "t2-" + type_name
        assert machine.succeed(f"nmcli -g ipv4.never-default connection show uuid {uuid}").strip() == "no"
        # switching to Ask writes flags 2 and drops the value
        req.update(secrets={key: {"mode": "ask", "value": ""}})
        ok(vpn("update", req))
        p = ok(vpn("get", {"uuid": uuid}))["profile"]
        assert p["secrets"][key] == "ask", p
        assert p["data"].get(key + "-flags") == "2", p
        assert "dummy-" + type_name not in secrets_of(uuid)
        return uuid

    with subtest("L2TP round-trip"):
        roundtrip("l2tp", {"gateway": "l2tp.example.invalid", "user": "alice", "ipsec-enabled": "yes"}, "password")
    with subtest("OpenVPN round-trip"):
        ovpn = roundtrip("openvpn", {"remote": "ovpn.example.invalid", "connection-type": "password", "username": "alice"}, "password")
    with subtest("strongSwan round-trip"):
        sw = roundtrip("strongswan", {"address": "ike.example.invalid", "method": "eap", "user": "alice", "virtual": "yes"}, "password")

    with subtest("OpenVPN import"):
        uuid = ok(vpn("import", {"type": "openvpn", "path": "/etc/vpn-test/office.ovpn"}))["uuid"]
        p = ok(vpn("get", {"uuid": uuid}))["profile"]
        assert p["type"] == "openvpn" and "vpn.example.invalid" in p["data"].get("remote", ""), p
        print("VM FINDING imported openvpn: " + json.dumps(p))

    with subtest("WireGuard add, import and several peers"):
        key = machine.succeed("wg genkey").strip()
        pub = machine.succeed(f"echo {key} | wg pubkey").strip()
        peer2 = machine.succeed("wg genkey | wg pubkey").strip()
        uuid = ok(vpn("add", {"type": "wireguard", "name": "wg-add", "data": {}, "user": {},
            "secrets": {"wireguard.private-key": {"mode": "save", "value": key}},
            "native": {"ipv4.addresses": "10.9.0.2/32, fd09::2/128", "ipv4.dns": "10.9.0.1", "peer.public-key": pub,
                       "peer.endpoint": "192.0.2.1:51820", "peer.allowed-ips": "0.0.0.0/0", "ipv4.never-default": "no"}}))["uuid"]
        p = ok(vpn("get", {"uuid": uuid}))["profile"]
        assert p["native"]["peer.public-key"] == pub, p
        assert "10.9.0.2/32" in p["native"]["ipv4.addresses"] and "fd09::2/128" in p["native"]["ipv4.addresses"], p
        assert p["secrets"]["wireguard.private-key"] == "save", p
        assert key not in json.dumps(p)
        conf = "[Interface]\nPrivateKey = %s\nAddress = 10.8.0.2/32\n\n[Peer]\nPublicKey = %s\nAllowedIPs = 10.8.0.0/24\nEndpoint = 192.0.2.2:51820\n\n[Peer]\nPublicKey = %s\nAllowedIPs = 10.7.0.0/24\nEndpoint = 192.0.2.3:51820\n" % (key, pub, peer2)
        machine.succeed("printf %s " + shlex.quote(conf) + " > /tmp/two.conf && chmod 644 /tmp/two.conf")
        uuid2 = ok(vpn("import", {"type": "wireguard", "path": "/tmp/two.conf"}))["uuid"]
        p = ok(vpn("get", {"uuid": uuid2}))["profile"]
        assert p["native"]["peer.count"] == "2", p
        ok(vpn("update", {"uuid": uuid2, "type": "wireguard", "name": "wg-renamed", "data": {}, "secrets": {}, "user": {},
                          "native": {"ipv4.addresses": "10.8.0.2/32", "ipv4.never-default": "no"}}))
        peers = machine.succeed(f"nmcli -t connection show uuid {uuid2} | grep -c '^wireguard-peer\\..*\\.endpoint:'").strip()
        assert peers == "2", peers

    with subtest("connect: the need handshake, then secrets through a passwd-file pipe"):
        r = vpn("connect", {"uuid": ovpn})
        assert r == {"ok": False, "need": ["password"], "type": "openvpn"}, r
        plain = machine.fail(f"su alice -s /bin/sh -c 'nmcli --wait 15 connection up uuid {ovpn}' 2>&1")
        piped = machine.fail("su alice -s /bin/bash -c " + shlex.quote(
            f"nmcli --wait 15 connection up uuid {ovpn} passwd-file <(printf 'vpn.secrets.password:dummy\\n')") + " 2>&1")
        print("VM FINDING passwd-file without: " + plain.strip())
        print("VM FINDING passwd-file via pipe: " + piped.strip())
        assert "Secrets were required" not in piped, piped
        r = vpn("connect", {"uuid": ovpn, "secrets": {"password": "dummy-pipe-secret"}}, env="NM_VPN_CONNECT_WAIT=15")
        assert r["ok"] is False and "Secrets were required" not in r["error"], r
        assert "dummy-pipe-secret" not in json.dumps(r), r

    with subtest("charon-nm runs beside services.strongswan"):
        machine.succeed("systemctl is-active strongswan.service")
        machine.execute("bash -c " + shlex.quote(
            f"nmcli --wait 15 connection up uuid {sw} passwd-file <(printf 'vpn.secrets.password:dummy\\n')"))
        log = machine.succeed("journalctl -b --no-pager | grep -iE 'charon-nm|charon|strongswan' || true")
        print("VM FINDING strongswan log tail: " + "\n".join(log.splitlines()[-15:]))
        assert "Address already in use" not in log, log
        assert "unable to bind" not in log.lower(), log
        machine.succeed("systemctl is-active strongswan.service")
  '';
}
```

Create `nixos/tests/test-vpn-vm.sh`:

```bash
#!/usr/bin/env bash
# Runs nixos/tests/vpn-vm.nix: a NixOS VM with NetworkManager, the repo's VPN
# plugins and nm-vpn (spec §14). Needs KVM and takes a few minutes; not part
# of `nix flake check`. Lines starting "VM FINDING" answer the open questions.
# Run: bash nixos/tests/test-vpn-vm.sh
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
if [[ ! -e /dev/kvm ]]; then echo "SKIP no /dev/kvm"; exit 0; fi
STUB_DIR=$(mktemp -d)
trap 'rm -rf "$STUB_DIR"' EXIT
cp "$ROOT/nixos/tests/stub-machine.nix" "$STUB_DIR/hardware-configuration.nix"
printf '{ }\n' > "$STUB_DIR/machine.nix"
cat > "$STUB_DIR/vm.nix" <<'NIX'
let
  root = builtins.getEnv "VPN_VM_ROOT";
  f = builtins.getFlake ("git+file://" + root + "?dir=nixos");
  c = f.nixosConfigurations.default.config;
  pkgs = f.inputs.nixpkgs.legacyPackages.${builtins.currentSystem};
in
import (root + "/nixos/tests/vpn-vm.nix") { inherit pkgs; plugins = c.networking.networkmanager.plugins; }
NIX
if VPN_VM_ROOT="$ROOT" DOTFILES_MACHINE_DIR="$STUB_DIR" \
   nix build --impure --no-link -L --file "$STUB_DIR/vm.nix" 2>&1 | tee "$STUB_DIR/log"; then
  grep -o 'VM FINDING.*' "$STUB_DIR/log" || true
  echo "OK (nm-vpn VM test)"
else
  grep -o 'VM FINDING.*' "$STUB_DIR/log" || true
  echo "FAIL nm-vpn VM test"
  exit 1
fi
```

Because of `set -o pipefail` (in the `set` line), a failed `nix build` fails the `if` even though its output goes through `tee`.

- [ ] **Step 2: Run it**

Run: `git add nixos/tests/vpn-vm.nix nixos/tests/test-vpn-vm.sh && bash nixos/tests/test-vpn-vm.sh 2>&1 | tail -40`
Expected: `OK (nm-vpn VM test)` plus the `VM FINDING` lines. A first run may FAIL in a subtest. That is this task's purpose.

- [ ] **Step 3: Fix what the VM finds, then re-run until it passes**

Fix the code, never the test's intent. Likely fixes:
- A PyGObject signature mismatch in `LibnmBackend` (the traceback names the method): correct the call in `nm-vpn.py`. Then run `bash quickshell/tests/test-nm-vpn.sh` again, since the fake-backend tests must stay green.
- **Pipe refused** (the `passwd-file via pipe` finding still says "Secrets were required"): in `nmcli_up`, replace the pipe with a file. Create it with `tempfile.mkstemp(dir=os.environ.get("XDG_RUNTIME_DIR") or None)`, then `os.fchmod(fd, 0o600)`, write the payload, pass its path, and `os.unlink` it in the `finally`. Update the spec §7 sentence to say which mechanism is used.
- **strongSwan clash** (the bind assertion fails): remove `networkmanager-strongswan` from `nixos/configuration.nix`, remove its expectation from `nixos/tests/test-vpn.sh` and `pkg[strongswan]` from `test-vpn-schema-keys.sh`, delete the `strongswan` schema entry from `vpnSchema.js`, and drop the `strongSwan round-trip` and `charon-nm` subtests. **Stop and tell the user** before going on: this changes what the spec promised.

- [ ] **Step 4: Record the findings**

Append to the end of this plan file:

```markdown
## VM findings (Task 5)

- passwd-file through a pipe: <works | refused — switched to a 0600 file in $XDG_RUNTIME_DIR>
- charon-nm beside services.strongswan: <coexist | clash — strongSwan plugin dropped>
- Imported OpenVPN profile as reported by `nm-vpn get`: <paste the VM FINDING line, secrets are modes only>
```

- [ ] **Step 5: Commit**

```bash
git add nixos/tests/vpn-vm.nix nixos/tests/test-vpn-vm.sh quickshell/scripts/nm-vpn.py quickshell/docs/superpowers/plans/2026-11-09-native-vpn.md
git commit -m "test(network): NixOS VM test for nm-vpn against NetworkManager

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 6: NetworkService VPN API, WireGuard fix and the smoke harness

**Files:**
- Modify: `quickshell/services/NetworkService.qml`
- Create: `quickshell/tests/smoke-vpn-views.sh`, `quickshell/tests/smoke/vpn-views.qml`

**Interfaces:**
- Consumes: the `nm-vpn` CLI (Tasks 2–3) and `VpnSchema.importExtensions` (Task 1).
- Produces, on the `NetworkService` singleton:
  - Properties: `helperAvailable: bool`, `vpnTypes: [{name, service, import}]`, `vpnNeed: [string]`, `vpnNeedUuid`, `vpnNeedName`, `vpnNeedType: string`, `importCandidates: [absolute path]`. Each `vpnConnections` entry gains `type` (`"vpn"` or `"wireguard"`).
  - Functions: `vpnConnect(uuid, secrets?)`, `vpnCancelNeed()`, `vpnLoad(uuid, cb)`, `vpnSave(request, cb)` (add when there's no `uuid`, else update), `vpnImport(type, path, cb)`, `loadVpnTypes()`, `refreshImportCandidates()`. Callbacks receive the helper's result object.
  - `busy` also covers a running helper request. An active WireGuard connection now sets `vpnActive`/`vpnName`.
  - Unchanged here (removed in Task 9): `launchEditor()`, `vpnAdd()`.

- [ ] **Step 1: Write the failing smoke test (service checks)**

Create `quickshell/tests/smoke-vpn-views.sh`:

```bash
#!/usr/bin/env bash
# Loads NetworkService and the Network Center VPN views inside Quickshell
# (offscreen, no compositor) and runs the checks in smoke/vpn-views.qml.
# HOME is a temporary directory with sample config files; nm-vpn and nmcli
# are stubs, so no real NetworkManager state is read or changed.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Quickshell only loads files under its config root: build one with the smoke
# shell at the top and copies of what the views import.
root="$tmp/qs"
mkdir -p "$root"
cp -r "$here/../components" "$here/../services" "$here/../theme" "$root/"
cp "$here/smoke/vpn-views.qml" "$root/shell.qml"

mkdir -p "$tmp/home/Downloads" "$tmp/home/Documents"
printf 'client\nremote vpn.example.com\n' > "$tmp/home/Downloads/office.ovpn"
printf '[Interface]\n' > "$tmp/home/Downloads/wg0.conf"
printf 'not a vpn\n' > "$tmp/home/Documents/notes.txt"

mkdir -p "$tmp/bin"
cat > "$tmp/bin/nmcli" <<'STUB'
#!/bin/sh
# Stand-in nmcli: three saved profiles and nothing else.
case "$*" in
  *"connection show"*) printf 'Office:uuid-l2tp:vpn\nHome WG:uuid-wg:wireguard\nCafe:uuid-wifi:802-11-wireless\n' ;;
esac
exit 0
STUB
cat > "$tmp/bin/nm-vpn" <<'STUB'
#!/usr/bin/env python3
# Stand-in nm-vpn: fixed answers; logs argv and the request for the checks below.
import json, os, sys
cmd = sys.argv[1] if len(sys.argv) > 1 else ""
req = json.loads(sys.stdin.read() or "{}")
with open(os.environ["NMVPN_LOG"], "a") as f:
    f.write(json.dumps({"argv": sys.argv[1:], "req": req}) + "\n")
TYPES = [{"name": "l2tp", "service": "org.freedesktop.NetworkManager.l2tp", "import": False},
         {"name": "openvpn", "service": "org.freedesktop.NetworkManager.openvpn", "import": True},
         {"name": "wireguard", "service": None, "import": True},
         {"name": "fortisslvpn", "service": "org.freedesktop.NetworkManager.fortisslvpn", "import": False}]
PROFILES = {
    "uuid-l2tp": {"uuid": "uuid-l2tp", "name": "Office", "type": "l2tp",
                  "data": {"gateway": "vpn.example.com", "user": "alice", "ipsec-enabled": "yes",
                           "password-flags": "0", "ipsec-psk-flags": "2", "lcp-echo-interval": "30"},
                  "secrets": {"password": "save", "ipsec-psk": "ask"},
                  "native": {"ipv4.never-default": "no"}, "user": {}},
    "uuid-imported": {"uuid": "uuid-imported", "name": "office", "type": "openvpn",
                      "data": {"remote": "vpn.example.com", "connection-type": "password"},
                      "secrets": {"password": "unset"}, "native": {"ipv4.never-default": "no"}, "user": {}},
}
if cmd == "types":
    out = {"ok": True, "types": TYPES}
elif cmd == "get":
    p = PROFILES.get(req.get("uuid"))
    out = {"ok": True, "profile": p} if p else {"ok": False, "error": "No VPN profile"}
elif cmd in ("add", "update"):
    out = {"ok": True, "uuid": req.get("uuid", "uuid-new")}
elif cmd == "import":
    out = {"ok": True, "uuid": "uuid-imported"}
elif cmd == "connect":
    has = "ipsec-psk" in (req.get("secrets") or {})
    out = {"ok": True} if has else {"ok": False, "need": ["ipsec-psk"], "type": "l2tp"}
else:
    out = {"ok": False, "error": "usage"}
print(json.dumps(out))
STUB
chmod +x "$tmp/bin/nmcli" "$tmp/bin/nm-vpn"
: > "$tmp/nm-vpn.log"

HOME="$tmp/home" PATH="$tmp/bin:$PATH" NMVPN_LOG="$tmp/nm-vpn.log" QS_NO_POLKIT_AGENT=1 \
  QT_QPA_PLATFORM=offscreen timeout 120 quickshell -p "$root/shell.qml" > "$tmp/log" 2>&1

grep -oE 'SMOKE (OK|FAIL|DONE).*' "$tmp/log"
fail=0
python3 - "$tmp/nm-vpn.log" <<'PY' || fail=1
import json, sys
calls = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
bad = 0
def ok(cond, msg):
    global bad
    print(("OK   " if cond else "FAIL ") + msg)
    if not cond:
        bad += 1
ok(all("smoke-secret" not in " ".join(c["argv"]) for c in calls), "secrets never reach nm-vpn's argv")
connects = [c for c in calls if c["argv"][:1] == ["connect"]]
ok(any((c["req"].get("secrets") or {}).get("ipsec-psk") == "smoke-secret-1" for c in connects),
   "an Ask secret reaches nm-vpn on stdin")
# --- log checks are added below by later tasks ---
sys.exit(1 if bad else 0)
PY
if ((fail)) || ! grep -q 'SMOKE DONE failures=0' "$tmp/log"; then
  echo "--- quickshell log (errors) ---"
  grep -iE 'error|warn|unavailable|cannot|failed' "$tmp/log" | head -20
  exit 1
fi
echo "OK (vpn view smoke tests)"
```

Create `quickshell/tests/smoke/vpn-views.qml`:

```qml
import QtQuick
import Quickshell
import "services"
// Views are created by path (make() and Qt.createComponent), so the
// components/launchers/network directory needs no import here and may not
// exist yet when this file is first added (Task 6).

// Smoke test for NetworkService's VPN API and the Network Center VPN views,
// run inside Quickshell from a temporary config root (see
// tests/smoke-vpn-views.sh: stub nm-vpn and nmcli, temporary HOME). Steps
// run one per timer tick so helper calls can finish in between. Prints one
// `SMOKE OK|FAIL <name>` line per check, then `SMOKE DONE`, and quits.
ShellRoot {
    id: shell
    property int failures: 0
    property int step: 0
    property var tv: null
    property var iv: null
    property var sp: null
    property var fv: null
    property string importedUuid: ""
    property bool fvSaved: false
    property bool loaded: false

    function check(name, cond, detail) {
        console.log((cond ? "SMOKE OK   " : "SMOKE FAIL ") + name + (cond || !detail ? "" : " — " + detail))
        if (!cond) failures++
    }
    function make(file) {
        const c = Qt.createComponent("components/launchers/network/" + file)
        if (c.status !== Component.Ready) { check(file + " loads", false, c.errorString()); return null }
        const o = c.createObject(win.contentItem, { width: 600 })
        check(file + " instantiates", o !== null)
        return o
    }
    function key(view, k) {
        const e = { key: k, text: "", modifiers: 0, accepted: false }
        view.handleKey(e)
        return e.accepted
    }
    function findFields(item, out) {
        for (let i = 0; i < item.children.length; i++) {
            const ch = item.children[i]
            if (ch.hasOwnProperty("placeholder") && ch.hasOwnProperty("input")) out.push(ch)
            findFields(ch, out)
        }
        return out
    }

    property var steps: [
        function () {
            check("service: nm-vpn found on PATH", NetworkService.helperAvailable)
            check("service: types loaded from nm-vpn", NetworkService.vpnTypes.length === 4, JSON.stringify(NetworkService.vpnTypes))
            check("service: the VPN list carries the type",
                  NetworkService.vpnConnections.some(v => v.name === "Home WG" && v.type === "wireguard"),
                  JSON.stringify(NetworkService.vpnConnections))
            check("service: Wi-Fi profiles are not VPNs", !NetworkService.vpnConnections.some(v => v.name === "Cafe"))
            NetworkService.vpnConnect("uuid-l2tp", {})
        },
        function () {
            check("service: Ask secrets come back as need",
                  NetworkService.vpnNeed.length === 1 && NetworkService.vpnNeed[0] === "ipsec-psk", JSON.stringify(NetworkService.vpnNeed))
            check("service: need names the profile",
                  NetworkService.vpnNeedUuid === "uuid-l2tp" && NetworkService.vpnNeedName === "Office" && NetworkService.vpnNeedType === "l2tp")
            check("service: not connecting while it asks", !NetworkService.connecting)
            NetworkService.vpnConnect("uuid-l2tp", { "ipsec-psk": "smoke-secret-1" })
        },
        function () {
            check("service: need cleared once connected", NetworkService.vpnNeed.length === 0)
            NetworkService.refreshImportCandidates()
        },
        function () {
            const c = NetworkService.importCandidates
            check("service: import candidates found",
                  c.some(p => p.endsWith("/Downloads/office.ovpn")) && c.some(p => p.endsWith("/Downloads/wg0.conf")), JSON.stringify(c))
            check("service: other files are not candidates", !c.some(p => p.endsWith("notes.txt")))
        },
        // --- view checks are added below by later tasks ---
        function () {
            console.log("SMOKE DONE failures=" + shell.failures)
            Qt.quit()
        }
    ]

    FloatingWindow {
        id: win
        visible: true
        implicitWidth: 620
        implicitHeight: 640
    }

    // The singleton is created on first use: start its probes now and give
    // them time before the first step (the real shell touches it at startup).
    Component.onCompleted: NetworkService.refresh()
    Timer {
        interval: 1000
        repeat: true
        running: true
        onTriggered: { const f = shell.steps[shell.step++]; if (f) f() }
    }
}
```

- [ ] **Step 2: Run it to make sure it fails**

Run: `bash quickshell/tests/smoke-vpn-views.sh`
Expected: `SMOKE FAIL service: nm-vpn found on PATH` (the property doesn't exist, so it's `undefined`), further FAILs and a non-zero exit.

- [ ] **Step 3: Add the API to `NetworkService.qml`**

Make these edits to `quickshell/services/NetworkService.qml`.

(a) Imports. Replace:
```qml
import QtQuick
import Quickshell.Io
```
with:
```qml
import QtQuick
import Quickshell.Io
import "vpnSchema.js" as VpnSchema
```

(b) Properties. Replace:
```qml
    property string _trafficIface: ""
    readonly property bool busy: nmUpProc.running || nmScanConnectProc.running || nmDownProc.running
```
with:
```qml
    property string _trafficIface: ""
    // Native VPN management through the nm-vpn helper
    // (docs/superpowers/specs/2026-11-09-native-vpn-design.md).
    property bool helperAvailable: false      // nm-vpn on PATH
    property var vpnTypes: []                 // [{name, service, import}] from `nm-vpn types`
    property var vpnNeed: []                  // secret keys a pending connect asks for
    property string vpnNeedUuid: ""
    property string vpnNeedName: ""
    property string vpnNeedType: ""
    property var importCandidates: []         // config files found by refreshImportCandidates()
    property var _helperCb: null
    property string _helperPayload: ""
    readonly property bool busy: nmUpProc.running || nmScanConnectProc.running || nmDownProc.running || helperProc.running
```

(c) Connect and the helper functions. Replace:
```qml
    function vpnConnect(uuid) { root.nmVpnUpProc.command = ["nmcli", "connection", "up", "uuid", uuid]; root.nmVpnUpProc.running = true }
```
with:
```qml
    // Connects through nm-vpn. Secrets set to Ask come back as `need`: the
    // Network Center prompts and calls this again with them. Without nm-vpn,
    // plain nmcli (no prompt).
    function vpnConnect(uuid, secrets) {
        const v = root.vpnConnections.filter(x => x.uuid === uuid)[0]
        const name = v ? v.name : ""
        root.lastError = ""
        if (!root.helperAvailable) {
            root.nmVpnUpProc.command = ["nmcli", "connection", "up", "uuid", uuid]
            root.nmVpnUpProc.running = true
            return
        }
        root.connecting = true
        root.connectingSsid = name
        root._runHelper("connect", { uuid: uuid, secrets: secrets || {} }, r => {
            root.connecting = false
            root.connectingSsid = ""
            if (r.ok) root.vpnCancelNeed()
            else if (r.need && r.need.length > 0) {
                root.vpnNeedUuid = uuid
                root.vpnNeedName = name
                root.vpnNeedType = r.type || ""
                root.vpnNeed = r.need             // last: listeners see the fields above
            } else {
                root.vpnCancelNeed()
                root.reportError(r.error || "VPN connection failed")
            }
            root.pollProc.running = true
            root.dataUpdated()
        })
    }
    function vpnCancelNeed() { root.vpnNeed = []; root.vpnNeedUuid = ""; root.vpnNeedName = ""; root.vpnNeedType = "" }
    function vpnLoad(uuid, cb) { root._runHelper("get", { uuid: uuid }, cb) }
    function vpnSave(request, cb) {
        root._runHelper(request.uuid ? "update" : "add", request, r => { if (r.ok) root.vpnProc.running = true; if (cb) cb(r) })
    }
    function vpnImport(type, path, cb) {
        root._runHelper("import", { type: type, path: path }, r => { if (r.ok) root.vpnProc.running = true; if (cb) cb(r) })
    }
    function loadVpnTypes() {
        root._runHelper("types", {}, r => { if (r.ok) { root.vpnTypes = r.types; root.dataUpdated() } })
    }
    function refreshImportCandidates() {
        if (root.importScanProc.running) return
        root.importScanProc.environment = ({ EXTS: VpnSchema.importExtensions(root.vpnTypes).join(" ") })
        root.importScanProc.running = true
    }
    function _runHelper(cmd, request, cb) {
        const done = cb || function () {}
        if (!root.helperAvailable) { done({ ok: false, error: "nm-vpn is not installed — run update" }); return }
        if (root.helperProc.running) { done({ ok: false, error: "Busy — try again" }); return }
        root._helperCb = done
        root._helperPayload = JSON.stringify(request || {})
        root.helperProc.command = ["nm-vpn", cmd]
        root.helperProc.running = true
    }
    function _helperDone(text) {
        const cb = root._helperCb
        root._helperCb = null
        const lines = (text || "").trim().split("\n")
        let r = null
        try { r = JSON.parse(lines[lines.length - 1]) } catch (e) { r = null }
        if (!r || typeof r !== "object") r = { ok: false, error: "nm-vpn gave no answer" }
        if (cb) cb(r)
    }
```

(d) Refresh reloads the types. Replace:
```qml
    function refresh() { root.pollProc.running = true; root.knownProc.running = true; root.vpnProc.running = true }
```
with:
```qml
    function refresh() { root.pollProc.running = true; root.knownProc.running = true; root.vpnProc.running = true; if (root.helperAvailable) root.loadVpnTypes() }
```

(e) The active-VPN check counts WireGuard, and only matches the TYPE column. In `pollProc`'s command string replace `nmcli -t -f NAME,TYPE connection show --active 2>/dev/null | grep vpn || true;` with `nmcli -t -f NAME,TYPE connection show --active 2>/dev/null | grep -E ':(vpn|wireguard)$' || true;`. Then replace:
```qml
                const vpnLines = vpnPart.trim().split("\n").filter(Boolean).filter(l => l.indexOf("vpn") !== -1)
```
with:
```qml
                const vpnLines = vpnPart.trim().split("\n").filter(Boolean).filter(l => /:(vpn|wireguard)$/.test(l))
```

(f) The VPN list carries the type and notifies the views. Replace:
```qml
        command: ["sh", "-c", "nmcli -t -f NAME,UUID,TYPE connection show 2>/dev/null | grep -E 'vpn|wireguard'"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = this.text.trim().split("\n").filter(Boolean)
                root.vpnConnections = lines.map(l => {
                    const p = root.splitTerse(l)
                    return ({ name: p[0] || "", uuid: p[1] || "", active: false })
                }).filter(v => v.name && v.uuid)
            }
```
with:
```qml
        command: ["sh", "-c", "nmcli -t -f NAME,UUID,TYPE connection show 2>/dev/null | grep -E ':(vpn|wireguard)$'"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = this.text.trim().split("\n").filter(Boolean)
                root.vpnConnections = lines.map(l => {
                    const p = root.splitTerse(l)
                    return ({ name: p[0] || "", uuid: p[1] || "", type: p[2] || "", active: false })
                }).filter(v => v.name && v.uuid)
                root.dataUpdated()
            }
```

(g) New processes. Insert this block directly above the line `    // Traffic for the current active connection: totals from /proc/net/dev,`:
```qml
    // nm-vpn is its own package (quickshell/scripts/nm-vpn.nix). Without it,
    // VPNs can still be listed, connected and deleted through nmcli.
    property Process vpnProbe: Process {
        command: ["sh", "-c", "command -v nm-vpn >/dev/null 2>&1 && echo 1 || echo 0"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.helperAvailable = this.text.trim() === "1"
                if (root.helperAvailable) root.loadVpnTypes()
                root.dataUpdated()
            }
        }
    }
    // One nm-vpn request at a time. The JSON request (secrets included) goes
    // to its stdin only and is dropped as soon as it has been written.
    property Process helperProc: Process {
        stdinEnabled: true
        onStarted: {
            root.helperProc.write(root._helperPayload)
            root._helperPayload = ""
            root.helperProc.stdinEnabled = false
        }
        stdout: StdioCollector { onStreamFinished: root._helperDone(this.text) }
        onExited: (exitCode, exitStatus) => {
            root._helperPayload = ""
            root.helperProc.stdinEnabled = true   // ready for the next request
        }
    }
    // Config files for the import view, newest first. EXTS holds the
    // extensions vpnSchema.js gives for the installed, import-capable types.
    property Process importScanProc: Process {
        command: ["sh", "-c", 'set --; for e in $EXTS; do [ $# -gt 0 ] && set -- "$@" -o; set -- "$@" -iname "*$e"; done; '
            + '[ $# -eq 0 ] && exit 0; '
            + 'for d in "$HOME/Downloads" "$HOME/Documents"; do [ -d "$d" ] && find "$d" -maxdepth 2 -type f \\( "$@" \\) -printf "%T@ %p\\n" 2>/dev/null; done '
            + '| sort -rn | head -n 200 | cut -d" " -f2-']
        stdout: StdioCollector {
            onStreamFinished: { root.importCandidates = this.text.split("\n").filter(Boolean); root.dataUpdated() }
        }
    }

```

(h) Start the probe. Replace:
```qml
    Component.onCompleted: { root.knownProc.running = true; root.vpnProc.running = true }
```
with:
```qml
    Component.onCompleted: { root.knownProc.running = true; root.vpnProc.running = true; root.vpnProbe.running = true }
```

- [ ] **Step 4: Run the smoke test to make sure it passes**

Run: `bash quickshell/tests/smoke-vpn-views.sh`
Expected: every `SMOKE OK`, `OK   secrets never reach nm-vpn's argv`, `OK   an Ask secret reaches nm-vpn on stdin`, then `OK (vpn view smoke tests)`.

- [ ] **Step 5: Check the shell still loads and the other suites pass**

Run:
```bash
timeout 5 quickshell -p "$PWD/quickshell" 2>&1 | grep -iE 'error|ReferenceError|TypeError' | head
bash quickshell/tests/run.sh 2>&1 | tail -2
bash quickshell/tests/smoke-identity-views.sh | tail -1
```
Expected: no QML error lines from `NetworkService.qml`. (Quickshell may print warnings that it can't take the layer shell when another instance is running. Those are fine.) Then `0 failed`, and `OK (identity view smoke tests)`.

- [ ] **Step 6: Commit**

```bash
git add quickshell/services/NetworkService.qml quickshell/tests/smoke-vpn-views.sh quickshell/tests/smoke/vpn-views.qml
git commit -m "feat(network): VPN API over nm-vpn in NetworkService; WireGuard counts as VPN

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 7: Type picker, import view and secret prompt

**Files:**
- Create: `quickshell/components/launchers/network/VpnRow.qml`, `VpnChip.qml`, `VpnTypeView.qml`, `VpnImportView.qml`, `VpnSecretPrompt.qml`
- Modify: `quickshell/tests/smoke/vpn-views.qml`, `quickshell/tests/smoke-vpn-views.sh`

**Interfaces:**
- Consumes: `NetworkService.vpnTypes`, `importCandidates`, `vpnImport`, `vpnNeed*`, `vpnConnect`, `vpnCancelNeed` (Task 6); `Schema.pickerTypes`, `importableTypes`, `typeForPath`, `importExtensions`, `labelFor` (Task 1); `SecretField` (existing, `components/launchers/SecretField.qml`: `text`, `placeholder`, `input`, `revealed`, `fieldEnabled`, signals `accepted`, `escaped`, `revealToggled`).
- Produces:
  - `VpnRow { icon, title, note, hint, selected, dim; signal clicked() }`
  - `VpnChip { first, second, onSecond; signal toggled(); signal advance(var from) }`: a two-option chip, toggled by Space or a click. Enter emits `advance`.
  - `VpnTypeView { reset(); handleKey(e); signal pickType(string name); signal importRequested(); signal back(); signal refocus(); rows }`
  - `VpnImportView { reset(); handleKey(e); signal imported(string uuid); signal back(); signal refocus(); files; choosingPath; typeChoices; sel; typeSel }`
  - `VpnSecretPrompt { focusFirst(); submit(); cancel(); clear(); signal done() }`, visible while `NetworkService.vpnNeed` isn't empty.

- [ ] **Step 1: Add the failing smoke checks**

In `quickshell/tests/smoke/vpn-views.qml`, replace the line
```qml
        // --- view checks are added below by later tasks ---
```
with:
```qml
        function () {
            const tv = shell.make("VpnTypeView.qml")
            if (!tv) return
            check("types: Import first, then 4 types", tv.rows.length === 5 && tv.rows[0].kind === "import", JSON.stringify(tv.rows))
            const last = tv.rows[tv.rows.length - 1]
            check("types: advanced-only types last", last.name === "fortisslvpn" && last.note === "advanced", JSON.stringify(last))
            let picked = ""
            tv.pickType.connect(n => picked = n)
            shell.key(tv, Qt.Key_J)
            shell.key(tv, Qt.Key_Return)
            check("types: j + Enter picks a type", picked === tv.rows[1].name, picked)
            let asked = false
            tv.importRequested.connect(() => asked = true)
            shell.key(tv, Qt.Key_K)
            shell.key(tv, Qt.Key_Return)
            check("types: Enter on Import asks for a file", asked)
            let back = false
            tv.back.connect(() => back = true)
            shell.key(tv, Qt.Key_Escape)
            check("types: Esc goes back", back)
            tv.destroy()
            shell.iv = shell.make("VpnImportView.qml")
            if (shell.iv) shell.iv.imported.connect(u => shell.importedUuid = u)
        },
        function () {
            const iv = shell.iv
            if (!iv) return
            check("import: lists the two candidates", iv.files.length === 2, JSON.stringify(iv.files))
            iv.sel = iv.files.findIndex(p => p.endsWith(".ovpn"))
            shell.key(iv, Qt.Key_Return)            // only OpenVPN claims .ovpn: imports at once
        },
        function () {
            const iv = shell.iv
            if (!iv) return
            check("import: .ovpn imports as OpenVPN at once", shell.importedUuid === "uuid-imported", shell.importedUuid)
            iv.sel = iv.files.findIndex(p => p.endsWith(".conf"))
            shell.key(iv, Qt.Key_Return)
            check("import: .conf asks which type", iv.choosingPath.endsWith("wg0.conf") && iv.typeChoices.length === 2,
                  JSON.stringify(iv.typeChoices))
            shell.key(iv, Qt.Key_Escape)
            check("import: Esc leaves the type question", iv.choosingPath === "")
            let back = false
            iv.back.connect(() => back = true)
            shell.key(iv, Qt.Key_Escape)
            check("import: a second Esc goes back", back)
            iv.destroy()
            shell.sp = shell.make("VpnSecretPrompt.qml")
            NetworkService.vpnConnect("uuid-l2tp", {})
        },
        function () {
            const sp = shell.sp
            if (!sp) return
            const f = shell.findFields(sp, [])
            check("prompt: one masked field per Ask secret", sp.visible && f.length === 1 && f[0].input.echoMode === TextInput.Password,
                  "visible=" + sp.visible + " fields=" + f.length)
            check("prompt: labelled from the schema", f.length === 1 && f[0].placeholder === "Pre-shared key", f.length ? f[0].placeholder : "")
            if (f.length === 1) {
                f[0].text = "smoke-secret-2"
                sp.submit()
                check("prompt: field cleared on submit", f[0].text === "")
            }
        },
        function () {
            check("prompt: hidden once connected", shell.sp !== null && !shell.sp.visible)
            if (shell.sp) shell.sp.destroy()
        },
        // --- view checks are added below by later tasks ---
```

In `quickshell/tests/smoke-vpn-views.sh`, replace the line
```python
# --- log checks are added below by later tasks ---
```
with:
```python
ok(any((c["req"].get("secrets") or {}).get("ipsec-psk") == "smoke-secret-2" for c in connects),
   "the prompt's secret reaches nm-vpn on stdin")
imports = [c for c in calls if c["argv"][:1] == ["import"]]
ok(any(c["req"].get("type") == "openvpn" and c["req"].get("path", "").endswith("office.ovpn") for c in imports),
   "the .ovpn file is imported as openvpn")
# --- log checks are added below by later tasks ---
```

- [ ] **Step 2: Run it to make sure it fails**

Run: `bash quickshell/tests/smoke-vpn-views.sh`
Expected: `SMOKE FAIL VpnTypeView.qml loads` (no such file) and a non-zero exit.

- [ ] **Step 3: Write the views**

Create `quickshell/components/launchers/network/VpnRow.qml`:

```qml
import QtQuick
import QtQuick.Layouts
import "../../../theme"

// One selectable row in the VPN views: glyph, title, note, hint on the right.
// State is shown by the border (STYLE.md §2.1).
Rectangle {
    id: row
    property string icon: ""
    property string title: ""
    property string note: ""
    property string hint: ""
    property bool selected: false
    property bool dim: false
    signal clicked()

    Layout.fillWidth: true
    implicitHeight: 40
    radius: Theme.roundingItem
    color: selected ? Theme.bgSelected : (ma.containsMouse ? Theme.bgHover : "transparent")
    border.color: selected ? Theme.borderSelected : Theme.border
    border.width: 1

    MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: row.clicked() }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Theme.padM
        anchors.rightMargin: Theme.padM
        spacing: Theme.gapM
        Text {
            visible: row.icon !== ""
            text: row.icon
            font.family: Theme.fontFamily
            font.pixelSize: 14
            color: row.dim ? Theme.fgDim : Theme.fg
            Layout.preferredWidth: 18
        }
        Text {
            text: row.title
            font.family: Theme.fontFamily
            font.pixelSize: 13
            color: row.dim ? Theme.fgDim : Theme.fg
            elide: Text.ElideMiddle
            Layout.fillWidth: true
        }
        Text { visible: row.note !== ""; text: row.note; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; color: Theme.fgMuted }
        Text { visible: row.hint !== ""; text: row.hint; font.family: Theme.fontFamily; font.pixelSize: 10; color: Theme.fgDim }
    }
}
```

Create `quickshell/components/launchers/network/VpnChip.qml`:

```qml
import QtQuick
import QtQuick.Layouts
import "../../../theme"

// Two-option chip (Save | Ask, Data | Secret). Space or a click toggles;
// Enter moves on (advance). The current option is bright, the other dim.
Rectangle {
    id: chip
    property string first: "Save"
    property string second: "Ask"
    property bool onSecond: false
    signal toggled()
    signal advance(var from)

    implicitWidth: 112
    implicitHeight: 36
    Layout.preferredWidth: implicitWidth
    Layout.preferredHeight: implicitHeight
    radius: Theme.roundingItem
    color: "transparent"
    border.color: chip.activeFocus ? Theme.borderSelected : Theme.border
    border.width: 1
    activeFocusOnTab: true

    Keys.onPressed: (e) => {
        if (e.key === Qt.Key_Space) { chip.toggled(); e.accepted = true }
        else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { chip.advance(chip); e.accepted = true }
    }

    RowLayout {
        anchors.centerIn: parent
        spacing: Theme.gapS
        Text {
            text: chip.first
            font.family: Theme.fontFamily
            font.pixelSize: 11
            font.weight: chip.onSecond ? Theme.fontWeightNormal : Theme.fontWeightMedium
            color: chip.onSecond ? Theme.fgDim : Theme.fgBright
        }
        Text { text: "|"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fgDim }
        Text {
            text: chip.second
            font.family: Theme.fontFamily
            font.pixelSize: 11
            font.weight: chip.onSecond ? Theme.fontWeightMedium : Theme.fontWeightNormal
            color: chip.onSecond ? Theme.fgBright : Theme.fgDim
        }
    }
    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { chip.forceActiveFocus(); chip.toggled() } }
}
```

Create `quickshell/components/launchers/network/VpnTypeView.qml`:

```qml
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../../theme"
import "../../../services"
import "../../../services/vpnSchema.js" as Schema

// Add VPN, step 1: import a file, or pick one of the installed VPN types
// (NetworkManager plugins plus WireGuard, NetworkService.vpnTypes).
// Spec: docs/superpowers/specs/2026-11-09-native-vpn-design.md §9.
Item {
    id: view
    property int sel: 0
    property string filter: ""
    readonly property var rows: {
        const all = [{ kind: "import", name: "", title: "Import from file…", note: "" }]
        Schema.pickerTypes(NetworkService.vpnTypes).forEach(t =>
            all.push({ kind: "type", name: t.name, title: t.label, note: t.advancedOnly ? "advanced" : "" }))
        const q = view.filter.trim().toLowerCase()
        return q === "" ? all : all.filter(r => r.title.toLowerCase().indexOf(q) !== -1)
    }
    signal pickType(string name)
    signal importRequested()
    signal back()
    signal refocus()

    implicitHeight: col.implicitHeight
    onRowsChanged: sel = Math.max(0, Math.min(sel, rows.length - 1))

    function reset() { sel = 0; filter = ""; filterField.text = ""; filterBox.visible = false }
    function activate() {
        const r = rows[sel]
        if (!r) return
        if (r.kind === "import") view.importRequested()
        else view.pickType(r.name)
    }
    // Keys the filter field does not consume land here.
    function handleKey(e) {
        if (e.key === Qt.Key_Escape) {
            if (filterBox.visible || filter !== "") { reset(); view.refocus() }
            else view.back()
            e.accepted = true
        } else if (e.key === Qt.Key_J || e.key === Qt.Key_Down) { sel = Math.min(rows.length - 1, sel + 1); e.accepted = true }
        else if (e.key === Qt.Key_K || e.key === Qt.Key_Up) { sel = Math.max(0, sel - 1); e.accepted = true }
        else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_L) { activate(); e.accepted = true }
        else if (e.text === "/") { filterBox.visible = true; filterField.forceActiveFocus(); e.accepted = true }
    }

    ColumnLayout {
        id: col
        width: parent.width
        spacing: Theme.gapS

        Rectangle {
            id: filterBox
            visible: false
            Layout.fillWidth: true
            Layout.preferredHeight: 36
            radius: Theme.roundingItem
            color: Theme.bgActive
            border.color: filterField.activeFocus ? Theme.borderSelected : Theme.border
            border.width: 1
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Theme.padM
                Text { text: Icons.search; font.family: Theme.fontFamily; font.pixelSize: 14; color: Theme.fgMuted }
                TextField {
                    id: filterField
                    Layout.fillWidth: true
                    placeholderText: "filter types…"
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                    color: Theme.fg
                    placeholderTextColor: Theme.fgDim
                    background: null
                    onTextChanged: view.filter = text
                    onAccepted: { filterBox.visible = false; view.refocus() }
                }
            }
        }
        Repeater {
            model: view.rows
            delegate: VpnRow {
                required property var modelData
                required property int index
                icon: modelData.kind === "import" ? Icons.download : Icons.vpn
                title: modelData.title
                note: modelData.note
                selected: index === view.sel
                onClicked: { view.sel = index; view.activate() }
            }
        }
        Text {
            visible: NetworkService.vpnTypes.length <= 1
            text: "More types: networking.networkmanager.plugins"
            font.family: Theme.fontFamily
            font.pixelSize: 11
            color: Theme.fgDim
        }
        Text {
            text: "j/k · Enter choose · / filter · Esc back"
            font.family: Theme.fontFamily
            font.pixelSize: 10
            color: Theme.fgDim
            Layout.alignment: Qt.AlignHCenter
        }
    }
}
```

Create `quickshell/components/launchers/network/VpnImportView.qml`:

```qml
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import "../../../theme"
import "../../../services"
import "../../../services/vpnSchema.js" as Schema

// Add VPN → Import from file: config files found in ~/Downloads and
// ~/Documents (NetworkService.importCandidates), or any typed path. The
// extension picks the type; when several installed types claim it, a short
// picker asks. nm-vpn creates the profile at once; the host then opens it in
// the form. No file-picker window. Spec §9.
Item {
    id: view
    property int sel: 0                       // index into files; files.length = the path box
    property string filter: ""
    property string choosingPath: ""          // non-empty: asking which type this file is
    property int typeSel: 0
    property bool busy: false
    property string message: ""
    readonly property string home: Quickshell.env("HOME") || ""
    readonly property var files: {
        const q = view.filter.trim().toLowerCase()
        const all = NetworkService.importCandidates
        return q === "" ? all : all.filter(p => p.toLowerCase().indexOf(q) !== -1)
    }
    readonly property var typeChoices: Schema.pickerTypes(Schema.importableTypes(NetworkService.vpnTypes))
    readonly property string extList: Schema.importExtensions(NetworkService.vpnTypes).join(" ")
    signal imported(string uuid)
    signal back()
    signal refocus()

    implicitHeight: col.implicitHeight

    function shortPath(p) { return home !== "" && p.indexOf(home + "/") === 0 ? "~" + p.slice(home.length) : p }
    function reset() {
        sel = 0; filter = ""; choosingPath = ""; typeSel = 0; busy = false; message = ""
        pathField.text = ""; filterField.text = ""; filterBox.visible = false
    }
    function importPath(p) {
        const path = String(p || "").trim()
        if (path === "" || busy) return
        const t = Schema.typeForPath(path, NetworkService.vpnTypes)
        if (t !== "") doImport(t, path)
        else if (typeChoices.length === 0) message = "No installed VPN type can import files"
        else { choosingPath = path; typeSel = 0; message = ""; view.refocus() }
    }
    function doImport(t, path) {
        busy = true
        message = ""
        NetworkService.vpnImport(t, path, r => {
            view.busy = false
            if (r.ok) { view.choosingPath = ""; view.imported(r.uuid) }
            else view.message = r.error || "Import failed"
        })
    }
    function activate() {
        if (choosingPath !== "") { const t = typeChoices[typeSel]; if (t) doImport(t.name, choosingPath); return }
        if (sel < files.length) importPath(files[sel])
        else pathField.forceActiveFocus()
    }
    // Keys the text fields do not consume land here.
    function handleKey(e) {
        if (e.key === Qt.Key_Escape) {
            if (pathField.activeFocus || filterField.activeFocus) { filterBox.visible = false; view.refocus() }
            else if (choosingPath !== "") { choosingPath = ""; message = "" }
            else if (filter !== "") { filter = ""; filterField.text = "" }
            else view.back()
            e.accepted = true
        } else if (e.key === Qt.Key_J || e.key === Qt.Key_Down) {
            if (choosingPath !== "") typeSel = Math.min(typeChoices.length - 1, typeSel + 1)
            else sel = Math.min(files.length, sel + 1)
            e.accepted = true
        } else if (e.key === Qt.Key_K || e.key === Qt.Key_Up) {
            if (choosingPath !== "") typeSel = Math.max(0, typeSel - 1)
            else sel = Math.max(0, sel - 1)
            e.accepted = true
        } else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { activate(); e.accepted = true }
        else if (e.text === "/" && choosingPath === "") { filterBox.visible = true; filterField.forceActiveFocus(); e.accepted = true }
    }

    ColumnLayout {
        id: col
        width: parent.width
        spacing: Theme.gapS

        // --- which type? ---
        Text {
            visible: view.choosingPath !== ""
            text: "Which type is " + view.shortPath(view.choosingPath) + "?"
            font.family: Theme.fontFamily
            font.pixelSize: 12
            color: Theme.fg
            elide: Text.ElideMiddle
            Layout.fillWidth: true
        }
        Repeater {
            model: view.choosingPath !== "" ? view.typeChoices : []
            delegate: VpnRow {
                required property var modelData
                required property int index
                icon: Icons.vpn
                title: modelData.label
                selected: index === view.typeSel
                onClicked: { view.typeSel = index; view.activate() }
            }
        }

        // --- files ---
        Rectangle {
            id: filterBox
            visible: false
            Layout.fillWidth: true
            Layout.preferredHeight: 36
            radius: Theme.roundingItem
            color: Theme.bgActive
            border.color: filterField.activeFocus ? Theme.borderSelected : Theme.border
            border.width: 1
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Theme.padM
                Text { text: Icons.search; font.family: Theme.fontFamily; font.pixelSize: 14; color: Theme.fgMuted }
                TextField {
                    id: filterField
                    Layout.fillWidth: true
                    placeholderText: "filter files…"
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                    color: Theme.fg
                    placeholderTextColor: Theme.fgDim
                    background: null
                    onTextChanged: { view.filter = text; view.sel = 0 }
                    onAccepted: { filterBox.visible = false; view.refocus() }
                }
            }
        }
        Text {
            visible: view.choosingPath === "" && view.files.length === 0
            text: view.extList === "" ? "No installed VPN type can import files"
                : "No " + view.extList + " files in ~/Downloads or ~/Documents"
            font.family: Theme.fontFamily
            font.pixelSize: 11
            color: Theme.fgDim
        }
        Repeater {
            model: view.choosingPath === "" ? view.files : []
            delegate: VpnRow {
                required property var modelData
                required property int index
                icon: Icons.download
                title: view.shortPath(modelData)
                selected: index === view.sel
                onClicked: { view.sel = index; view.activate() }
            }
        }
        Rectangle {
            visible: view.choosingPath === ""
            Layout.fillWidth: true
            Layout.preferredHeight: 36
            radius: Theme.roundingItem
            color: Theme.bgActive
            border.color: (pathField.activeFocus || view.sel === view.files.length) ? Theme.borderSelected : Theme.border
            border.width: 1
            TextField {
                id: pathField
                anchors.fill: parent
                anchors.leftMargin: Theme.padM
                anchors.rightMargin: Theme.padM
                placeholderText: "or type a path: ~/vpn/office.ovpn"
                font.family: Theme.fontFamily
                font.pixelSize: 13
                color: Theme.fg
                placeholderTextColor: Theme.fgDim
                background: null
                onAccepted: view.importPath(text)
            }
        }

        Text {
            visible: view.message !== "" || view.busy
            text: view.busy ? "Importing…" : Icons.warning + " " + view.message
            font.family: Theme.fontFamily
            font.pixelSize: 11
            color: view.busy ? Theme.fgMuted : Theme.critical
            wrapMode: Text.Wrap
            Layout.fillWidth: true
        }
        Text {
            text: view.choosingPath !== "" ? "j/k · Enter import as · Esc back" : "j/k · Enter import · / filter · Esc back"
            font.family: Theme.fontFamily
            font.pixelSize: 10
            color: Theme.fgDim
            Layout.alignment: Qt.AlignHCenter
        }
    }
}
```

Create `quickshell/components/launchers/network/VpnSecretPrompt.qml`:

```qml
import QtQuick
import QtQuick.Layouts
import "../../../theme"
import "../../../services"
import "../../../services/vpnSchema.js" as Schema
import ".."                                   // SecretField

// Connect-time prompt for secrets set to Ask (NetworkService.vpnNeed),
// inline in the /vpn view like the Wi-Fi password box. The values go to
// NetworkService.vpnConnect (→ nm-vpn stdin → nmcli passwd-file pipe), and
// the fields are cleared at once. Spec §9–10.
Rectangle {
    id: prompt
    property bool reveal: false
    readonly property var keys: NetworkService.vpnNeed
    signal done()

    visible: keys.length > 0
    Layout.fillWidth: true
    implicitHeight: col.implicitHeight + Theme.padL * 2
    radius: Theme.roundingItem
    color: Theme.bgActive
    border.color: Theme.borderSelected
    border.width: 1

    function fieldAt(i) { return rep.itemAt(i) }
    function focusFirst() { const f = fieldAt(0); if (f) f.forceActiveFocus() }
    function clear() {
        for (let i = 0; i < rep.count; i++) { const f = fieldAt(i); if (f) f.text = "" }
        reveal = false
    }
    function submit() {
        const secrets = {}
        for (let i = 0; i < rep.count; i++) { const f = fieldAt(i); if (f) secrets[prompt.keys[i]] = f.text }
        const uuid = NetworkService.vpnNeedUuid
        clear()
        NetworkService.vpnConnect(uuid, secrets)
        prompt.done()
    }
    function cancel() { clear(); NetworkService.vpnCancelNeed(); prompt.done() }

    ColumnLayout {
        id: col
        anchors.fill: parent
        anchors.margins: Theme.padL
        spacing: Theme.gapM
        RowLayout {
            spacing: Theme.gapM
            Layout.fillWidth: true
            Text { text: Icons.lock; font.family: Theme.fontFamily; font.pixelSize: 16; color: Theme.fg }
            Text {
                text: "Sign in to " + NetworkService.vpnNeedName
                font.family: Theme.fontFamily
                font.pixelSize: 13
                font.weight: Theme.fontWeightMedium
                color: Theme.fg
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
        }
        Repeater {
            id: rep
            model: prompt.keys
            delegate: SecretField {
                required property var modelData
                required property int index
                placeholder: Schema.labelFor(NetworkService.vpnNeedType, modelData)
                revealed: prompt.reveal
                onRevealToggled: prompt.reveal = !prompt.reveal
                onAccepted: { const next = prompt.fieldAt(index + 1); if (next) next.forceActiveFocus(); else prompt.submit() }
                onEscaped: prompt.cancel()
            }
        }
        Text {
            text: "Ctrl+s show/hide · Enter next / connect · Esc cancel"
            font.family: Theme.fontFamily
            font.pixelSize: 10
            color: Theme.fgDim
            Layout.alignment: Qt.AlignHCenter
        }
    }
}
```

- [ ] **Step 4: Run the smoke test to make sure it passes**

Run: `bash quickshell/tests/smoke-vpn-views.sh`
Expected: every `SMOKE OK`, four `OK` log lines, then `OK (vpn view smoke tests)`.

- [ ] **Step 5: Check for hard-coded colours or glyphs**

Run: `grep -nE '#[0-9a-fA-F]{3,8}\b|"\\u[0-9a-f]{4}"' quickshell/components/launchers/network/*.qml`
Expected: no output.

- [ ] **Step 6: Commit**

```bash
git add quickshell/components/launchers/network quickshell/tests/smoke/vpn-views.qml quickshell/tests/smoke-vpn-views.sh
git commit -m "feat(network): VPN type picker, import view and secret prompt

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 8: The VPN form

**Files:**
- Create: `quickshell/components/launchers/network/VpnFieldStop.qml`, `VpnAdvancedRow.qml`, `VpnFormView.qml`
- Modify: `quickshell/tests/smoke/vpn-views.qml`, `quickshell/tests/smoke-vpn-views.sh`

**Interfaces:**
- Consumes: `Schema.allFields`, `defaults`, `defaultModes`, `isShown`, `fromProfile`, `buildRequest`, `validate`, `toBool`, `cycleChoice`, `choiceLabel`, `hasSchema` (Task 1); `NetworkService.vpnSave`, `vpnLoad` (Task 6); `VpnChip` (Task 7); `SecretField`.
- Produces:
  - `VpnFieldStop { field, initial, checked, mode, stored, revealed; kind; focusInput(); secretText(); clearSecret(); signal edited(var value); signal modeToggled(); signal revealToggled(); signal advance(var from); signal escaped() }`
  - `VpnAdvancedRow { entry, revealed; focusKey(); signal changed(); signal revealToggled(); signal advance(var from); signal escaped() }`. Edits write straight into `entry`.
  - `VpnFormView { type, uuid, profileName, name, values, modes, stored, advanced, isEdit, dirty, busy, formError, confirmText; startAdd(type); startEdit(profile); reset(); focusFirst(); save(); handleKey(e); stopFor(key); visibleKeys(); signal back(); signal saved(); signal refocus() }`

- [ ] **Step 1: Add the failing smoke checks**

In `quickshell/tests/smoke/vpn-views.qml`, replace the line
```qml
        // --- view checks are added below by later tasks ---
```
with:
```qml
        function () {
            const fv = shell.make("VpnFormView.qml")
            shell.fv = fv
            if (!fv) return
            fv.saved.connect(() => shell.fvSaved = true)
            fv.startAdd("l2tp")
            check("form: l2tp stops in schema order",
                  JSON.stringify(fv.visibleKeys()) === JSON.stringify(["gateway", "user", "password", "ipsec-enabled", "ipsec-psk", "ipsec-gateway-id", "ipv4.never-default"]),
                  JSON.stringify(fv.visibleKeys()))
            const ipsec = fv.stopFor("ipsec-enabled")
            ipsec.checked = false
            ipsec.edited(false)
            check("form: turning IPsec off hides the PSK", fv.visibleKeys().indexOf("ipsec-psk") === -1, JSON.stringify(fv.visibleKeys()))
            fv.save()
            check("form: a missing name blocks Save", fv.formError === "Name is required", fv.formError)
            fv.stopFor("name").edited("Smoke")
            fv.save()
            check("form: a missing gateway blocks Save", fv.formError === "Gateway is required", fv.formError)
            fv.stopFor("gateway").edited("smoke.example.com")
            const pwf = shell.findFields(fv.stopFor("password"), [])
            check("form: the password is a masked field", pwf.length === 1 && pwf[0].input.echoMode === TextInput.Password)
            if (pwf.length === 1) pwf[0].text = "smoke-secret-3"
            fv.save()
            check("form: typed secrets are cleared once handed over", pwf.length === 1 && pwf[0].text === "")
            check("form: busy while saving", fv.busy)
        },
        function () {
            check("form: saved", shell.fvSaved)
            NetworkService.vpnLoad("uuid-l2tp", r => { if (r.ok) { shell.fv.startEdit(r.profile); shell.loaded = true } })
        },
        function () {
            const fv = shell.fv
            if (!fv) return
            check("form: edit is prefilled", shell.loaded && fv.uuid === "uuid-l2tp" && fv.name === "Office" && fv.values.gateway === "vpn.example.com")
            const pwf = shell.findFields(fv.stopFor("password"), [])
            check("form: a saved secret shows a placeholder, never a value",
                  pwf.length === 1 && pwf[0].text === "" && pwf[0].placeholder === "saved · leave empty to keep", pwf.length ? pwf[0].placeholder : "")
            check("form: an Ask secret keeps its mode", fv.stopFor("ipsec-psk").mode === "ask")
            check("form: unknown keys go to Advanced", fv.advanced.some(r => r.key === "lcp-echo-interval"))
            fv.stopFor("user").edited("bob")
            shell.key(fv, Qt.Key_Escape)
            check("form: Esc with changes asks first", fv.confirmText !== "")
            let back = false
            fv.back.connect(() => back = true)
            shell.key(fv, Qt.Key_Y)
            check("form: y discards and goes back", back && fv.type === "")
            fv.destroy()
        },
        // --- view checks are added below by later tasks ---
```

In `quickshell/tests/smoke-vpn-views.sh`, replace the line
```python
# --- log checks are added below by later tasks ---
```
with:
```python
adds = [c for c in calls if c["argv"][:1] == ["add"]]
ok(any(c["req"].get("data", {}).get("gateway") == "smoke.example.com"
       and c["req"].get("secrets", {}).get("password", {}).get("value") == "smoke-secret-3"
       and c["req"].get("data", {}).get("ipsec-enabled") == "no" for c in adds),
   "the form's add request carries its fields and the typed secret on stdin")
# --- log checks are added below by later tasks ---
```

- [ ] **Step 2: Run it to make sure it fails**

Run: `bash quickshell/tests/smoke-vpn-views.sh`
Expected: `SMOKE FAIL VpnFormView.qml loads` and a non-zero exit.

- [ ] **Step 3: Write the field stop**

Create `quickshell/components/launchers/network/VpnFieldStop.qml`:

```qml
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../../theme"
import "../../../services/vpnSchema.js" as Schema
import ".."                                   // SecretField

// One stop of VpnFormView, drawn from a vpnSchema.js field:
//   text | file | number → text box     secret → SecretField + Save | Ask chip
//   bool → toggle (Space)               choice → value cycled with Space / h / l
// Enter emits advance(from) so the form moves on; Tab follows the focus chain.
// A secret's value stays in its SecretField until the form collects it.
ColumnLayout {
    id: stop
    property var field: ({ key: "", label: "", kind: "text" })
    property string initial: ""          // text / file / number / choice value
    property bool checked: false         // bool value
    property string mode: "save"         // secret: save | ask
    property bool stored: false          // secret already saved in the profile
    property bool revealed: false
    readonly property string kind: field.kind || "text"
    readonly property bool askable: field.askable !== false
    readonly property bool asking: kind === "secret" && askable && mode === "ask"
    signal edited(var value)             // secrets emit null: their value stays here
    signal modeToggled()
    signal revealToggled()
    signal advance(var from)
    signal escaped()

    function focusInput() {
        if (kind === "secret") { if (asking) chip.forceActiveFocus(); else secret.forceActiveFocus() }
        else if (kind === "bool") toggle.forceActiveFocus()
        else if (kind === "choice") choice.forceActiveFocus()
        else box.forceActiveFocus()
    }
    function secretText() { return secret.text }
    function clearSecret() { secret.text = "" }
    function setChoice(step) {
        const v = Schema.cycleChoice(stop.field, stop.initial, step)
        stop.initial = v
        stop.edited(v)
    }
    function flip() { stop.checked = !stop.checked; stop.edited(stop.checked) }

    Layout.fillWidth: true
    spacing: 2

    Text {
        visible: stop.kind !== "bool"
        text: stop.field.label + (stop.field.required ? " *" : "")
        font.family: Theme.fontFamily
        font.pixelSize: 10
        color: Theme.fgMuted
    }

    // text / file / number
    Rectangle {
        visible: stop.kind === "text" || stop.kind === "file" || stop.kind === "number"
        Layout.fillWidth: true
        Layout.preferredHeight: 36
        radius: Theme.roundingItem
        color: Theme.bgActive
        border.color: box.activeFocus ? Theme.borderSelected : Theme.border
        border.width: 1
        TextField {
            id: box
            anchors.fill: parent
            anchors.leftMargin: Theme.padM
            anchors.rightMargin: Theme.padM
            text: stop.initial
            placeholderText: stop.field.placeholder || (stop.kind === "file" ? "~/path/to/file" : "")
            inputMethodHints: stop.kind === "number" ? Qt.ImhDigitsOnly : Qt.ImhNone
            font.family: Theme.fontFamily
            font.pixelSize: 13
            color: Theme.fg
            placeholderTextColor: Theme.fgDim
            background: null
            activeFocusOnTab: true
            onTextEdited: stop.edited(text)
            onAccepted: stop.advance(box)
        }
    }

    // secret
    RowLayout {
        visible: stop.kind === "secret"
        Layout.fillWidth: true
        spacing: Theme.gapS
        SecretField {
            id: secret
            revealed: stop.revealed
            fieldEnabled: !stop.asking
            placeholder: stop.asking ? "asked when you connect"
                : (stop.stored ? "saved · leave empty to keep" : "")
            onRevealToggled: stop.revealToggled()
            onAccepted: stop.advance(secret.input)
            onEscaped: stop.escaped()
            onTextChanged: if (text !== "") stop.edited(null)
        }
        VpnChip {
            id: chip
            visible: stop.askable
            first: "Save"
            second: "Ask"
            onSecond: stop.mode === "ask"
            onToggled: stop.modeToggled()
            onAdvance: (from) => stop.advance(from)
        }
    }

    // bool
    Rectangle {
        id: toggle
        visible: stop.kind === "bool"
        Layout.fillWidth: true
        Layout.preferredHeight: 36
        radius: Theme.roundingItem
        color: "transparent"
        border.color: toggle.activeFocus ? Theme.borderSelected : Theme.border
        border.width: 1
        activeFocusOnTab: true
        Keys.onPressed: (e) => {
            if (e.key === Qt.Key_Space) { stop.flip(); e.accepted = true }
            else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { stop.advance(toggle); e.accepted = true }
        }
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Theme.padM
            anchors.rightMargin: Theme.padM
            spacing: Theme.gapM
            Text { text: stop.checked ? Icons.check : ""; font.family: Theme.fontFamily; font.pixelSize: 13; color: Theme.fg; Layout.preferredWidth: 16 }
            Text { text: stop.field.label; font.family: Theme.fontFamily; font.pixelSize: 13; color: Theme.fg; elide: Text.ElideRight; Layout.fillWidth: true }
            Text { text: stop.checked ? "on" : "off"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fgMuted }
        }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { toggle.forceActiveFocus(); stop.flip() } }
    }

    // choice
    Rectangle {
        id: choice
        visible: stop.kind === "choice"
        Layout.fillWidth: true
        Layout.preferredHeight: 36
        radius: Theme.roundingItem
        color: "transparent"
        border.color: choice.activeFocus ? Theme.borderSelected : Theme.border
        border.width: 1
        activeFocusOnTab: true
        Keys.onPressed: (e) => {
            if (e.key === Qt.Key_Space || e.key === Qt.Key_L || e.key === Qt.Key_Right) { stop.setChoice(1); e.accepted = true }
            else if (e.key === Qt.Key_H || e.key === Qt.Key_Left) { stop.setChoice(-1); e.accepted = true }
            else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { stop.advance(choice); e.accepted = true }
        }
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Theme.padM
            anchors.rightMargin: Theme.padM
            Text { text: Icons.chevronLeft; font.family: Theme.fontFamily; font.pixelSize: 12; color: Theme.fgMuted }
            Text {
                text: Schema.choiceLabel(stop.field, stop.initial)
                font.family: Theme.fontFamily
                font.pixelSize: 13
                color: Theme.fg
                horizontalAlignment: Text.AlignHCenter
                Layout.fillWidth: true
            }
            Text { text: Icons.chevronRight; font.family: Theme.fontFamily; font.pixelSize: 12; color: Theme.fgMuted }
        }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { choice.forceActiveFocus(); stop.setChoice(1) } }
    }
}
```

- [ ] **Step 4: Write the Advanced row**

Create `quickshell/components/launchers/network/VpnAdvancedRow.qml`:

```qml
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../../theme"
import ".."                                   // SecretField

// One Advanced row of VpnFormView: `key = value`. Edits write straight into
// `entry` (an element of VpnFormView.advanced). Rows read from the profile
// keep their kind; a new row has a Data | Secret chip. A secret row masks its
// value and has a Save | Ask chip. Clearing the key removes the row on save.
RowLayout {
    id: row
    property var entry: ({ key: "", value: "", secret: false, mode: "save", stored: false, existing: false })
    property bool revealed: false
    property bool isSecret: entry.secret === true
    property string mode: entry.mode || "save"
    signal changed()
    signal revealToggled()
    signal advance(var from)
    signal escaped()

    function focusKey() { keyBox.forceActiveFocus() }

    Layout.fillWidth: true
    spacing: Theme.gapS

    Rectangle {
        Layout.preferredWidth: 170
        Layout.preferredHeight: 36
        radius: Theme.roundingItem
        color: Theme.bgActive
        border.color: keyBox.activeFocus ? Theme.borderSelected : Theme.border
        border.width: 1
        TextField {
            id: keyBox
            anchors.fill: parent
            anchors.leftMargin: Theme.padM
            anchors.rightMargin: Theme.padM
            text: row.entry.key
            placeholderText: "key"
            font.family: Theme.fontFamily
            font.pixelSize: 12
            color: Theme.fg
            placeholderTextColor: Theme.fgDim
            background: null
            activeFocusOnTab: true
            onTextEdited: { row.entry.key = text; row.changed() }
            onAccepted: row.advance(keyBox)
        }
    }
    Text { text: "="; font.family: Theme.fontFamily; font.pixelSize: 12; color: Theme.fgDim }
    VpnChip {
        visible: !row.entry.existing
        first: "Data"
        second: "Secret"
        onSecond: row.isSecret
        onToggled: {
            row.entry.secret = !row.isSecret
            row.isSecret = row.entry.secret
            row.entry.value = ""
            valueBox.text = ""
            secretBox.text = ""
            row.changed()
        }
        onAdvance: (from) => row.advance(from)
    }
    Rectangle {
        visible: !row.isSecret
        Layout.fillWidth: true
        Layout.preferredHeight: 36
        radius: Theme.roundingItem
        color: Theme.bgActive
        border.color: valueBox.activeFocus ? Theme.borderSelected : Theme.border
        border.width: 1
        TextField {
            id: valueBox
            anchors.fill: parent
            anchors.leftMargin: Theme.padM
            anchors.rightMargin: Theme.padM
            text: row.isSecret ? "" : row.entry.value
            placeholderText: "value"
            font.family: Theme.fontFamily
            font.pixelSize: 12
            color: Theme.fg
            placeholderTextColor: Theme.fgDim
            background: null
            activeFocusOnTab: true
            onTextEdited: { row.entry.value = text; row.changed() }
            onAccepted: row.advance(valueBox)
        }
    }
    SecretField {
        id: secretBox
        visible: row.isSecret
        revealed: row.revealed
        fieldEnabled: row.mode !== "ask"
        placeholder: row.mode === "ask" ? "asked when you connect" : (row.entry.stored ? "saved · leave empty to keep" : "value")
        onTextChanged: if (row.isSecret) { row.entry.value = text; if (text !== "") row.changed() }
        onRevealToggled: row.revealToggled()
        onAccepted: row.advance(secretBox.input)
        onEscaped: row.escaped()
    }
    VpnChip {
        visible: row.isSecret
        first: "Save"
        second: "Ask"
        onSecond: row.mode === "ask"
        onToggled: {
            row.entry.mode = row.mode === "ask" ? "save" : "ask"
            row.mode = row.entry.mode
            row.changed()
        }
        onAdvance: (from) => row.advance(from)
    }
}
```

- [ ] **Step 5: Write the form view**

Create `quickshell/components/launchers/network/VpnFormView.qml`:

```qml
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../../theme"
import "../../../services"
import "../../../services/vpnSchema.js" as Schema

// Add or edit one VPN profile (spec §9). Stops: Name, the type's schema
// fields, Common, then a collapsed Advanced section with every other vpn.data
// key. Saved secrets never come back from nm-vpn: their boxes stay empty
// ("saved · leave empty to keep"). Typed secrets are cleared as soon as they
// are handed to NetworkService.vpnSave, and on reset.
//
// `values`, `modes` and `advanced` are edited in place, so typing never
// rebuilds the stops. The *Rev counters say when a rebuild or re-read is due.
Item {
    id: view
    property string type: ""
    property string uuid: ""                  // "" = new profile
    property string profileName: ""           // name when opened, for the title
    property string name: ""
    property string nameInit: ""
    property var values: ({})
    property var modes: ({})
    property var stored: ({})
    property var advanced: []
    property bool advancedOpen: false
    property int formRev: 0                   // rebuilds every stop
    property int shownRev: 0                  // re-evaluates showIf
    property int modeRev: 0                   // re-reads secret modes
    property int advRev: 0                    // rebuilds the Advanced rows
    property bool dirty: false
    property bool busy: false
    property bool reveal: false
    property string formError: ""
    property string confirmText: ""
    readonly property bool isEdit: uuid !== ""
    readonly property bool isWireGuard: type === "wireguard"
    readonly property int peerCount: { view.formRev; return Number(view.values["peer.count"] || 0) }
    signal back()
    signal saved()
    signal refocus()

    implicitHeight: col.implicitHeight

    function clearSecrets() {
        for (let i = 0; i < rep.count; i++) { const it = rep.itemAt(i); if (it && it.kind === "secret") it.clearSecret() }
        for (let j = 0; j < advanced.length; j++) if (advanced[j].secret) advanced[j].value = ""
        advRev++
    }
    function reset() {
        clearSecrets()
        type = ""; uuid = ""; profileName = ""; name = ""; nameInit = ""
        values = ({}); modes = ({}); stored = ({}); advanced = []
        advancedOpen = false; dirty = false; busy = false; reveal = false
        formError = ""; confirmText = ""
        formRev++; advRev++
    }
    function startAdd(t) {
        reset()
        values = Schema.defaults(t)
        modes = Schema.defaultModes(t)
        type = t
        advancedOpen = !Schema.hasSchema(t)
        formRev++; advRev++
        Qt.callLater(focusFirst)
    }
    function startEdit(profile) {
        reset()
        const s = Schema.fromProfile(profile)
        values = s.values; modes = s.modes; stored = s.stored; advanced = s.advanced
        uuid = s.uuid; profileName = s.name; name = s.name; nameInit = s.name
        type = s.type
        advancedOpen = !Schema.hasSchema(s.type)
        formRev++; advRev++
        Qt.callLater(focusFirst)
    }
    function focusFirst() { nameStop.focusInput() }
    function next(from) {
        if (!from) return
        const n = from.nextItemInFocusChain(true)
        if (n) n.forceActiveFocus()
    }
    function fieldEdited(field, v) {
        if (field.kind !== "secret") values[field.key] = v
        dirty = true
        formError = ""
        if (field.kind === "bool" || field.kind === "choice") shownRev++
    }
    function toggleMode(key) { modes[key] = modes[key] === "ask" ? "save" : "ask"; modeRev++; dirty = true }
    function addRow() {
        advanced.push({ key: "", value: "", secret: false, mode: "save", stored: false, existing: false })
        advRev++
        dirty = true
        Qt.callLater(() => { const r = advRep.itemAt(advRep.count - 1); if (r) r.focusKey() })
    }
    function stopFor(key) {
        if (key === "name") return nameStop
        for (let i = 0; i < rep.count; i++) { const it = rep.itemAt(i); if (it && it.field.key === key) return it }
        return null
    }
    function visibleKeys() {
        const out = []
        for (let i = 0; i < rep.count; i++) { const it = rep.itemAt(i); if (it && it.visible) out.push(it.field.key) }
        return out
    }
    function collectSecrets() {
        const sv = {}
        for (let i = 0; i < rep.count; i++) {
            const it = rep.itemAt(i)
            if (it && it.kind === "secret" && it.visible) sv[it.field.key] = it.secretText()
        }
        return sv
    }
    function save() {
        if (busy || type === "") return
        const st = { type: type, uuid: uuid, name: name, values: values, modes: modes, stored: stored,
                     secretValues: collectSecrets(), advanced: advanced }
        const err = Schema.validate(st)
        if (err) {
            formError = err.message
            if (err.key === "advanced") { advancedOpen = true; advHeader.forceActiveFocus() }
            else { const s = stopFor(err.key); if (s) s.focusInput() }
            return
        }
        const req = Schema.buildRequest(st)
        clearSecrets()
        busy = true
        formError = ""
        NetworkService.vpnSave(req, r => {
            view.busy = false
            if (r.ok) { view.dirty = false; view.saved() }
            else view.formError = r.error || "Could not save the profile"
        })
    }
    function requestBack() {
        if (dirty) { confirmText = "Discard changes?  y / n"; view.refocus() }
        else { reset(); view.back() }
    }
    // Keys the stops do not consume land here.
    function handleKey(e) {
        if (confirmText !== "") {
            if (e.key === Qt.Key_Y) { reset(); view.back() }
            else if (e.key === Qt.Key_N || e.key === Qt.Key_Escape) { confirmText = ""; Qt.callLater(focusFirst) }
            e.accepted = true
            return
        }
        if (e.key === Qt.Key_Escape) { requestBack(); e.accepted = true }
    }

    // A focusable button: Space or Enter activates it.
    component FocusButton: Rectangle {
        id: fb
        property string label: ""
        property bool primary: false
        signal activated()
        Layout.fillWidth: true
        Layout.preferredHeight: 36
        radius: Theme.roundingItem
        color: fb.primary ? Theme.bgSelected : "transparent"
        border.color: fb.activeFocus ? Theme.borderSelected : Theme.border
        border.width: 1
        activeFocusOnTab: true
        Keys.onPressed: (e) => {
            if (e.key === Qt.Key_Space || e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { fb.activated(); e.accepted = true }
        }
        Text {
            anchors.centerIn: parent
            text: fb.label
            font.family: Theme.fontFamily
            font.pixelSize: 12
            font.weight: fb.primary ? Theme.fontWeightMedium : Theme.fontWeightNormal
            color: fb.activeFocus ? Theme.fgBright : Theme.fg
        }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { fb.forceActiveFocus(); fb.activated() } }
    }

    ColumnLayout {
        id: col
        width: parent.width
        spacing: Theme.gapM

        VpnFieldStop {
            id: nameStop
            field: ({ key: "name", label: "Name", kind: "text", required: true, placeholder: "Office VPN" })
            initial: view.nameInit
            onEdited: (v) => { view.name = v; view.dirty = true; view.formError = "" }
            onAdvance: (from) => view.next(from)
            onEscaped: view.requestBack()
        }
        Repeater {
            id: rep
            model: { view.formRev; return Schema.allFields(view.type) }
            delegate: VpnFieldStop {
                required property var modelData
                field: modelData
                visible: { view.shownRev; return Schema.isShown(modelData, view.values) }
                initial: { const v = view.values[modelData.key]; return v === undefined || v === null || typeof v === "boolean" ? "" : String(v) }
                checked: Schema.toBool(view.values[modelData.key])
                mode: { view.modeRev; return view.modes[modelData.key] || "save" }
                stored: !!view.stored[modelData.key]
                revealed: view.reveal
                onEdited: (v) => view.fieldEdited(modelData, v)
                onModeToggled: view.toggleMode(modelData.key)
                onRevealToggled: view.reveal = !view.reveal
                onAdvance: (from) => view.next(from)
                onEscaped: view.requestBack()
            }
        }
        Text {
            visible: view.isWireGuard && view.peerCount > 1
            text: view.peerCount + " peers · re-import to change"
            font.family: Theme.fontFamily
            font.pixelSize: 11
            color: Theme.fgMuted
        }

        FocusButton {
            id: advHeader
            visible: view.type !== "" && !view.isWireGuard
            label: (view.advancedOpen ? Icons.collapse : Icons.expand) + "  Advanced · " + (function () { view.advRev; return view.advanced.length })()
            onActivated: { view.advancedOpen = !view.advancedOpen; view.advRev++ }
        }
        Repeater {
            id: advRep
            model: { view.advRev; return view.advancedOpen ? view.advanced : [] }
            delegate: VpnAdvancedRow {
                required property var modelData
                entry: modelData
                revealed: view.reveal
                onChanged: { view.dirty = true; view.formError = "" }
                onRevealToggled: view.reveal = !view.reveal
                onAdvance: (from) => view.next(from)
                onEscaped: view.requestBack()
            }
        }
        FocusButton {
            visible: view.advancedOpen && !view.isWireGuard
            label: "+ Add row"
            onActivated: view.addRow()
        }

        Text {
            visible: view.formError !== ""
            text: Icons.warning + " " + view.formError
            font.family: Theme.fontFamily
            font.pixelSize: 11
            color: Theme.critical
            wrapMode: Text.Wrap
            Layout.fillWidth: true
        }
        FocusButton {
            id: saveBtn
            primary: true
            label: view.busy ? "Saving…" : (view.isEdit ? "Save changes" : "Add VPN")
            onActivated: view.save()
        }
        Text {
            text: view.confirmText !== "" ? view.confirmText
                : "Tab next · Enter next / save · Space toggle · h/l choose · Ctrl+s show/hide · Esc back"
            font.family: Theme.fontFamily
            font.pixelSize: 10
            color: view.confirmText !== "" ? Theme.critical : Theme.fgDim
            Layout.alignment: Qt.AlignHCenter
        }
    }
}
```

- [ ] **Step 6: Run the smoke test to make sure it passes**

Run: `bash quickshell/tests/smoke-vpn-views.sh`
Expected: every `SMOKE OK`, five `OK` log lines, then `OK (vpn view smoke tests)`.

- [ ] **Step 7: Check for hard-coded colours or glyphs**

Run: `grep -nE '#[0-9a-fA-F]{3,8}\b|"\\u[0-9a-f]{4}"' quickshell/components/launchers/network/*.qml`
Expected: no output.

- [ ] **Step 8: Commit**

```bash
git add quickshell/components/launchers/network quickshell/tests/smoke/vpn-views.qml quickshell/tests/smoke-vpn-views.sh
git commit -m "feat(network): VPN form drawn from the schema, with Advanced rows

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 9: Network Center integration; remove the editor entry points

**Files:**
- Modify: `quickshell/components/launchers/NetworkCenter.qml`
- Modify: `quickshell/services/NetworkService.qml` (remove `launchEditor`, `vpnAdd`, `vpnEditorProc`, `vpnAddProc`)
- Modify: `quickshell/tests/smoke/vpn-views.qml`, `quickshell/tests/smoke-vpn-views.sh`

**Interfaces:**
- Consumes: every view from Tasks 7–8 and the service API from Task 6.
- Produces, on `NetworkCenter`: `stack: [string]`, `top: string` (`"home" | "types" | "form" | "import"`), `openAdd()`, `openForm(type)`, `openImport()`, `editProfile(uuid)`, `editSelected()`, `popView()`, `resetVpnViews()`. In `/vpn`: `e` edits the selected VPN and `Add VPN…` opens the type picker. The secret prompt appears inline. The card is 620 px wide and animates its height.

- [ ] **Step 1: Add the failing smoke checks**

In `quickshell/tests/smoke/vpn-views.qml`, replace the line
```qml
        // --- view checks are added below by later tasks ---
```
with:
```qml
        function () {
            check("service: no nm-connection-editor entry points left",
                  typeof NetworkService.launchEditor === "undefined" && typeof NetworkService.vpnAdd === "undefined")
            const c = Qt.createComponent("components/launchers/NetworkCenter.qml")
            check("NetworkCenter.qml compiles", c.status === Component.Ready, c.errorString())
            if (c.status !== Component.Ready) return
            const nc = c.createObject(shell)
            check("NetworkCenter instantiates closed", nc !== null && nc.isOpen === false)
            if (!nc) return
            check("network: starts on the main view", nc.top === "home")
            nc.openAdd()
            check("network: Add VPN opens the type picker", nc.top === "types", nc.top)
            nc.openForm("openvpn")
            check("network: picking a type opens the form above it", nc.top === "form" && nc.stack.length === 2, JSON.stringify(nc.stack))
            check("network: views below the top park left", nc.parkFor("types") === -60 && nc.parkFor("home") === -60 && nc.parkFor("import") === 60)
            nc.popView()
            check("network: Esc returns one level", nc.top === "types")
            nc.resetVpnViews()
            check("network: closing resets the stack", nc.top === "home" && nc.stack.length === 0)
            nc.destroy()
        },
        // --- view checks are added below by later tasks ---
```

In `quickshell/tests/smoke-vpn-views.sh`, add this line directly above `grep -oE 'SMOKE (OK|FAIL|DONE).*' "$tmp/log"`:

```bash
if grep -rn "nm-connection-editor" "$here/../components" "$here/../services"; then echo "FAIL nm-connection-editor is still referenced"; exit 1; fi
```

- [ ] **Step 2: Run it to make sure it fails**

Run: `bash quickshell/tests/smoke-vpn-views.sh`
Expected: the grep prints the two `NetworkService.qml` lines, then `FAIL nm-connection-editor is still referenced` and exit 1.

- [ ] **Step 3: Remove the editor entry points from `NetworkService.qml`**

Delete these two lines:
```qml
    function launchEditor() { root.vpnEditorProc.running = true }
    function vpnAdd() { root.vpnAddProc.running = true }
```
and these two:
```qml
    property Process vpnEditorProc: Process { command: ["nm-connection-editor"]; stdout: StdioCollector { onStreamFinished: { root.vpnProc.running = true; root.knownProc.running = true } } }
    property Process vpnAddProc: Process { command: ["nm-connection-editor", "-c", "-t", "vpn"]; stdout: StdioCollector { onStreamFinished: { root.vpnProc.running = true; root.knownProc.running = true } } }
```

- [ ] **Step 4: Edit `NetworkCenter.qml`**

Make these edits to `quickshell/components/launchers/NetworkCenter.qml`, in order.

(a) Imports. Replace:
```qml
import "../../theme"
import "../../services"

WlrLayershell {
```
with:
```qml
import "../../theme"
import "../../services"
import "../../services/vpnSchema.js" as Schema
import "network"

WlrLayershell {
```

(b) Stack state and navigation. Replace:
```qml
    function open(){ isOpen=true }
    function close(){ isOpen=false; filterActive=false }
    function toggle(){ if(isOpen) close(); else open() }
```
with:
```qml
    function open(){ isOpen=true }
    function close(){ isOpen=false; filterActive=false; resetVpnViews() }
    function toggle(){ if(isOpen) close(); else open() }

    // VPN views (docs/superpowers/specs/2026-11-09-native-vpn-design.md §9):
    // a stack above the main view. Views below the top park at x -60, the
    // rest at +60 (STYLE.md §2.5).
    property var stack: []                    // "types" | "form" | "import"
    readonly property string top: stack.length > 0 ? stack[stack.length - 1] : "home"
    readonly property string titleSuffix: top === "types" ? "  ·  Add VPN"
        : top === "import" ? "  ·  Import"
        : top === "form" ? (formView.isEdit ? "  ·  Edit " + formView.profileName : "  ·  Add " + Schema.typeLabel(formView.type))
        : ""
    function parkFor(name) {
        if (name === "home") return -60
        const i = stack.indexOf(name)
        return i !== -1 && i < stack.length - 1 ? -60 : 60
    }
    function currentView() { return top === "types" ? typeView : (top === "form" ? formView : importView) }
    function refocusTop() {
        Qt.callLater(() => {
            if (root.top === "home") mainCol.forceActiveFocus()
            else if (root.top === "form") formView.focusFirst()
            else viewHost.forceActiveFocus()
        })
    }
    function pushView(name) { stack = stack.concat([name]); refocusTop() }
    function popView() { stack = stack.slice(0, stack.length - 1); refocusTop() }
    function resetVpnViews() { stack = []; typeView.reset(); formView.reset(); importView.reset(); secretPrompt.clear() }
    function openAdd() {
        if (!NetworkService.helperAvailable) { NetworkService.lastError = "nm-vpn is not installed — run update"; return }
        typeView.reset()
        pushView("types")
    }
    function openForm(type) { formView.startAdd(type); pushView("form") }
    function openImport() { importView.reset(); NetworkService.refreshImportCandidates(); pushView("import") }
    function editProfile(uuid) {
        NetworkService.vpnLoad(uuid, r => {
            if (!r.ok) { NetworkService.reportError(r.error || "Could not read the VPN profile"); root.stack = []; root.refocusTop(); return }
            importView.reset()
            formView.startEdit(r.profile)
            root.stack = ["form"]                 // after an import too: Esc returns to the list
            root.refocusTop()
        })
    }
    function editSelected() {
        const it = navItems[selIndex]
        if (!it || it.kind !== "vpn") return
        const v = filteredVpn[it.idx]
        if (!v) return
        if (!NetworkService.helperAvailable) { NetworkService.lastError = "nm-vpn is not installed — run update"; return }
        editProfile(v.uuid)
    }
    function formSaved() { formView.reset(); stack = []; NetworkService.refresh(); refocusTop() }

    // A view slot of the stack (STYLE.md §2.5 slide + cross-fade).
    component Slide: Item {
        property string name: ""
        readonly property bool active: root.top === name
        width: parent ? parent.width : 0
        x: active ? 0 : root.parkFor(name)
        opacity: active ? 1 : 0
        enabled: active
        visible: opacity > 0.01
        Behavior on x { NumberAnimation { duration: Theme.durationNormal; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: Theme.durationFast } }
    }
```

(c) Card width (spec §2: 620) and height animation. Replace:
```qml
        width: 640
        height: Math.min(640, mainCol.implicitHeight + Theme.padL*2)
```
with:
```qml
        width: 620
        height: Math.min(640, mainCol.implicitHeight + Theme.padL*2)
        Behavior on height { NumberAnimation { duration: Theme.durationNormal; easing.type: Easing.OutCubic } }
```

(d) Title. Replace:
```qml
                Text { text: "Network"; font.family: Theme.fontFamily;
```
with:
```qml
                Text { text: "Network" + root.titleSuffix; font.family: Theme.fontFamily;
```

(e) Open the view host and the home slide. Replace:
```qml
            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border }

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.gapM
                Rectangle {
                    visible: filterActive
```
with:
```qml
            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border }

            Item {
                id: viewHost
                Layout.fillWidth: true
                Layout.preferredHeight: root.top === "types" ? typeView.implicitHeight
                    : root.top === "form" ? formView.implicitHeight
                    : root.top === "import" ? importView.implicitHeight
                    : homeCol.implicitHeight
            Slide {
                name: "home"
                implicitHeight: homeCol.implicitHeight
            ColumnLayout {
                id: homeCol
                width: parent.width
                spacing: Theme.gapM

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.gapM
                Rectangle {
                    visible: filterActive
```

The existing content keeps its indentation inside the new wrappers. QML doesn't care, and leaving it keeps this diff readable.

(f) `Add VPN…` without the editor row, plus the secret prompt. Replace the two Rectangles `id: vpnAddRow` and `id: editorRow` (from `            Rectangle {\n                id: vpnAddRow` down to the closing `}` of `editorRow`, just before `            Rectangle {\n                id: pwdDialog`) with:
```qml
            Rectangle {
                id: vpnAddRow
                visible: root.view === "vpn"
                Layout.fillWidth: true
                height: 32
                radius: Theme.roundingItem
                readonly property bool isSel: root.navItems[root.selIndex] !== undefined && root.navItems[root.selIndex].kind === "vpnAdd"
                color: isSel ? Theme.bgSelected : Theme.bgHover
                border.color: isSel ? Theme.borderSelected : Theme.border
                border.width: 1
                Text {
                    anchors.centerIn: parent
                    text: NetworkService.helperAvailable ? "Add VPN…" : "Add VPN… · Not available"
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    color: NetworkService.helperAvailable ? Theme.fg : Theme.fgDim
                }
                MouseArea { anchors.fill: parent; onClicked: root.openAdd() }
            }
            VpnSecretPrompt {
                id: secretPrompt
                onDone: mainCol.forceActiveFocus()
            }
```

(g) Footer hint for the VPN view. Replace:
```qml
                    return "j/k · Enter act · /nearby /known /vpn · x delete · d disc · r rescan · Esc back · Esc close"
```
with:
```qml
                    if (root.view === "vpn") return "j/k · Enter connect · e edit · x delete · /nearby /known /vpn · Esc back"
                    return "j/k · Enter act · /nearby /known /vpn · x delete · d disc · r rescan · Esc back · Esc close"
```

(h) Close the home slide, add the VPN slides, close the view host. Replace:
```qml
                color: confirmText ? Theme.critical : (NetworkService.busy ? Theme.fgMuted : Theme.fgDim)
                Layout.alignment: Qt.AlignHCenter
            }
        }
        }
        Keys.onPressed: (e)=>{
```
with:
```qml
                color: confirmText ? Theme.critical : (NetworkService.busy ? Theme.fgMuted : Theme.fgDim)
                Layout.alignment: Qt.AlignHCenter
            }
            }   // homeCol
            }   // Slide home
                Slide {
                    name: "types"
                    implicitHeight: typeView.implicitHeight
                    VpnTypeView {
                        id: typeView
                        width: parent.width
                        onPickType: (t) => root.openForm(t)
                        onImportRequested: root.openImport()
                        onBack: root.popView()
                        onRefocus: viewHost.forceActiveFocus()
                    }
                }
                Slide {
                    name: "form"
                    implicitHeight: formView.implicitHeight
                    VpnFormView {
                        id: formView
                        width: parent.width
                        onSaved: root.formSaved()
                        onBack: root.popView()
                        onRefocus: viewHost.forceActiveFocus()
                    }
                }
                Slide {
                    name: "import"
                    implicitHeight: importView.implicitHeight
                    VpnImportView {
                        id: importView
                        width: parent.width
                        onImported: (uuid) => root.editProfile(uuid)
                        onBack: root.popView()
                        onRefocus: viewHost.forceActiveFocus()
                    }
                }
            }   // viewHost
        }
        }
        Keys.onPressed: (e)=>{
```

(i) Route keys to the top view; the prompt's Esc; `e` to edit. Replace:
```qml
        Keys.onPressed: (e)=>{
            if (confirmText !== "") {
```
with:
```qml
        Keys.onPressed: (e)=>{
            if (root.top !== "home") { root.currentView().handleKey(e); return }
            if (confirmText !== "") {
```
then replace:
```qml
                if(pwdDialog.visible){ cancelPwd(); e.accepted=true }
```
with:
```qml
                if(secretPrompt.visible){ secretPrompt.cancel(); e.accepted=true }
                else if(pwdDialog.visible){ cancelPwd(); e.accepted=true }
```
then replace:
```qml
            else if(e.key===Qt.Key_X) { root.requestDelete(); e.accepted=true }
```
with:
```qml
            else if(e.key===Qt.Key_X) { root.requestDelete(); e.accepted=true }
            else if(e.key===Qt.Key_E) { root.editSelected(); e.accepted=true }
```

(j) Reset the views when opening. Replace:
```qml
    onIsOpenChanged: if(isOpen) { NetworkService.lastError = "";
```
with:
```qml
    onIsOpenChanged: if(isOpen) { root.resetVpnViews(); NetworkService.lastError = "";
```

(k) Navigation without the editor row. Delete the line:
```qml
        else if(it.kind==="editor") anchor = editorRow
```
Replace:
```qml
        else if(it.kind==="vpnAdd"){ NetworkService.vpnAdd() }
        else if(it.kind==="editor"){ NetworkService.launchEditor() }
```
with:
```qml
        else if(it.kind==="vpnAdd"){ root.openAdd() }
```
Replace:
```qml
items.push({kind:"vpnAdd"}); items.push({kind:"editor"}) }
```
with:
```qml
items.push({kind:"vpnAdd"}) }
```

(l) Show the prompt when a connect needs secrets. Replace:
```qml
    Connections { target: NetworkService; function onDataUpdated(){ updateModels() } }
```
with:
```qml
    Connections {
        target: NetworkService
        function onDataUpdated(){ updateModels() }
        function onVpnNeedChanged(){
            if (NetworkService.vpnNeed.length === 0 || !root.isOpen) return
            root.stack = []
            root.view = "vpn"
            root.updateModels()
            Qt.callLater(() => secretPrompt.focusFirst())
        }
    }
```

- [ ] **Step 5: Run the smoke tests to make sure they pass**

Run:
```bash
bash quickshell/tests/smoke-vpn-views.sh
grep -n "editor" quickshell/components/launchers/NetworkCenter.qml
```
Expected: every `SMOKE OK` and `OK (vpn view smoke tests)`. The grep prints nothing.

- [ ] **Step 6: Load the real shell from the worktree**

Run: `timeout 5 quickshell -p "$PWD/quickshell" 2>&1 | grep -iE 'NetworkCenter|network/|ReferenceError|TypeError|is not a type' | head`
Expected: no output. A layer-shell warning about another running instance is fine.

- [ ] **Step 7: Run the other QML suites**

Run:
```bash
bash quickshell/tests/run.sh 2>&1 | tail -2
bash quickshell/tests/smoke-identity-views.sh | tail -1
```
Expected: `0 failed`, then `OK (identity view smoke tests)`.

- [ ] **Step 8: Commit**

```bash
git add quickshell/components/launchers/NetworkCenter.qml quickshell/services/NetworkService.qml quickshell/tests/smoke/vpn-views.qml quickshell/tests/smoke-vpn-views.sh
git commit -m "feat(network): native VPN views in the Network Center; drop nm-connection-editor

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 10: Remove `networkmanagerapplet`; docs and specs; full checks

**Files:**
- Modify: `nixos/programs/quickshell.nix`, `nixos/tests/test-vpn.sh`
- Modify: `quickshell/specs/launchers/Network-Center.md`, `quickshell/specs/SPECS.md`, `README.md`, `AGENTS.md`, `quickshell/docs/superpowers/specs/2026-11-09-native-vpn-design.md`

**Interfaces:**
- Consumes: everything above.
- Produces: no `networkmanagerapplet` in the user's packages, which removes `nm-connection-editor`, the `nm-applet` tray icon and its XDG autostart. The docs and specs match what was built.

- [ ] **Step 1: Add the failing assertion**

In `nixos/tests/test-vpn.sh`, replace:
```bash
expect '.strongswan'                             "services.strongswan stays enabled (L2TP/IPsec)"
```
with:
```bash
expect '.strongswan'                             "services.strongswan stays enabled (L2TP/IPsec)"
expect '[.home[] | test("network-manager-applet")] | any | not' "networkmanagerapplet is gone (no nm-connection-editor, no nm-applet)"
```

Run: `bash nixos/tests/test-vpn.sh`
Expected: `FAIL networkmanagerapplet is gone …`, exit 1.

- [ ] **Step 2: Remove the package**

In `nixos/programs/quickshell.nix`, delete the line:
```nix
    networkmanagerapplet # nm-connection-editor GUI for NetworkCenter
```

Run: `bash nixos/tests/test-vpn.sh`
Expected: seven `OK` lines, then `OK (VPN config checks)`.

- [ ] **Step 3: Update `quickshell/specs/launchers/Network-Center.md`**

(a) In the §3 table, replace:
```markdown
| `/vpn` | vpn | current connection + VPN networks + config options (`Add VPN…`, `Open connection editor…`) |
```
with:
```markdown
| `/vpn` | vpn | current connection + VPN profiles + `Add VPN…` |
```

(b) Replace the whole of `### 3.4 VPN (`/vpn`)`, from that heading down to and including the line ``* **Empty state:** if no VPN profiles → `"No VPN connections"` at `Theme.fgDim`.``, with:
```markdown
### 3.4 VPN (`/vpn`)

Native: no `nm-connection-editor`, no `nm-applet`. Design: `docs/superpowers/specs/2026-11-09-native-vpn-design.md`.

* **List:** `nmcli -t -f NAME,UUID,TYPE connection show` rows whose type is `vpn` or `wireguard`: name, plus `active` when connected. An active WireGuard connection counts as the active VPN.
* **Row keys:** `Enter` connect / disconnect · `e` edit · `x` delete (`y/n`).
* **Connect:** `NetworkService.vpnConnect(uuid)` → `nm-vpn connect`. Secrets set to **Ask** come back as `need`. That covers flag `2`, and also `1` (agent-owned), since no agent is left to supply it. An inline prompt (`network/VpnSecretPrompt.qml`) asks for them: one masked field per secret, labelled from the schema, `Ctrl+s` show/hide, `Enter` next / connect, `Esc` cancel. It clears its fields at once, and the values go through `nmcli … passwd-file` on a pipe. The Current Connection card shows `Connecting to {name}…`.
* **`Add VPN…`** opens `network/VpnTypeView.qml`: `Import from file…` first, then the installed types (every plugin in `networking.networkmanager.plugins`, plus WireGuard). Types without a schema show `advanced`.
* **Form** (`network/VpnFormView.qml`): Name, the type's fields from `services/vpnSchema.js`, `Use only for resources on its network` (`ipv4.never-default`), then a collapsed **Advanced** section. Advanced lists every other `vpn.data` key as `key = value`; `+ Add row` adds one, with a `Data | Secret` chip; clearing a key removes it. Each secret has a **`Save | Ask`** chip (default Save). Saved secrets never come back: their box reads `saved · leave empty to keep`. Keys: `Tab`/`Shift+Tab`/`Enter` move, `Enter` on the last stop saves, `Space` toggles, `h`/`l` cycle choices, `Ctrl+s` show/hide, `Esc` back. `Esc` asks `Discard changes? y / n` when something changed. A WireGuard profile with several peers shows `N peers · re-import to change`.
* **Import** (`network/VpnImportView.qml`): config files from `~/Downloads` and `~/Documents` (depth 2, newest first), plus a path field; there's no file-picker window. The extension picks the type. When several installed types claim it, a short picker asks. The profile is created at once and opens in the form; `Esc` there returns to the list.
* **Empty state:** no profiles → `"No VPN connections"` at `Theme.fgDim`. Without `nm-vpn` → `Add VPN… · Not available`, and list, connect and delete keep working through `nmcli`.
* **Not offered yet:** OpenConnect. Its login needs its own step (design §10).
```

(c) In §4, after the line starting `* **Error toast:**`, add:
```markdown
* **VPN views:** the type picker, form and import view slide over the list as a stack (`STYLE.md` §2.5: views below the top park at `x: -60`, the rest at `+60`; cross-fade; the card animates its height). Each view handles its own keys; `Esc` returns one level.
```

(d) In §5, replace:
```qml
function vpnConnect(name: string): void
function vpnDisconnect(name: string): void
function vpnDelete(name: string): void
function vpnAdd(config: var): void
```
with:
```qml
function vpnConnect(uuid: string, secrets?: var): void   // nm-vpn connect; Ask secrets → vpnNeed
function vpnCancelNeed(): void
function vpnDisconnect(uuid: string): void
function vpnDelete(uuid: string): void
function vpnLoad(uuid: string, cb: function): void        // nm-vpn get (secret modes, never values)
function vpnSave(request: var, cb: function): void        // nm-vpn add | update
function vpnImport(type: string, path: string, cb: function): void
function refreshImportCandidates(): void
// properties: helperAvailable, vpnTypes, vpnNeed, vpnNeedUuid, vpnNeedName, vpnNeedType, importCandidates
```

(e) In §6, replace:
```markdown
* [ ] `/nearby` shows only nearby; `/known` shows only known; `/vpn` shows VPN list + `Add VPN…` + `Open connection editor…`.
```
with:
```markdown
* [ ] `/nearby` shows only nearby; `/known` shows only known; `/vpn` shows the VPN list + `Add VPN…`.
```
and replace:
```markdown
* [ ] VPN list/connect/delete/add works; `nm-connection-editor` fallback documented if native form deferred.
```
with:
```markdown
* [ ] VPN add (every installed type), import (`.ovpn`, `.conf`), edit, delete and connect work in the shell. Saved secrets are never shown; each secret is Save or Ask; Ask prompts at connect.
* [ ] No `nm-connection-editor` or `nm-applet` window ever opens (`networkmanagerapplet` is not installed).
* [ ] An active WireGuard connection shows as the active VPN.
```

- [ ] **Step 4: Update `quickshell/specs/SPECS.md`, `README.md` and `AGENTS.md`**

`quickshell/specs/SPECS.md` §2.2: after the row starting `| \`networkmanager\` + \`nmcli\``, add:
```markdown
| NetworkManager VPN plugins | VPN types offered in the Network Center (`/vpn`) | **yes** for VPN | `networking.networkmanager.plugins` (`configuration.nix`) |
| `nm-vpn` | VPN add/import/edit/connect helper (libnm, secrets on stdin) | **yes** for VPN | `quickshell/scripts/nm-vpn.nix`, in `programs/quickshell.nix` |
```

`README.md`, under `### Network`, after the closing ```` ``` ```` of the `nmcli device wifi connect` block, add:
```markdown
**VPN:** `SUPER+W`, then `/vpn`. `Add VPN…` adds a profile for any installed type (OpenVPN, L2TP/IPsec, IKEv2, WireGuard; more with `networking.networkmanager.plugins`) or imports a `.ovpn`/`.conf` file. `e` edits a profile. Each password is either saved by NetworkManager or asked when you connect.
```

`AGENTS.md`, in "Checks before proposing a commit": after `bash nixos/tests/test-face.sh` add `bash nixos/tests/test-vpn.sh`. After `bash quickshell/tests/smoke-identity-views.sh` add:
```bash
bash quickshell/tests/test-nm-vpn.sh
bash quickshell/tests/smoke-vpn-views.sh
bash quickshell/tests/test-vpn-schema-keys.sh
```
Then, directly above the paragraph starting `To evaluate a real machine without rebuilding`, add:
```markdown
When `nm-vpn`, the VPN plugins or `services.strongswan` change, also run `bash nixos/tests/test-vpn-vm.sh`. It's a NixOS VM test, needs KVM and takes a few minutes.
```

- [ ] **Step 5: Bring the design spec in line with what was built**

In `quickshell/docs/superpowers/specs/2026-11-09-native-vpn-design.md`:

(a) In the §7 table's `get` row, replace `"secrets":{"password":"save"\|"ask"}` with `"secrets":{"password":"save"\|"ask"\|"unset"}`. Then replace `**No secret values**, only modes |` with `**No secret values**, only modes (\`unset\`: no value and not asked) |`.

(b) In the `connect` row, replace `{"ok":false,"need":["password",…]}` with `{"ok":false,"need":["password",…],"type":"l2tp"}`.

(c) Replace `**Secret flags.** Save writes \`K-flags = 0\`; Ask writes \`K-flags = 2\` (not saved).` with `**Secret flags.** Save writes \`K-flags = 0\` (or \`4\`, not required, when there is no value); Ask writes \`K-flags = 2\` (not saved). \`update\` never removes \`*-flags\` data keys.`

(d) Replace the `**Packaging.**` paragraph with:
```markdown
**Packaging.** `quickshell/scripts/nm-vpn.nix`: `python3.withPackages` with `pygobject3`, behind `makeWrapper`, so `GI_TYPELIB_PATH` holds libnm's and GLib's typelibs and `PATH` holds `nmcli` (Plan 2 adds `openconnect` the same way). Test hooks, as `IDENTITY_PASSWD_BIN` does: `NM_VPN_FAKE_STATE` (a JSON-file backend instead of libnm), `NM_VPN_NMCLI_BIN`, `NM_VPN_CONNECT_WAIT`.
```

(e) In §8, replace the `**Pure functions**` bullet with:
```markdown
- **Pure functions** (unit-tested by `tests/tst_vpn_schema.qml`): `defaults`, `defaultModes`, `isShown`/`fieldsFor`, `fromProfile`, `buildRequest`, `validate`, `typeForPath`, `importExtensions`, `pickerTypes`, `labelFor`, `cycleChoice`. Flag handling (`mode_from_flags`, `secret_keys`) lives only in `nm-vpn`: the shell gets modes, never flags.
```

(f) In §9, replace `Secret keys found by \`secretKeysFromData\` are masked and get a chip. An \`Add row\` button adds an empty row;` with `Secret keys (reported by \`nm-vpn get\`) are masked and get a \`Save | Ask\` chip. \`+ Add row\` adds an empty row with a \`Data | Secret\` chip;`.

(g) In the §11 table, replace `networkmanager-openvpn networkmanager-openconnect networkmanager-strongswan` with `networkmanager-openvpn networkmanager-strongswan`, and add after that row:
```markdown
| `nixos/configuration.nix` (Plan 2) | `networkmanager-openconnect` is added together with the OpenConnect login (§10) |
```

- [ ] **Step 6: Run every check**

Run from the worktree root:
```bash
nix flake check ./nixos --no-write-lock-file
bash nixos/tests/test-bootstrap.sh
bash nixos/tests/test-sync-secrets.sh
bash nixos/tests/test-fingerprint.sh
bash nixos/tests/test-face.sh
bash nixos/tests/test-vpn.sh
bash quickshell/tests/run.sh
bash quickshell/tests/test-identity-passwd.sh
bash quickshell/tests/smoke-identity-views.sh
bash quickshell/tests/test-nm-vpn.sh
bash quickshell/tests/smoke-vpn-views.sh
bash quickshell/tests/test-vpn-schema-keys.sh
bash tests/check-no-hardcoded-home.sh
bash tests/test-user.sh
bash tests/test-guard.sh
bash nixos/tests/test-vpn-vm.sh
```
Expected: each one ends in its `OK …` line (or `SKIP no /dev/kvm` for the VM test, which you must then report), and the flake check exits 0. Then dry-build a real machine layer without switching:
```bash
DOTFILES_MACHINE_DIR=/etc/nixos nixos-rebuild dry-build --flake ./nixos#default --impure
```
Expected: it evaluates and lists what would be built, with no error.

- [ ] **Step 7: Commit**

```bash
git add nixos/programs/quickshell.nix nixos/tests/test-vpn.sh quickshell/specs/launchers/Network-Center.md quickshell/specs/SPECS.md README.md AGENTS.md quickshell/docs/superpowers/specs/2026-11-09-native-vpn-design.md
git commit -m "feat(network): remove networkmanagerapplet; document native VPN management

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 8: Hand over to the user**

Report what was verified and what wasn't. The user then rebuilds (`update`) and tries a real VPN. **Not verified until the user rebuilds and tries:**
- a real connection for each type they use;
- that the `nm-applet` tray icon is gone after logging in again;
- profiles made earlier with `nm-connection-editor`. They should prompt for their agent-owned secrets, and `e` → Save stores them.

Then write Plan 2 (OpenConnect: plugin, `nm-vpn oc-login`, prompt events) from spec §10 and the VM findings below.

## VM findings (Task 5)

From `bash nixos/tests/test-vpn-vm.sh` (NetworkManager 1.56.0, strongSwan 6.1.0, networkmanager-strongswan 1.6.5), 2026-11-09.

- passwd-file through a pipe: **works**. `nm-vpn connect` (pipe on `/dev/fd/N`) and `nmcli … passwd-file <(…)` both get NetworkManager past the secrets stage. OpenVPN then fails only because the test profile has no CA (`Connection activation failed: Unknown reason`, no "Secrets were required"); without passwd-file nmcli says "You need to authenticate…". No file fallback needed; `nmcli_up` is unchanged.
  - strongSwan caveat: nmcli learns strongSwan's secret names by running `nm-strongswan-auth-dialog --external-ui-mode`, which calls `gtk_init` first and dies without a display. Headless, nmcli falls back to hard-coded names (`xauthpassword`, `pskvalue`) that miss `password`, and NM reports "No valid secrets". With a display (Xvfb in the VM, the Wayland session on the desktop) the piped `password` reaches charon-nm, which initiates (XFRM interface created) and fails only on DNS for the dummy host.
- charon-nm beside services.strongswan: **coexist**, once `/etc/strongswan.conf` exists. NixOS creates none (services.strongswan passes its own charon a store file through `STRONGSWAN_CONF`), so charon-nm aborted: `no files found matching '/etc/strongswan.conf'` / `abort initialization due to invalid configuration`. Fix: `environment.etc."strongswan.conf".text = "";` in `nixos/configuration.nix` (checked by `nixos/tests/test-vpn.sh`). charon-nm then loads `socket-default` (random IKE ports by default) with no bind error, and `strongswan.service` stays active.
- Imported OpenVPN profile as reported by `nm-vpn get` (fixture `client`/`dev tun`/`proto udp`/`remote vpn.example.invalid 1194`/`auth-user-pass`/`ca ca.crt`):
  `{"name": "office", "type": "openvpn", "data": {"ca": "/etc/vpn-test/ca.crt", "challenge-response-flags": "2", "connection-type": "password", "dev": "tun", "password-flags": "1", "remote": "vpn.example.invalid:1194"}, "secrets": {"challenge-response": "ask", "password": "ask"}, "native": {"ipv4.never-default": "no"}, "user": {}}`
  The importer makes `password` agent-owned (flags 1, read as Ask) and adds `challenge-response` (flags 2); `remote` becomes `host:port`; a relative `ca` is resolved against the file's folder. It refuses a file with no `ca` ("missing --ca"). It can be renamed and saved with no stored secrets.
- Other results: every type round-trips through libnm (add/get/update, Save → Ask writes `K-flags = 2` and drops the value, empty value keeps the stored secret); `*-flags` set as plain ints work, including WireGuard's GFlags `private-key-flags` (Ask → 2). `types` reports strongSwan with `import: false`. The `secrets_unreadable` guard never tripped: NM's GetSecrets returns an empty result, not an error, for profiles with no stored secrets. This nmcli prints WireGuard peers on one `wireguard.peers` line, not as `wireguard-peer.<key>.*` lines.
