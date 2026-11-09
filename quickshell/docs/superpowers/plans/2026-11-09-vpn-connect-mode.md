# VPN connect-mode chooser Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When the user activates a VPN in the Network Center, ask whether to send all traffic through it (default) or only its own network, and apply that choice for the connection.

**Architecture:** An inline `VpnModePrompt.qml` sits above the `/vpn` list. `NetworkCenter` routes activation through it, `NetworkService.vpnConnect` carries a `mode` field to the existing `nm-vpn` helper, and the helper sets `ipv4.never-default`/`ipv6.never-default` on the stored profile immediately before the existing `nmcli … passwd-file` activation, restoring the old value if activation fails.

**Tech Stack:** Quickshell QML, Python 3 + PyGObject/libnm, NetworkManager 1.56/`nmcli`, NixOS VM tests, bash smoke tests.

**Spec:** `quickshell/docs/superpowers/specs/2026-11-09-vpn-connect-mode-design.md`

## Global Constraints

- No machine-specific values, hostnames, usernames or `/home/<user>` paths.
- Secrets travel only on stdin and the `passwd-file` pipe; never in argv, logs, or output. The `mode` field is not a secret.
- `nm-vpn` requests stay backward compatible: an omitted/empty `mode` leaves the profile unchanged.
- QML uses `Theme.*` tokens, never hard-coded colours or glyphs.
- Without `nm-vpn` (`helperAvailable == false`) and for WireGuard, skip the prompt; connect exactly as today.
- Do not commit, push, merge or rebuild without the user's explicit permission. Leave the work in the worktree.
- Run tests from the worktree root.

## Review Focus

- **Ask secrets + a chosen mode:** the mode must survive the `need` round trip and reach the second `nm-vpn connect`. Tested in Task 3 (service) and Task 5 (NetworkCenter).
- **Activation failure:** the helper must restore the profile's previous `never-default`, not leave the failed choice behind. Tested in Task 2.
- **Old callers / WireGuard:** an `nm-vpn connect` request with no `mode` must not touch the profile. Tested in Task 1.
- **Already-active VPN:** activating the row must disconnect, not open the mode prompt. Tested in Task 5.
- **Missing helper:** `helperAvailable == false` must bypass the prompt and use the plain `nmcli` path. Tested in Task 5 (prompt must stay closed).

---

## File Structure

| File | Responsibility |
|---|---|
| `quickshell/scripts/nm-vpn.py` | Validate `mode`; set/restore `never-default` through libnm (or the JSON fake) before/after `nmcli` |
| `quickshell/services/NetworkService.qml` | Carry `mode` to the helper and remember it across the `need` handshake |
| `quickshell/components/launchers/network/VpnModePrompt.qml` | The inline two-choice prompt and its keyboard handling |
| `quickshell/components/launchers/NetworkCenter.qml` | Route VPN activation through the prompt; wire the chosen mode to the service |
| `quickshell/components/launchers/network/VpnSecretPrompt.qml` | Resubmit the connect with the remembered mode |
| `quickshell/tests/test_nm_vpn.py` | Helper mode tests (fake backend + fake nmcli) |
| `quickshell/tests/smoke/vpn-views.qml` | Prompt and NetworkCenter smoke checks |
| `quickshell/tests/smoke-vpn-views.sh` | Stub `nm-vpn` connect answers and log assertions |
| `nixos/tests/vpn-vm.nix` | Real-libnm `set_mode` round-trip with a stub `nmcli` |
| `quickshell/specs/launchers/Network-Center.md` | Normative UI/service contract |
| `quickshell/docs/superpowers/specs/2026-11-09-native-vpn-design.md` | Protocol/flow/test notes |

---

### Task 1: Helper applies and validates `mode`

**Files:**
- Modify: `quickshell/scripts/nm-vpn.py` (`cmd_connect`, `FakeBackend`, `LibnmBackend`)
- Test: `quickshell/tests/test_nm_vpn.py`

**Interfaces:**
- Consumes: existing `Failure`, `need_str`, `backend.load`, `nmcli_up`, `_ip_settings`, `_call`.
- Produces: `backend.set_mode(uuid: str, split: bool) -> str` returning `"full"`/`"split"` for the previous IPv4 mode; `nm-vpn connect` accepts `{"mode": "full"|"split"|""}`.

