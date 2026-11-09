# VPN connect-mode chooser — design

**Status:** Approved (2026-11-09). Builds on
[`2026-11-09-native-vpn-design.md`](2026-11-09-native-vpn-design.md).

## Intent

Today a VPN profile's route mode is a stored property
(`ipv4.never-default`), changed in **Edit → Common → Use only for
resources on its network**. The `/vpn` list connects immediately, so the
user has to remember the profile's mode before pressing `Enter`.

The user wants to pick the mode **when connecting**, with **all traffic
through the VPN** as the default. Split tunneling stays available for
the times a VPN is only needed for its own resources.

## Goals

- Activating a non-active VPN opens a two-choice prompt:
  - **All traffic through the VPN** (preselected, the default)
  - **Only the VPN's own network**
- `Enter` connects with the highlighted choice; `j`/`k` (or arrows)
  move; `Esc` cancels.
- The choice reaches `nm-vpn connect` and is applied before the
  connection is activated.
- Ask secrets still work: the secret prompt follows the mode prompt and
  remembers the chosen mode.
- The existing profile editor, `nm-vpn` protocol and `nmcli passwd-file`
  secret path keep working unchanged.

## Non-goals

- WireGuard mode switching. `ipv4.never-default=yes` suppresses a
  `0.0.0.0/0` peer route, but when `allowed-ips` is a split list,
  `never-default=no` cannot create a full tunnel. WireGuard profiles
  connect exactly as today, without the mode prompt.
- IPv6 leak-proofing. `ipv6.never-default` is set to match the choice,
  but a full tunnel only carries IPv6 if the VPN provides it. If the
  LAN has global IPv6 and the VPN does not, IPv6 can still bypass the
  tunnel.
- Ephemeral per-connection profiles (temporary clones or in-memory
  connections). The stored profile keeps the last successful choice.
- OpenConnect (native-vpn Plan 2, not built).
- Changing DNS behavior, `ipv4.dns-priority`, or routes pushed by the
  server. The chooser controls NetworkManager's `never-default`; whether
  a server offers a default route is up to the server.

## Anti-goals

- A second profile per VPN that duplicates secrets and has to be kept
  in sync.
- Passing secrets or mode over argv, or logging them.
- Any machine-specific value in the repo.
- A prompt that appears on an already-active VPN; activating that row
  still disconnects.

## Constraints

- `nm-vpn` is the only writer; secrets travel on stdin only
  (native-vpn design §5).
- `nm-vpn` requests must stay backward compatible: an omitted `mode`
  means "leave the profile's route setting alone".
- The UI uses `Theme.*` tokens and the existing inline-prompt pattern
  (`VpnSecretPrompt.qml`).
- One `Process` per subsystem in `NetworkService`; the helper already
  serializes requests.
- Without `nm-vpn` (`helperAvailable == false`), the prompt is skipped
  and the list connects through `nmcli` as today; the stored profile
  mode applies.
- The change must not break the VM tests or the existing smoke test.

## Approaches considered

| Approach | Trade-off | Verdict |
|---|---|---|
| **A. Set `never-default` on the stored profile just before `nmcli up`** | One libnm write; reuses the tested `nmcli passwd-file` connect. The stored profile keeps the last choice; on connect failure the helper restores the previous value. | **Chosen** |
| B. Temporary clone per connection | Saved profile untouched, but needs clone lifecycle, unique names/UUIDs, WireGuard interface-name conflicts, copied secrets, and a hidden UUID the list must track. | Rejected: fragile |
| C. In-memory connection activated over D-Bus | Cleanest semantics, but replaces the proven `nmcli passwd-file` secret-agent path and reworks the connect flow. | Rejected: high regression risk |
| D. Two profiles per VPN | No code, but duplicates secrets and edits; does not match "asked each connect". | Rejected |

## Design

### UX

`NetworkCenter.qml` gets an inline `VpnModePrompt.qml`, modeled on
`VpnSecretPrompt.qml`, below the VPN list:

```
Connect to DP
  ▸ All traffic through the VPN
    Only the VPN's own network
  j/k choose · Enter connect · Esc cancel
```

- Selection index starts at 0 (`full`) every time the prompt opens.
- `Enter` emits `picked(uuid, "full"|"split")`; `Esc` emits `cancelled`.
- After either, focus returns to the main column and the prompt hides.
- Closing the Network Center, leaving `/vpn`, or a `need` arriving from
  another connect clears the prompt (`resetVpnViews`/`onVpnNeedChanged`).
  The prompt is only visible while `view === "vpn"`, so it cannot reappear
  stale or connect a choice the user abandoned.
- While open, the prompt owns the keyboard: keys it does not use are
  swallowed, so `x`, `e`, `d` and `r` never reach the list behind it.
- Mouse: each option row is clickable.
- The card scrolls the prompt into view (`scrollToAnchor`).

`NetworkCenter.requestVpnConnect(v)` is the single activation path for
both `Enter` and row clicks:

- active VPN → `NetworkService.vpnDisconnect(uuid)`, no prompt.
- `helperAvailable == false` or `v.type == "wireguard"` →
  `NetworkService.vpnConnect(uuid)` (no mode; profile unchanged).
- otherwise → open `VpnModePrompt` with the UUID and name.

The footer hint in `/vpn` says `Enter connect · e edit · x delete`
(unchanged; the prompt explains the extra choice).

### Service flow

`NetworkService.vpnConnect(uuid, secrets, mode)` gains the optional
`mode` argument and sends:

```json
{"uuid": "...", "mode": "full" | "split", "secrets": {"...": "..."}}
```

- `mode` is `""` when the caller must not change the profile
  (WireGuard, or the no-helper fallback).
