# Network Center — Native VPN Management Design

**Date:** 2026-11-09
**Status:** Draft, awaiting user approval
**Scope:** NetworkManager VPN plugins, a VPN helper (`nm-vpn`), `vpnSchema.js`, `NetworkService.qml`, new Network Center views, removal of `networkmanagerapplet`, spec, doc and test updates.

## 1. Intent

The Network Center (`SUPER+W`, `/vpn`) lists, connects and deletes VPNs, but **Add VPN…** and **Open connection editor…** start `nm-connection-editor`, a GTK window that ignores the shell's theme and keyboard model. Connecting to a VPN whose password isn't saved also pops up the plugin's GTK auth dialog through `nm-applet`. The goal is to do all of this inside the shell, for every VPN type NetworkManager supports on the machine, with no third-party UI. `Network-Center.md` §6 already expected a native form ("`nm-connection-editor` fallback documented if native form deferred").

## 2. Goals

- Add, import, edit, delete, connect and disconnect VPNs entirely in the Network Center.
- Support every installed VPN type. Types are discovered at runtime, so adding a plugin in Nix makes it appear with no QML change.
- Friendly forms for the common types, and a raw key/value fallback so no installed plugin is ever unreachable.
- Each secret chooses **Save** (NetworkManager stores it) or **Ask** (prompted at every connect; needed for 2FA/OTP).
- OpenConnect (Cisco AnyConnect, GlobalProtect, Juniper/Pulse, Fortinet, F5, Array) logs in through the shell, including certificate trust and browser single sign-on.
- Secrets never enter argv, the environment, logs or QML memory beyond the moment they are typed.
- Remove `networkmanagerapplet` (editor, tray applet, secret agent).

## 3. Non-goals

- Editing Wi-Fi or Ethernet profiles (802.1X enterprise Wi-Fi, static IP). Those use `nmcli`.
- A long-running secret agent. Ask secrets are supplied only when a connect is started from the Network Center; NetworkManager asking on its own (autoconnect, reconnect) gets no answer (§12).
- Editing WireGuard profiles with more than one peer in the form (re-import instead).
- Exporting profiles.
- Moving the existing Wi-Fi password off argv (`connectScanned`). The helper makes that easy later, but it isn't part of this work.

## 4. Constraints

- `AGENTS.md`: nothing machine-specific; plugins and packages are personal layer. Never touch the live NetworkManager while developing: anything that creates profiles is tested in a VM.
- `quickshell/AGENTS.md` and `STYLE.md`: `Theme.*`/`Icons.*` only; state shown by borders; card 620 px; vim keys in lists; `Esc` stack; view transitions per §2.5; one `Process` per subsystem inside `services/`; every component renders a degraded state.
- The Identity Manager's rule: passwords travel only on a helper's stdin (`identity-passwd`).

## 5. Approaches considered

### 5.1 How to cover every type

NetworkManager has no API that describes a plugin's fields: each plugin's form is compiled into its own GTK library (`[GNOME] properties=` in `/etc/NetworkManager/VPN/*.name`). Three options:

- **A. Layered (chosen):** runtime type discovery + import from file + forms drawn from a schema + a raw key/value fallback.
- **B. Raw key/value editor + import only:** fully general, but you'd need to know key names like `ipsec-psk`.
- **C. A hand-built QML form per type:** most polished, but every new type means new QML.

A covers everything B covers, with friendly forms where we know the type.

### 5.2 Backend

- `nmcli connection add/modify` would put secrets in argv (`/proc/*/cmdline` is world-readable) and makes nested values such as WireGuard peers (`aa{sv}`) awkward.
- **Chosen:** a Python helper using **libnm through PyGObject** for reads and writes (secrets go over D-Bus), and `nmcli connection up … passwd-file` for connecting. With `passwd-file`, `nmcli` registers a temporary secret agent for that single activation, which is the part of `nm-applet`'s job we still need.

### 5.3 Secrets

Per-field **Save | Ask**, defaulting to Save. Chosen over "always save" (breaks 2FA) and "always ask" (too much typing).

## 6. Architecture