- [ ] **Step 1: Write the failing tests**

Add to `class Cli` in `quickshell/tests/test_nm_vpn.py`:

```python
    def saved_psk(self):
        self.run_cli("update", edit(uuid="u-office",
            secrets={"ipsec-psk": {"mode": "save", "value": "p"}}))

    def test_connect_mode_split_sets_never_default_yes(self):
        self.saved_psk()
        self.assertEqual(self.run_cli("connect", {"uuid": "u-office", "mode": "split"}), {"ok": True})
        self.assertEqual(self.stored("u-office")["native"]["ipv4.never-default"], "yes")
        self.assertEqual(self.stored("u-office")["native"]["ipv6.never-default"], "yes")

    def test_connect_mode_full_sets_never_default_no(self):
        self.saved_psk()
        with open(self.state) as f:
            st = json.load(f)
        st["profiles"]["u-office"]["native"]["ipv4.never-default"] = "yes"
        with open(self.state, "w") as f:
            json.dump(st, f)
        self.assertEqual(self.run_cli("connect", {"uuid": "u-office", "mode": "full"}), {"ok": True})
        self.assertEqual(self.stored("u-office")["native"]["ipv4.never-default"], "no")
        self.assertEqual(self.stored("u-office")["native"]["ipv6.never-default"], "no")

    def test_connect_without_mode_leaves_profile_unchanged(self):
        self.saved_psk()
        with open(self.state) as f:
            st = json.load(f)
        st["profiles"]["u-office"]["native"]["ipv4.never-default"] = "yes"
        with open(self.state, "w") as f:
            json.dump(st, f)
        self.assertEqual(self.run_cli("connect", {"uuid": "u-office"}), {"ok": True})
        self.assertEqual(self.stored("u-office")["native"]["ipv4.never-default"], "yes")

    def test_connect_mode_is_not_applied_when_secrets_are_missing(self):
        r = self.run_cli("connect", {"uuid": "u-office", "mode": "split"})
        self.assertEqual(r, {"ok": False, "need": ["ipsec-psk"], "type": "l2tp"})
        self.assertEqual(self.stored("u-office")["native"]["ipv4.never-default"], "no")

    def test_connect_rejects_bad_mode(self):
        r = self.run_cli("connect", {"uuid": "u-office", "mode": "both"})
        self.assertFalse(r["ok"])
        self.assertIn("mode must be full or split", r["error"])
        self.assertFalse(os.path.exists(self.args_file))
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash quickshell/tests/test-nm-vpn.sh`
Expected: the new tests fail; the helper ignores `mode`, so `never-default` stays `"no"`, and the bad-mode request succeeds instead of returning an error.

- [ ] **Step 3: Implement `mode` parsing and `set_mode`**

In `quickshell/scripts/nm-vpn.py`:

- Add a small validator near `cmd_connect`:

```python
def connect_mode(req):
    mode = req.get("mode", "")
    if mode not in ("", "full", "split"):
        raise Failure("mode must be full or split")
    return mode
```

- In `cmd_connect`, call `mode = connect_mode(req)` right after validating `uuid`/`secrets`, before `backend.load(uuid)`.
- After the `missing` check and before `nmcli_up`, add:

```python
    old = backend.set_mode(uuid, mode == "split") if mode else None
    try:
        nmcli_up(uuid, passwd_lines(rec, wanted), list(wanted.values()))
    except Failure:
        if old is not None:
            try:
                backend.set_mode(uuid, old == "split")
            except Failure:
                pass
        raise
    return {"ok": True}
```

- Add `set_mode` to `FakeBackend`:

```python
    def set_mode(self, uuid, split):
        rec = self.state["profiles"].get(uuid)
        if rec is None:
            raise Failure("No VPN profile %s" % uuid)
        native = rec.setdefault("native", {})
        old = native.get("ipv4.never-default", "no") == "yes"
        native["ipv4.never-default"] = "yes" if split else "no"
        native["ipv6.never-default"] = "yes" if split else "no"
        self._write()
        return "split" if old else "full"
```

- Add `set_mode` to `LibnmBackend`:

```python
    def set_mode(self, uuid, split):
        rc = self._remote(uuid)
        conn = self.NM.SimpleConnection.new_clone(rc)
        ip4, ip6 = self._ip_settings(conn)
        old = ip4.get_never_default()
        ip4.set_property("never-default", split)
        ip6.set_property("never-default", split)
        rc.replace_settings_from_connection(conn)
        self._call(lambda cb: rc.commit_changes_async(True, None, cb, None),
                   lambda src, res: src.commit_changes_finish(res))
        return "split" if old else "full"
```

- Update the module docstring's `connect` note: `mode` is optional and sets both `never-default` flags.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash quickshell/tests/test-nm-vpn.sh`
Expected: all tests pass, including the five new ones.

---

### Task 2: Restore the previous mode when activation fails

**Files:**
- Modify: `quickshell/scripts/nm-vpn.py` (`cmd_connect`, already partly in Task 1)
- Test: `quickshell/tests/test_nm_vpn.py`

**Interfaces:**
- Consumes: `backend.set_mode(uuid, split)` from Task 1.
- Produces: a failed `nm-vpn connect` leaves `ipv4.never-default` at its previous value.

- [ ] **Step 1: Write the failing test**

Add to `class Cli`:

```python
    def test_connect_mode_failure_restores_previous(self):
        self.saved_psk()
        with open(self.state) as f:
            st = json.load(f)
        st["profiles"]["u-office"]["native"]["ipv4.never-default"] = "yes"
        with open(self.state, "w") as f:
            json.dump(st, f)
        r = self.run_cli("connect", {"uuid": "u-office", "mode": "full"},
                         FAKE_NMCLI_FAIL="boom")
        self.assertFalse(r["ok"])
        self.assertEqual(self.stored("u-office")["native"]["ipv4.never-default"], "yes")
```

- [ ] **Step 2: Run it to verify it fails**

Run: `python3 quickshell/tests/test_nm_vpn.py Cli.test_connect_mode_failure_restores_previous -v`
Expected: FAIL because the profile stays at `"no"` after the failed full-mode connect.

- [ ] **Step 3: Confirm the restore block is in `cmd_connect`**

The `try/except Failure` around `nmcli_up` added in Task 1 already restores. If Task 1 implemented only the success path, add the restore now. Do not mask the original error: the restore is wrapped in its own `try/except Failure: pass`.

- [ ] **Step 4: Run the test to verify it passes**

Run: `python3 quickshell/tests/test_nm_vpn.py Cli.test_connect_mode_failure_restores_previous -v`
Expected: PASS.

- [ ] **Step 5: Run the whole helper suite**

Run: `bash quickshell/tests/test-nm-vpn.sh`
Expected: all tests pass.

---

### Task 3: Carry the mode through `NetworkService`

**Files:**
- Modify: `quickshell/services/NetworkService.qml:36-39, 123-154`
- Test: `quickshell/tests/smoke/vpn-views.qml`

**Interfaces:**
- Consumes: `nm-vpn connect` accepting `mode` (Task 1).
- Produces: `vpnConnect(uuid, secrets, mode)`; `property string vpnNeedMode`; `vpnCancelNeed()` clears it.

- [ ] **Step 1: Write the failing smoke step**

In `quickshell/tests/smoke/vpn-views.qml`, after the existing `need` check, add:

```qml
        function () {
            NetworkService.vpnConnect("uuid-l2tp", {}, "split")
        },
        function () {
            check("service: the mode survives the need handshake",
                  NetworkService.vpnNeedMode === "split", NetworkService.vpnNeedMode)
            NetworkService.vpnConnect("uuid-l2tp", { "ipsec-psk": "smoke-secret-1" },
                                      NetworkService.vpnNeedMode)
        },
```

Keep the existing `need` checks working; adjust their order so the first `vpnConnect` call has no mode (the default), and the new pair follows. The final `NetworkService.vpnConnect` in the prompt step should pass no mode, so it stays backward compatible.

- [ ] **Step 2: Run it to verify it fails**

Run: `bash quickshell/tests/smoke-vpn-views.sh`
Expected: `SMOKE FAIL service: the mode survives the need handshake` because `vpnNeedMode` does not exist (or is empty).

- [ ] **Step 3: Implement the service change**