- On a `need` answer, the service stores the mode in
  `NetworkService.vpnNeedMode` before setting `vpnNeed` (listeners see
  a consistent state).
- `VpnSecretPrompt.submit()` calls
  `vpnConnect(vpnNeedUuid, secrets, vpnNeedMode)`.
- `vpnCancelNeed()` clears `vpnNeedMode`.

### Helper protocol and backend

`nm-vpn connect` accepts an optional `"mode"`:

- absent or `""`: leave the profile unchanged (backward compatible).
- `"full"`: `ipv4.never-default = false`, `ipv6.never-default = false`.
- `"split"`: `ipv4.never-default = true`, `ipv6.never-default = true`.
- anything else: `Failure("mode must be full or split")`.

Order in `cmd_connect`:

1. Load the profile and compute missing Ask secrets.
2. If keys are missing, return `need` **without touching the profile**.
3. If `mode` is set, call `backend.set_mode(uuid, split)` and remember
   the previous mode.
4. Run the existing `nmcli_up(...)`.
5. If `nmcli_up` fails, restore the previous mode (best effort, without
   masking the original error) and re-raise.

`LibnmBackend.set_mode(uuid, split)`:

- Load the `NM.RemoteConnection`, clone it with
  `NM.SimpleConnection.new_clone(rc)`.
- Get/create the IPv4 and IPv6 settings (`_ip_settings`), set both
  `never-default` properties, replace and commit as `save()` already
  does.
- Return `"split"` if the old IPv4 `never-default` was true, else
  `"full"`.
- Secrets are already loaded into `rc` by the preceding `load()`, which
  is the same pattern `save()` relies on; the VM test checks that a mode
  change does not erase stored secrets.

`FakeBackend.set_mode(uuid, split)` updates
`native["ipv4.never-default"]` and `native["ipv6.never-default"]` in the
JSON state and returns the previous mode.

### Persistence

- A successful connect leaves the profile at the chosen mode. The next
  connect always opens the prompt at `full`, so the user-visible default
  is full.
- A failed connect restores the previous stored mode.
- An external `nmcli connection up <profile>` uses the last successful
  choice; this is documented, not reset on disconnect. Resetting would
  add another write and race with the disconnect.

### Files

| File | Change |
|---|---|
| `quickshell/services/NetworkService.qml` | `vpnNeedMode`; `vpnConnect(uuid, secrets, mode)`; set/clear `vpnNeedMode`; include `mode` in the helper request |
| `quickshell/components/launchers/network/VpnModePrompt.qml` | New inline prompt (two rows, keyboard + mouse) |
| `quickshell/components/launchers/NetworkCenter.qml` | `requestVpnConnect()`, open the prompt, `picked` → `vpnConnect`, focus/Esc handling, scroll into view |
| `quickshell/components/launchers/network/VpnSecretPrompt.qml` | Submit with `vpnNeedMode` |
| `quickshell/scripts/nm-vpn.py` | `mode` parsing, `set_mode()` on both backends, apply/restore around `nmcli_up` |
| `quickshell/specs/launchers/Network-Center.md` | `/vpn` connect flow, keys, service contract, acceptance |
| `quickshell/docs/superpowers/specs/2026-11-09-native-vpn-design.md` | `connect` request row, connect flow, tests |
| `quickshell/tests/test_nm_vpn.py` | Mode unit tests (see below) |
| `quickshell/tests/smoke/vpn-views.qml` | Prompt checks + mode in the stub log |
| `quickshell/tests/smoke-vpn-views.sh` | Stub `nm-vpn` already logs the request; assert `mode` |
| `nixos/tests/vpn-vm.nix` | Libnm `set_mode` round-trip with a stub `nmcli`; stored secrets survive |

## Tests

### `quickshell/tests/test_nm_vpn.py` (fake backend + fake nmcli)

- `mode=full` sets `ipv4.never-default` to `"no"`.
- `mode=split` sets it to `"yes"`.
- A `need` answer leaves the mode untouched.
- A failed `nmcli` restores the previous mode.
- An omitted/empty mode leaves the profile untouched (backward
  compatibility).
- An invalid mode is rejected.
- The mode does not appear in the fake `nmcli` argv; secrets still only
  travel on the pipe.

### `quickshell/tests/smoke-vpn-views.sh`

- `VpnModePrompt.qml` instantiates; default selection is `full`.
- `j`/`k` move the selection; `Enter` emits `picked(uuid, mode)`;
  `Esc` emits `cancelled`.
- A connect through the prompt reaches the `nm-vpn` stub with the
  chosen `mode`.
- An active VPN still disconnects from the row; no prompt.

### `nixos/tests/test-vpn-vm.sh`

- Add a subtest: create an L2TP profile with a saved password, point
  `NM_VPN_NMCLI_BIN` at a stub that exits 0, run `nm-vpn connect` with
  `mode=split`, and check `ipv4.never-default=yes` and that the saved
  secret is still present; repeat with `mode=full`.

### Live check (after implementation, with permission)

- Connect `DP` choosing **All traffic**; confirm a default route on
  `ppp0` and that the public IP changes.
- Disconnect, reconnect choosing **Only the VPN's own network**;
  confirm the default route is back on Wi-Fi and the public IP is the
  home IP.

## What is left to the builder

- The exact libnm call (`update2` with only the IP settings vs. the
  clone-and-commit pattern `save()` already uses). The clone-and-commit
  path is proven in this codebase; use it unless the VM test shows it
  disturbs secrets.
- The visual layout details of `VpnModePrompt.qml` within `STYLE.md`.
- Whether the footer hint needs a `· mode` mention; keep it short.