```
NetworkCenter.qml ─► network/*View.qml ─► vpnSchema.js ─► NetworkService.qml ─► nm-vpn ─► NetworkManager
  (/vpn list,         (type picker, form,   (pure data +     (VPN API, one        (Python +    (D-Bus; nmcli
   hosts the views)    import, prompt)       request building) Process each)       libnm)       for connect)
```

| Unit | File | Job | Depends on |
|---|---|---|---|
| Helper | `quickshell/scripts/nm-vpn.py` | Talks to NetworkManager; secrets only on stdin | libnm, `nmcli`, `openconnect` |
| Schema | `quickshell/services/vpnSchema.js` | Field lists per type; form values → helper request; flags → modes; extension → type | nothing (pure JS) |
| Service | `quickshell/services/NetworkService.qml` | VPN API over the helper; existing list/poll | helper, schema |
| Views | `quickshell/components/launchers/network/` | `VpnTypeView`, `VpnFormView`, `VpnImportView`, `VpnSecretPrompt` | service, schema, `SecretField` |
| Host | `quickshell/components/launchers/NetworkCenter.qml` | `/vpn` list, view stack, key routing | views |

## 7. Helper `nm-vpn`

`nm-vpn <command>` reads one JSON request on stdin and prints exactly one JSON line on stdout, except `oc-login`, which streams. Every result has `"ok"`. Failures carry `"error"`, scrubbed of every secret in the request. The exit code is 0 whenever a result line was printed.

| Command | Request | Result |
|---|---|---|
| `types` | `{}` | `{"ok":true,"types":[{"name":"openvpn","service":"org.freedesktop.NetworkManager.openvpn","import":true}, …, {"name":"wireguard","service":null,"import":true}]}` from `NM.VpnPluginInfo.list_load()` plus WireGuard; `import` from the editor plugin's capabilities |
| `get` | `{"uuid":…}` | `{"ok":true,"profile":{"uuid","name","type","data":{…},"secrets":{"password":"save"\|"ask"\|"unset"},"native":{…},"user":{…}}}`. **No secret values**, only modes (`unset`: no value and not asked) |
| `add` | `{"type","name","data":{…},"secrets":{"k":{"mode":"save"\|"ask","value":"…"}},"native":{…},"user":{…}}` | `{"ok":true,"uuid":…}` |
| `update` | as `add` plus `uuid`. A data key absent from `data` is removed. A secret with an empty `value` keeps its stored value but takes the new `mode`; a secret absent from `secrets` is left as it is | `{"ok":true}` |
| `import` | `{"type","path"}` | `{"ok":true,"uuid":…}`. The profile is created immediately |
| `connect` | `{"uuid","secrets":{"k":"v"}}` | `{"ok":true}`, or `{"ok":false,"need":["password",…],"type":"l2tp"}` when Ask secrets are missing, or `{"ok":false,"error":…}` |
| `oc-login` | `{"uuid","secrets":{…}}` | JSON-line conversation (§10) |

Delete and disconnect stay on plain `nmcli` (no secrets), so they work without the helper.

**Secret flags.** Save writes `K-flags = 0` (or `4`, not required, when there is no value); Ask writes `K-flags = 2` (not saved). `update` never removes `*-flags` data keys. Reading: flag `2` → ask; flag `1` (agent-owned) → **also ask**, because no agent is left to supply it once `nm-applet` is gone (profiles made with `nm-connection-editor` are usually agent-owned); otherwise save. WireGuard uses `wireguard.private-key-flags` and each peer's `preshared-key-flags`.

**Connect.** `nmcli --wait 90 connection up uuid U passwd-file <pipe>`, with lines `vpn.secrets.<key>:<value>` (or `wireguard.private-key:…`). `nmcli` accepts the pipe (verified in the VM test, §14), so no secret ever touches disk. strongSwan's secret names come from its auth dialog in external-UI mode, which needs a display: the desktop session has one, a headless shell does not.

**Our own metadata** (OpenConnect login method, username, pinned server certificate) goes in NetworkManager's generic `user` setting (`user.data`, keys `quickshell.vpn.*`), never as `vpn.data` keys: OpenVPN and OpenConnect reject data keys they don't recognise.