In `quickshell/services/NetworkService.qml`:

- Add `property string vpnNeedMode: ""` beside `vpnNeedType`.
- Change the signature to `function vpnConnect(uuid, secrets, mode)`.
- Pass `mode: mode || ""` in the helper request:

```qml
        root._runHelper("connect", { uuid: uuid, mode: mode || "", secrets: secrets || {} }, r => {
```

- In the `need` branch, set `root.vpnNeedMode = mode || ""` immediately before `root.vpnNeed = r.need` (listeners must see it).
- In `vpnCancelNeed()`, clear `root.vpnNeedMode = ""`.
- Leave the no-helper fallback unchanged; it ignores `mode`.

- [ ] **Step 4: Run it to verify it passes**

Run: `bash quickshell/tests/smoke-vpn-views.sh`
Expected: all smoke checks pass, including the new `vpnNeedMode` check.

---

### Task 4: Add `VpnModePrompt.qml`

**Files:**
- Create: `quickshell/components/launchers/network/VpnModePrompt.qml`
- Test: `quickshell/tests/smoke/vpn-views.qml`

**Interfaces:**
- Produces:
  - `open(uuid: string, vpnName: string): void`
  - `handleKey(e): bool`
  - `cancel(): void`
  - `readonly property string selectedMode` (`"full"` or `"split"`)
  - `signal picked(string uuid, string mode)`
  - `signal cancelled()`
  - `objectName: "vpnModePrompt"`

- [ ] **Step 1: Write the failing smoke checks**

Add to `quickshell/tests/smoke/vpn-views.qml` (before the NetworkCenter steps):

```qml
        function () {
            shell.mp = shell.make("VpnModePrompt.qml")
            if (!shell.mp) return
            const got = []
            shell.mp.picked.connect((u, m) => got.push([u, m]))
            shell.mp.open("uuid-l2tp", "Office")
            check("mode prompt: opens at All traffic", shell.mp.visible && shell.mp.selectedMode === "full")
            shell.key(shell.mp, Qt.Key_J)
            check("mode prompt: j selects VPN-only", shell.mp.selectedMode === "split")
            shell.key(shell.mp, Qt.Key_Return)
            check("mode prompt: Enter emits the choice",
                  got.length === 1 && got[0][0] === "uuid-l2tp" && got[0][1] === "split", JSON.stringify(got))
            check("mode prompt: hides after choosing", !shell.mp.visible)
            let cancelled = false
            shell.mp.cancelled.connect(() => cancelled = true)
            shell.mp.open("uuid-l2tp", "Office")
            shell.key(shell.mp, Qt.Key_Escape)
            check("mode prompt: Esc cancels", cancelled && !shell.mp.visible)
            shell.mp.destroy()
        },
```

Add `property var mp: null` near the other properties.

- [ ] **Step 2: Run it to verify it fails**

Run: `bash quickshell/tests/smoke-vpn-views.sh`
Expected: `VpnModePrompt.qml loads` fails; the component does not exist.

- [ ] **Step 3: Create the component**

Create `quickshell/components/launchers/network/VpnModePrompt.qml` modeled on `VpnSecretPrompt.qml`:

- Root `Rectangle`, `objectName: "vpnModePrompt"`, `visible: uuid !== ""`, `Layout.fillWidth: true`, `implicitHeight: col.implicitHeight + Theme.padL * 2`, `radius: Theme.roundingItem`, `color: Theme.bgActive`, `border.color: Theme.borderSelected`, `border.width: 1`, `focus: true`.
- Properties: `property string uuid: ""`, `property string vpnName: ""`, `property int sel: 0`.
- Mode array:

```qml
    readonly property var modes: [
        { mode: "full", label: "All traffic through the VPN" },
        { mode: "split", label: "Only the VPN's own network" }
    ]
    readonly property string selectedMode: modes[sel].mode
```

- Signals: `signal picked(string uuid, string mode)`, `signal cancelled()`.
- Functions:

```qml
    function open(id, name) {
        uuid = id; vpnName = name; sel = 0
        forceActiveFocus()
    }
    function close() { uuid = ""; vpnName = ""; sel = 0 }
    function move(d) { sel = Math.max(0, Math.min(modes.length - 1, sel + d)) }
    function choose() {
        const id = uuid, m = selectedMode
        close(); picked(id, m)
    }
    function cancel() { close(); cancelled() }
    function handleKey(e) {
        if (e.key === Qt.Key_J || e.key === Qt.Key_Down) { move(1); e.accepted = true; return true }
        if (e.key === Qt.Key_K || e.key === Qt.Key_Up) { move(-1); e.accepted = true; return true }
        if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { choose(); e.accepted = true; return true }
        if (e.key === Qt.Key_Escape) { cancel(); e.accepted = true; return true }
        return false
    }
    Keys.onPressed: (e) => { handleKey(e) }
```

- Content: a header row with `Icons.vpn` and `"Connect to " + vpnName`; a `Repeater` over `modes` with two rows. Each row:
  - height ~28, `radius: Theme.roundingItem`
  - background `sel === index ? Theme.bgSelected : (ma.containsMouse ? Theme.bgHover : "transparent")`
  - selection marker: `Text { text: sel === index ? "▸" : " "; ... }` (use an `Icons` token if one fits; otherwise keep the marker out of the theme rule because it is a selection affordance, not an icon)
  - label `Text { text: modelData.label; ... color: Theme.fg }`
  - `MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; onClicked: { prompt.sel = index; prompt.choose() } }`
- Footer: `Text { text: "j/k choose · Enter connect · Esc cancel"; ... color: Theme.fgDim; Layout.alignment: Qt.AlignHCenter }`.
- Use only `Theme.*` tokens.

- [ ] **Step 4: Run the smoke test to verify it passes**

Run: `bash quickshell/tests/smoke-vpn-views.sh`
Expected: all checks pass, including the four `mode prompt:` checks.

---

### Task 5: Route `/vpn` activation through the prompt

**Files:**
- Modify: `quickshell/components/launchers/NetworkCenter.qml` (activate, row click, Escape, prompt instance, footer)
- Modify: `quickshell/components/launchers/network/VpnSecretPrompt.qml` (submit with `vpnNeedMode`)
- Test: `quickshell/tests/smoke/vpn-views.qml` + `quickshell/tests/smoke-vpn-views.sh`

**Interfaces:**
- Consumes: `VpnModePrompt.open/handleKey/cancel`, `NetworkService.vpnConnect(uuid, secrets, mode)`, `vpnNeedMode`.
- Produces: `NetworkCenter.requestVpnConnect(v)`, `readonly property bool modePromptOpen`.

- [ ] **Step 1: Write the failing smoke checks**

In `quickshell/tests/smoke/vpn-views.qml`, in the NetworkCenter step (after `nc.open()` and before the form checks), add:

```qml
            nc.view = "vpn"
            nc.updateModels()
            const vpnIdx = nc.navItems.findIndex(it => it.kind === "vpn")
            check("network: /vpn has a selectable VPN", vpnIdx !== -1, JSON.stringify(nc.navItems))
            nc.selIndex = vpnIdx
            nc.activate()
            check("network: activating a VPN opens the mode prompt", nc.modePromptOpen)
```

Then add a separate step that finds the prompt and picks `full`:

```qml
        function () {
            const nc = shell.nc
            if (!nc) return
            const mp = shell.findByName(nc.contentItem, "vpnModePrompt")
            check("network: the mode prompt is reachable", mp !== null && mp.visible)
            if (mp) {
                mp.sel = 0
                mp.choose()
            }
        },
```

Add a `findByName` helper beside `findFields`:

```qml
    function findByName(item, name) {
        if (item.objectName === name) return item
        for (let i = 0; i < item.children.length; i++) {
            const hit = findByName(item.children[i], name)
            if (hit) return hit
        }
        return null
    }
```

In `quickshell/tests/smoke-vpn-views.sh`, extend the Python log check:

```python
connects = [c for c in calls if c["argv"][:1] == ["connect"]]
ok(any(c["req"].get("mode") == "full" for c in connects),
   "the mode prompt's choice reaches nm-vpn")
```

Also update the stub `nm-vpn` connect branch so a WireGuard connect succeeds:

```python
elif cmd == "connect":
    if req.get("uuid") == "uuid-wg":
        out = {"ok": True}
    else:
        has = "ipsec-psk" in (req.get("secrets") or {})
        out = {"ok": True} if has else {"ok": False, "need": ["ipsec-psk"], "type": "l2tp"}
```

Add a WireGuard check in the NetworkCenter step:

```qml
            const wgIdx = nc.navItems.findIndex(it => it.kind === "vpn" && nc.filteredVpn[it.idx].type === "wireguard")
            check("network: the list carries the WireGuard profile", wgIdx !== -1, JSON.stringify(nc.navItems))
            nc.selIndex = wgIdx
            nc.activate()
            check("network: WireGuard skips the mode prompt", !nc.modePromptOpen)
```

Add an active-VPN check and a no-helper check in the same step, after the prompt pick:

```qml
            NetworkService.vpnCancelNeed()
            nc.resetVpnViews()
            NetworkService.vpnActive = true
            NetworkService.vpnName = "Office"
            nc.selIndex = vpnIdx
            nc.activate()
            check("network: an active VPN disconnects without the prompt", !nc.modePromptOpen)
            NetworkService.vpnActive = false
            NetworkService.vpnName = ""
            NetworkService.helperAvailable = false
            nc.activate()
            check("network: without nm-vpn the prompt is skipped", !nc.modePromptOpen)
            NetworkService.helperAvailable = true
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash quickshell/tests/smoke-vpn-views.sh`
Expected: `network: activating a VPN opens the mode prompt` fails because activation connects directly.

- [ ] **Step 3: Implement the integration**

In `quickshell/components/launchers/NetworkCenter.qml`:

- Add `readonly property bool modePromptOpen: modePrompt.visible` near the other VPN properties.
- Add `function requestVpnConnect(v)`:

```qml
    function requestVpnConnect(v) {
        if (!v) return
        if (NetworkService.vpnActive && NetworkService.vpnName === v.name) {
            NetworkService.vpnDisconnect(v.uuid)
            return
        }
        if (!NetworkService.helperAvailable || v.type === "wireguard") {
            NetworkService.vpnConnect(v.uuid)
            return
        }
        modePrompt.open(v.uuid, v.name)
        Qt.callLater(() => root.scrollToAnchor(modePrompt))
    }
```

- Replace the row's `onClicked` with `onClicked: root.requestVpnConnect(modelData)`.
- In `activate()`, replace the `kind === "vpn"` branch with `const v=filteredVpn[it.idx]; if(v) root.requestVpnConnect(v)`.
- Add the prompt instance after `VpnSecretPrompt`:

```qml
            VpnModePrompt {
                id: modePrompt
                onPicked: (uuid, mode) => {
                    NetworkService.vpnConnect(uuid, {}, mode)
                    Qt.callLater(() => mainCol.forceActiveFocus())
                }
                onCancelled: Qt.callLater(() => mainCol.forceActiveFocus())
            }
```

- In the Escape chain, add `else if(modePrompt.visible){ modePrompt.cancel(); e.accepted=true }` before the `secretPrompt.visible` branch.
- Change the `/vpn` footer to `"j/k · Enter connect · e edit · x delete · /nearby /known /vpn · Esc back"` (unchanged; the prompt itself explains the choice). If the line is too long, drop `· Esc back` only if the existing spec permits; do not change other views.
- In `quickshell/components/launchers/network/VpnSecretPrompt.qml`, change `NetworkService.vpnConnect(uuid, secrets)` to `NetworkService.vpnConnect(uuid, secrets, NetworkService.vpnNeedMode)`.

- [ ] **Step 4: Run the smoke test to verify it passes**

Run: `bash quickshell/tests/smoke-vpn-views.sh`
Expected: all checks pass, including the mode-prompt, WireGuard-skip, and log assertions.

---

### Task 6: Update the normative specs

**Files:**
- Modify: `quickshell/specs/launchers/Network-Center.md`
- Modify: `quickshell/docs/superpowers/specs/2026-11-09-native-vpn-design.md`

- [ ] **Step 1: Update `Network-Center.md`**