**Packaging.** `quickshell/scripts/nm-vpn.nix`: `python3.withPackages` with `pygobject3`, behind `makeWrapper`, so `GI_TYPELIB_PATH` holds libnm's and GLib's typelibs and `PATH` holds `nmcli` (Plan 2 adds `openconnect` the same way). Test hooks, as `IDENTITY_PASSWD_BIN` does: `NM_VPN_FAKE_STATE` (a JSON-file backend instead of libnm), `NM_VPN_NMCLI_BIN`, `NM_VPN_CONNECT_WAIT`.

**VM findings** (`nixos/tests/test-vpn-vm.sh`, NetworkManager 1.56.0, strongSwan 6.1.0, networkmanager-strongswan 1.6.5, 2026-11-09).
- `passwd-file` through a pipe works: `nm-vpn connect` and `nmcli … passwd-file <(…)` both get NetworkManager past the secrets stage, so no file fallback is needed.
- `charon-nm` coexists with `services.strongswan`, once `/etc/strongswan.conf` exists (§11).
- An imported OpenVPN profile arrives with `password-flags 1` (agent-owned), which `nm-vpn get` reads as `ask`. The importer also adds `challenge-response` (flags 2), turns `remote` into `host:port` and resolves a relative `ca` against the file's folder. It refuses a file with no `ca`.

**One request at a time.** `nm-vpn` handles one request at a time. A second request while one runs returns `Busy — try again`.

## 8. Schema `vpnSchema.js`

One entry per type, pure data:

```js
l2tp: { service: "org.freedesktop.NetworkManager.l2tp", label: "L2TP/IPsec", importExt: [], fields: [
  { key: "gateway",       label: "Gateway",        kind: "text",   required: true },
  { key: "user",          label: "Username",       kind: "text" },
  { key: "password",      label: "Password",       kind: "secret" },
  { key: "ipsec-enabled", label: "Use IPsec",      kind: "bool",   default: true },
  { key: "ipsec-psk",     label: "Pre-shared key", kind: "secret", showIf: { "ipsec-enabled": true } },
]}
```