- §3.4 row keys: `Enter` connect (opens the route chooser) / disconnect.
- §3.4 connect bullet: describe `network/VpnModePrompt.qml`, the two choices, the default `All traffic`, `j/k`/`Enter`/`Esc`, and that the mode goes to `nm-vpn connect` as `mode` and sets `ipv4`/`ipv6.never-default` before activation. Note that Ask secrets follow in `VpnSecretPrompt.qml` and the mode is kept.
- §5 service contract: `function vpnConnect(uuid: string, secrets?: var, mode?: string): void`; add `vpnNeedMode` to the properties list.
- §6 acceptance: add `[ ] Activating a VPN asks All traffic (default) or VPN only; the choice changes the default route; Ask secrets still connect.`

- [ ] **Step 2: Update the native VPN design**

- §5 `connect` row: add `"mode":"full"|"split"` to the request and say an omitted/empty mode leaves the profile unchanged.
- §9 `/vpn` list keys: `Enter` opens the mode chooser.
- §10 step 1: `Enter` → `VpnModePrompt` → `vpnConnect(uuid, {}, mode)`.
- §12 tests: add the mode tests to the `test-nm-vpn.sh` and VM rows.
- Add a one-line `See also:` pointing at `2026-11-09-vpn-connect-mode-design.md`.

- [ ] **Step 3: Check the docs mention the new names**

Run: `grep -n "VpnModePrompt\|vpnNeedMode\|mode.*full.*split" quickshell/specs/launchers/Network-Center.md quickshell/docs/superpowers/specs/2026-11-09-native-vpn-design.md`
Expected: the new names appear in both files.

---

### Task 7: VM test for the real libnm write

**Files:**
- Modify: `nixos/tests/vpn-vm.nix`
- Test: `bash nixos/tests/test-vpn-vm.sh` (needs KVM)

- [ ] **Step 1: Add the subtest**

After the L2TP round-trip subtest, add:

```python
    with subtest("connect mode sets never-default and keeps secrets"):
        l2m = ok(vpn("add", {"type": "l2tp", "name": "t-mode",
            "data": {"gateway": "192.0.2.11", "user": "alice", "ipsec-enabled": "no"},
            "secrets": {"password": {"mode": "save", "value": "dummy-mode-pw"}},
            "native": {"ipv4.never-default": "no"}, "user": {}}))["uuid"]
        r = vpn("connect", {"uuid": l2m, "mode": "split"}, env="NM_VPN_NMCLI_BIN=/bin/true")
        assert r == {"ok": True}, r
        assert machine.succeed(f"nmcli -g ipv4.never-default connection show uuid {l2m}").strip() == "yes"
        assert machine.succeed(f"nmcli -g ipv6.never-default connection show uuid {l2m}").strip() == "yes"
        assert "dummy-mode-pw" in secrets_of(l2m)
        r = vpn("connect", {"uuid": l2m, "mode": "full"}, env="NM_VPN_NMCLI_BIN=/bin/true")
        assert r == {"ok": True}, r
        assert machine.succeed(f"nmcli -g ipv4.never-default connection show uuid {l2m}").strip() == "no"
        assert "dummy-mode-pw" in secrets_of(l2m)
```

- [ ] **Step 2: Run the VM test**

Run: `bash nixos/tests/test-vpn-vm.sh`
Expected: `OK` with the new subtest. If KVM is unavailable, report that the VM test was not run and why.

---

### Task 8: Final checks and hand-off

**Files:** none.

- [ ] **Step 1: Run the focused suites**

```bash
bash quickshell/tests/test-nm-vpn.sh
bash quickshell/tests/smoke-vpn-views.sh
bash quickshell/tests/test-vpn-schema-keys.sh
bash tests/check-no-hardcoded-home.sh
```

Expected: all pass.

- [ ] **Step 2: Run the broader Quickshell suite**

```bash
bash quickshell/tests/run.sh
```

Expected: all pass. If an unrelated pre-existing failure appears, report it separately; do not paper over it.

- [ ] **Step 3: Review the diff**

```bash
git diff --stat
git diff
```

Check: no secrets, no machine-specific values, `Theme.*` only in QML, `nm-vpn` mode omitted by old callers, docs match the code.

- [ ] **Step 4: Ask for commit/merge approval**

Do not commit. Report:
- what changed
- which tests ran and their result
- whether the VM test ran
- what was not verified (the live `DP` routing check, if not run)

Then ask the user whether to commit and whether to run the live full/split check against `DP`.