- **Kinds:** `text`, `secret`, `bool` (stored `yes`/`no`), `choice` (fixed `options`), `file` (path; `~` expanded and existence checked by the helper), `number`.
- **`showIf`** hides fields that don't apply (OpenVPN `connection-type` decides between certificate and username/password fields). `buildRequest` leaves hidden fields out, so on save, switching OpenVPN's connection type drops the other type's keys.
- **Schemas shipped:** L2TP, OpenVPN, strongSwan, WireGuard (OpenConnect arrives with Plan 2). SSTP was dropped: `networkmanager-sstp` is flagged insecure (CVE-2026-91838) in the pinned nixpkgs, and that broke evaluation of the whole system. Key names are checked against each plugin before use (L2TP's are verified, §13). WireGuard entries set `native: true` and use setting paths (`wireguard.private-key`, `ipv4.addresses`, `ipv4.dns`, `peer.endpoint`, `peer.public-key`, `peer.allowed-ips`, `peer.preshared-key`, `peer.persistent-keepalive`) with one peer.
- **Common to every type:** `Use only for resources on its network` (`ipv4.never-default`).
- **Pure functions** (unit-tested by `tests/tst_vpn_schema.qml`): `defaults`, `defaultModes`, `isShown`/`fieldsFor`, `fromProfile`, `buildRequest`, `validate`, `typeForPath`, `importExtensions`, `pickerTypes`, `labelFor`, `cycleChoice`. Flag handling (`mode_from_flags`, `secret_keys`) lives only in `nm-vpn`: the shell gets modes, never flags.
- A type with no schema has no fields: its form is Name plus Advanced.

## 9. Views and keys

**View stack.** `/vpn` list → `VpnTypeView` → `VpnFormView` or `VpnImportView`. Edit goes from the list straight to `VpnFormView`. Transitions follow `STYLE.md` §2.5, generalised to a stack: a view below the top parks at `x: -60`, a view above it at `x: +60`; cross-fade; the card animates its height. Each view has `reset()` and `handleKey(e)`; `NetworkCenter.qml` routes keys to the top view (the Identity Manager pattern). The title gains `· Add <Type>`, `· Edit <name>` or `· Import`.

**`/vpn` list (existing, extended).** Rows: VPN profiles, then `Add VPN…`. "Open connection editor…" is removed. Keys: `Enter` connect/disconnect, `e` edit, `x` delete (`y/n`), `j/k`, `/` filter. Footer hints are updated.

**`VpnTypeView`.** `Import from file…` first, then the installed types (schema label, or the plugin name with `· advanced` when no schema exists). `j/k`, `/`, `Enter`, `Esc` back. Without plugins: WireGuard plus `More types: networking.networkmanager.plugins` at `Theme.fgDim`.

**`VpnFormView`.**
- Order: Name (required), schema fields, Common, then a collapsed **Advanced** header.
- Advanced (plugin types only) lists every `vpn.data` key not covered by the schema as a `key = value` row. Secret keys (reported by `nm-vpn get`) are masked and get a `Save | Ask` chip. `+ Add row` adds an empty row with a `Data | Secret` chip; a row whose key is cleared is removed on save.
- Secret fields use `SecretField` (eye, `Ctrl+S`), each followed by a **`Save | Ask`** chip.
- Keys: `Tab`/`Shift+Tab` and `Enter` move between stops; `Enter` on the last stop (Save) saves. `Space` toggles bools, chips, choices and the Advanced header; `h`/`l` cycle choices. `Esc` goes back, after `Discard changes? y / n` if anything changed.
- Edit prefills from `get`. Saved secrets show the placeholder `saved · leave empty to keep`, and their values never reach QML.
- A WireGuard profile with more than one peer shows its peers read-only with `N peers · re-import to change`.
- Validation: a missing required field blocks Save, takes focus and shows an inline `Theme.critical` line.

**`VpnImportView`.** Candidate files from one `find ~/Downloads ~/Documents -maxdepth 2` filtered by every schema's `importExt` (`.ovpn`, `.conf`, …), plus a path field for anything else. `j/k`, `/`, `Enter`. The type comes from `typeForPath`; when ambiguous, a picker shows only installed types with `import: true`. After import the stack becomes `/vpn` list → `VpnFormView` (Edit) on the new profile, so `Esc` returns to the list and keeps the profile.

**`VpnSecretPrompt`.** Inline in the `/vpn` view, like the Wi-Fi password dialog. One `SecretField` per needed key (label from `labelFor`, or the key name), or one event at a time during `oc-login`. `Ctrl+S` reveals, `Enter` goes to the next field and then submits, `Esc` cancels. On submit the fields are **cleared immediately** and the Current Connection card shows `Connecting to {name}…` (spec §3.1). Fields are also cleared on leaving the view and on close.

## 10. Connect flow and the OpenConnect login

**Every type except OpenConnect:**
1. `Enter` → `NetworkService.vpnConnect(uuid)` → `nm-vpn connect` with no secrets.
2. If the result is `need`, the prompt asks for those keys and calls `connect` again with them.
3. Success refreshes the poll. Failure shows an inline error, and `Enter` retries.

Without the helper, `vpnConnect` falls back to `nmcli connection up uuid` (today's behaviour).

**OpenConnect.** NetworkManager needs `cookie`, `gateway` and `gwcert`, which only come from a live login. `nm-vpn oc-login` runs `openconnect --authenticate --protocol=<p> [--servercert <pin>] [--external-browser=xdg-open] <gateway>` on a pseudo-terminal and relays the conversation:

| Out (helper → shell) | Meaning |
|---|---|
| `{"event":"prompt","id":n,"label":"Password:","secret":true}` | A question. `secret` comes from the pty's **echo flag** (`termios`), not from the wording |
| `{"event":"choice","id":n,"label":"GROUP:","options":["staff","admin"]}` | A prompt of the form `LABEL: [a\|b]:` |
| `{"event":"cert","id":n,"host":"vpn.example.com","pin":"pin-sha256:…"}` | Unknown server certificate |
| `{"event":"browser"}` | SSO started in the default browser |
| `{"event":"result","ok":true}` / `{"event":"result","ok":false,"error":…}` | End |

| In (shell → helper) | Meaning |
|---|---|
| `{"id":n,"answer":"…"}` | Answer to a prompt, choice or cert (`yes`/`no`) |
| `{"cancel":true}` | Kill openconnect and stop |

- Username and password prompts are answered automatically from the profile when they are saved; only the rest (OTP, group, cert) reaches the shell.
- An accepted pin is stored in `user.data` and passed as `--servercert` next time.
- The browser state shows `Finish signing in in your browser…`.
- On success the helper connects with `vpn.secrets.cookie`, `vpn.secrets.gateway` and `vpn.secrets.gwcert` through `passwd-file`.
- Timeout 5 minutes; `Esc` sends `cancel`.

`NetworkService` owns one `Process` for `oc-login` (`stdinEnabled`, line-split stdout) beside the one for single-shot commands.

The saved OpenConnect password is a `vpn.secrets` key named as the plugin's own auth dialog names it (`form:main:password`), *if* the plugin accepts it (§14). Otherwise the password is Ask-only.

## 11. Nix, removals and existing fixes

| File | Change |
|---|---|
| `nixos/configuration.nix` | `networking.networkmanager.plugins = with pkgs; [ networkmanager-openvpn networkmanager-strongswan networkmanager-l2tp ];` (SSTP dropped: `networkmanager-sstp` is flagged insecure, CVE-2026-91838, and broke evaluation of the whole system.) `services.strongswan` stays; an empty `environment.etc."strongswan.conf"` so `charon-nm` can start |
| `nixos/configuration.nix` (Plan 2) | `networkmanager-openconnect` is added together with the OpenConnect login (§10) |
| `nixos/programs/quickshell.nix` | Remove `networkmanagerapplet` (editor, tray applet, its XDG autostart). Add the `nm-vpn` package (§7) |
| `quickshell/services/NetworkService.qml` | Remove `vpnEditorProc`, `vpnAddProc`, `launchEditor()`, `vpnAdd()`. Add `helperAvailable`, `vpnTypes`, `vpnLoad(uuid)`, `vpnSave(request)`, `vpnImport(type, path)`, `vpnConnect(uuid, secrets)`, `ocAnswer(id, answer)` and `ocCancel()`. Errors use the existing `lastError` |
| `quickshell/services/NetworkService.qml` (fix) | The poll's active-VPN check greps `vpn` only, so an active **WireGuard** connection never shows as `vpnActive`. Match `wireguard` too, as `vpnProc` already does |

`/etc/strongswan.conf` is empty on purpose: `charon-nm` needs the file to exist, and so does nm-l2tp's IPsec starter. NixOS creates none, because `services.strongswan` points its own charon at a store file.

Left alone: the commented-out `nm-applet` line in `hypr/hyprland.lua` and `hypr/hyprland.conf`, `i3/config`, and the `nm-applet` example in `Tray-Manager.md` (still a valid example of a dbusmenu app).

**Degraded states.**
- `nm-vpn` missing: `Add VPN…` shows `Not available`, and list/connect/delete keep working through `nmcli`.
- No plugins: WireGuard only, plus the hint.
- Every helper failure is an inline `Theme.critical` line under the VPN list, cleared on the next success (spec §4).
- Timeouts: 30 s for single-shot commands, 90 s for connect, 5 min for `oc-login`.

## 12. Known limits

- Ask secrets only work for connects started from the Network Center. If NetworkManager needs secrets on its own (VPN autoconnect, re-authentication), nothing answers and that activation fails.
- Browser SSO depends on the protocol and the server supporting `openconnect --external-browser`.
- The Advanced section can set keys a plugin rejects; the plugin's error then appears when connecting.
- `nm-vpn` handles one request at a time. A second request while one runs returns `Busy — try again`.

## 13. Verified while designing (2026-11-09)

- `nmcli` 1.56.0. NixOS `networking.networkmanager.plugins` defaults to `[]`. nixpkgs: `networkmanager-openvpn` 1.12.5, `-openconnect` 1.2.10, `-strongswan` 1.6.5, `-l2tp` 1.52.0, `openconnect` 9.12. (`-sstp` 1.3.2 was also checked, then dropped: flagged insecure, CVE-2026-91838.)
- Only `nm-l2tp-service.name` is installed today. It declares a GNOME auth dialog and `supports-external-ui-mode=true`.
- L2TP keys, taken from the installed plugin binaries: `gateway`, `user`, `password`(`-flags`), `domain`, `ipsec-enabled`, `ipsec-psk`(`-flags`), `ipsec-gateway-id`, `ipsec-remote-id`, `ipsec-ike`, `ipsec-esp`, `ipsec-pfs`, `ipsec-forceencaps`, `ipsec-ipcomp`, `ipsec-ikelifetime`, `ipsec-salifetime`, `user-auth-type`, `user-ca`, `user-cert`, `user-key`, `user-certpass`(`-flags`), `machine-auth-type`, `machine-ca`, `machine-cert`, `machine-key`, `machine-certpass`(`-flags`). Every secret `K` has a `K-flags` data key.
- libnm's `NM-1.0.typelib` is present and exposes `conn_wireguard_import`, `VpnPluginInfo.list_load`/`load_editor_plugin`, the editor plugin's `import` and `get_capabilities`.
- `nm-applet` runs from XDG autostart (`wayland-session-xdg-autostart@hyprland.desktop.target`) because `networkmanagerapplet` is in `home.packages`. It is the session's only NetworkManager secret agent.
- `openconnect` is not on PATH today.

## 14. Not verified (answered by the VM test or by you)

- ~~Whether `nmcli … passwd-file` accepts a pipe~~: it does (VM test, 2026-11-09).
- ~~Whether `charon-nm` coexists with `services.strongswan`~~: it does, once `/etc/strongswan.conf` exists; charon-nm aborts without it, and NixOS creates none (VM test, 2026-11-09; §11).
- Key names for OpenVPN, OpenConnect and strongSwan (checked against each plugin before its schema is written).
- A strongSwan secret set to Ask needs a graphical session: the plugin's auth dialog starts GTK in external-UI mode, prints only the secret names and shows no window. The VM verified this under X11 only, not Wayland.
- L2TP with IPsec next to `services.strongswan` is untested, because they share the ipsec pid file and the IKE ports.
- Whether `nm-openconnect` accepts `form:*` secrets.
- That libnm import loads only each plugin's core library, not its GTK editor.
- Real connections to your own servers, OpenConnect against a corporate gateway, and browser SSO.

## 15. Testing

| Test | Proves |
|---|---|
| `quickshell/tests/tst_vpn_schema.qml` (run by `tests/run.sh`) | `buildRequest`, `showIf`, flag → mode, `secretKeysFromData`, `typeForPath`, Advanced rows |
| `quickshell/tests/test-nm-vpn.sh` | Helper with stubbed binaries: JSON protocol, scrubbing, `passwd-file` lines, the `need` handshake, `oc-login` against a fake `openconnect` (prompts, echo-off detection, choice, cert, browser, failure, cancel) |
| `quickshell/tests/smoke-vpn-views.sh` | Each new view loads offscreen with a stub `nm-vpn`; secret fields clear on submit and on leave |
| `nixos/tests/test-vpn.sh` | Evaluated config: the five plugins, no `networkmanagerapplet`, `nm-vpn` present |
| `nixos/tests/test-vpn-vm.sh` (opt-in, needs KVM; a NixOS VM test) | Real libnm round-trips per type (add/get/update/import/delete), `types` sees the plugins, `passwd-file` via a pipe, `charon-nm` beside `services.strongswan` |

Plus the repo checks in `AGENTS.md`.

## 16. Docs and specs

- `quickshell/specs/launchers/Network-Center.md`: the `/vpn` row in §3, §3.4 rewritten (add, import, edit, Save/Ask, prompt, OpenConnect login), §4 keys, §5 service contract, §6 acceptance (replace the `nm-connection-editor` items).
- `quickshell/specs/SPECS.md`: dependency table (plugins, `nm-vpn`).
- `README.md`: a VPN paragraph beside the `nmcli` Wi-Fi note.
- The Network Center footer hints.

## 17. Build order

1. `vpnSchema.js` and its tests.
2. `nm-vpn`: `types`, `get`, `add`, `update`, `import`, `connect`, with stub tests; Nix packaging and plugins; the VM test (answers §14).
3. `NetworkService` VPN API and the WireGuard `vpnActive` fix.
4. Views and `NetworkCenter.qml` integration; smoke test.
5. `oc-login` (helper and prompt events) with the fake-`openconnect` tests.
6. Remove `networkmanagerapplet` and the editor code; docs, specs and hints.
7. All repo checks.

Steps 1–4 already give a working native UI for every type except OpenConnect's login.
