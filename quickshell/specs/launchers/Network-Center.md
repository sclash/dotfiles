# Network-Center — Refined Spec

> Command: `SUPER+w` · File: `components/launchers/NetworkCenter.qml` · Service: `NetworkService.qml`

---

## 1. Purpose

Center-screen window to inspect and mutate network state: current connection, known networks, scan, VPN. Mutations reflect in the `Wifi` bar icon via the shared `NetworkService`.

## 2. Window

* `LauncherBase.qml`: centered, `width: 620`, `radius: Theme.roundingLauncher`, `focusable: true`, `Esc` closes, vim `j/k` + `/` filter, `Enter` acts.
* **Hyprland:** layer on top; `layerrule = blur, quickshell` if compositor blur desired.

## 3. Sections (view-based, one list shown at a time)

The launcher is **view-based**: exactly one list is visible at a time. The view is selected by a slash command in the filter field; it defaults to `nearby`.

| Command | View | Content |
|---|---|---|
| (default) `/nearby` | nearby | current connection + scanned networks only |
| `/known` | known | current connection + known networks only |
| `/vpn` | vpn | current connection + VPN profiles + `Add VPN…` |

The **Current Connection** status card (§3.1) and the scan/filter row are always visible in every view. Typing any other text filters the list of the active view.

### 3.1 Current Connection

* **Fields:** `ESSID` (bold), signal `({signal}%)`, `IPv4` (`ipaddr`), `VPN` line if `vpnActive` ("via {vpnName}").
* **Actions:** `Disconnect` button (visible only when `connected`). Calls `NetworkService.disconnect()` → `nmcli connection down id "{essid}"`.
* **Empty state:** if `!connected` → `"Not connected — scan or pick a known network"` at `Theme.fgMuted`.
* **Connecting state:** while a connection attempt is in progress (`connecting` flag on `NetworkService`) → `"Connecting to {ssid}…"` at `Theme.fgMuted`, replacing the fields/empty state. Shown immediately when a connect is initiated (including right after the password dialog is submitted) and cleared on success (fields render again) or failure (inline error per §4).

### 3.2 Known Networks (`/known`)

* List of `nmcli -t -f NAME,TYPE connection show` wifi entries.
* Each row: `ssid` + `available` dot (`●` at `success` if in scan results, `fgDim` if not) + actions:
  * `Connect` — `nmcli connection up id "{name}"`.
  * `Forget` — `nmcli connection delete id "{name}"` with confirm (`y/n`).
* New wifi connections are **auto-added** to known — this is `NetworkManager` default (`connection.autoconnect`); no extra code needed, just don't disable it.

### 3.3 Scan Networks (`/nearby`, default)

* Trigger scan: `nmcli device wifi rescan` then `nmcli -t -f SSID,SIGNAL,SECURITY device wifi list --rescan no`.
* Display: list sorted by signal desc. Each row: `SSID` + `signal%` bar (text or thin `Rectangle` width = `signal%`) + `SECURITY` lock icon if not `--`.
* **Empty state:** if no networks in scan results → `"No networks found — press r to rescan"` at `Theme.fgDim`.
* **Connect flow:** select row →
  * **Already known:** if the SSID has an existing profile (present in the known networks list, §3.2), connect directly via `nmcli connection up id "{ssid}"` — **never prompt for a password**, even when selected from the nearby view. NM supplies the saved credentials.
  * **Open network (not known):** `nmcli device wifi connect "{ssid}"`.
  * **Secured (not known):** prompt for password via an inline dialog (`placeholder: "Password for {ssid}"`, `echoMode: Password`), then `nmcli device wifi connect "{ssid}" password "{pwd}"`. The password field has a show/hide toggle: the eye button or `Ctrl+s` flips `echoMode` between `Password` and `Normal`. On **submit (`Enter`)** the dialog closes immediately and the Current Connection card switches to the connecting state (§3.1); the connect command then runs. On failure, clear the connecting state and show inline error (`Theme.critical`) + allow retry. On success, the new connection auto-appears in Known.

### 3.4 VPN (`/vpn`)

Native: no `nm-connection-editor`, no `nm-applet`. Design: `docs/superpowers/specs/2026-11-09-native-vpn-design.md`.

* **List:** `nmcli -t -f NAME,UUID,TYPE connection show` rows whose type is `vpn` or `wireguard`: name, plus `active` when connected. An active WireGuard connection counts as the active VPN.
* **Row keys:** `Enter` connect / disconnect · `e` edit · `x` delete (`y/n`).
* **Connect:** `NetworkService.vpnConnect(uuid)` → `nm-vpn connect`. Secrets set to **Ask** come back as `need`. That covers flag `2`, and also `1` (agent-owned), since no agent is left to supply it. An inline prompt (`network/VpnSecretPrompt.qml`) asks for them: one masked field per secret, labelled from the schema, `Ctrl+s` show/hide, `Enter` next / connect, `Esc` cancel. It clears its fields at once, and the values go through `nmcli … passwd-file` on a pipe. The Current Connection card shows `Connecting to {name}…`.
* **`Add VPN…`** opens `network/VpnTypeView.qml`: `Import from file…` first, then the installed types (every plugin in `networking.networkmanager.plugins`, plus WireGuard). Types without a schema show `advanced`.
* **Form** (`network/VpnFormView.qml`): Name, the type's fields from `services/vpnSchema.js`, `Use only for resources on its network` (`ipv4.never-default`), then a collapsed **Advanced** section. Advanced lists every other `vpn.data` key as `key = value`; `+ Add row` adds one, with a `Data | Secret` chip; clearing a key removes it. Each secret has a **`Save | Ask`** chip (default Save). Saved secrets never come back: their box reads `saved · leave empty to keep`. Keys: `Tab`/`Shift+Tab`/`Enter` move, `Enter` on the last stop saves, `Space` toggles, `h`/`l` cycle choices, `Ctrl+s` show/hide, `Esc` back. `Esc` asks `Discard changes? y / n` when something changed. A WireGuard profile with several peers shows `N peers · re-import to change`. Editing never adds a setting the profile lacks (such as `ipsec-enabled`) unless that field is changed; the field shows what the plugin assumes when it's missing.
* **Import** (`network/VpnImportView.qml`): config files from `~/Downloads` and `~/Documents` (depth 2, newest first), plus a path field; there's no file-picker window. The extension picks the type. When several installed types claim it, a short picker asks. The profile is created at once, with autoconnect off (like an added one, it connects only from here), and opens in the form; `Esc` there returns to the list.
* **Empty state:** no profiles → `"No VPN connections"` at `Theme.fgDim`. Without `nm-vpn` → `Add VPN… · Not available`, and list, connect and delete keep working through `nmcli`.
* **Not offered yet:** OpenConnect. Its login needs its own step (design §10).

## 4. Shared Behaviours

* **Search/filter:** `/` focuses a `TextField`; typing filters the list of the active view (current excluded). `Esc` when filter focused clears filter, second `Esc` closes launcher.
* **View commands:** typing `/nearby`, `/known` or `/vpn` (with or without leading slash) switches the view and clears the field; the view persists until another command or the launcher closes (reopens to `nearby`).
* **Vim nav:** `j/k` moves `currentIndex`, `Enter` acts on focused row/button. Section headers are not focusable.
* **Refresh:** opening the launcher auto-triggers a wifi rescan (`NetworkService.rescanWifi()`) so the nearby list is fresh; `r` rescans again; `Ctrl+r` rescans + reloads known/VPN.
* **Error toast:** inline `Text { color: Theme.critical }` under the relevant section, auto-cleared on next success.
* **VPN views:** the type picker, form and import view slide over the list as a stack (`STYLE.md` §2.5: views below the top park at `x: -60`, the rest at `+60`; cross-fade; the card animates its height). Each view handles its own keys; `Esc` returns one level.

## 5. Service Contract

All `nmcli` invocations go through `NetworkService.qml` — no ad-hoc `Process` in the launcher.

```qml
// NetworkService extensions used here
function disconnect(): void
function connectKnown(name: string): void
function connectScanned(ssid: string, password?: string): void
// connectScanned resolves the ssid against known profiles internally:
// known → nmcli connection up (password ignored); unknown → device wifi connect.
function forget(name: string): void
function rescanWifi(): void
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

DBus `PropertiesChanged` or next poll propagates changes back to the `Wifi` icon.

## 6. Acceptance

* [ ] Launcher opens to `nearby` view by default; only nearby networks shown.
* [ ] `/nearby` shows only nearby; `/known` shows only known; `/vpn` shows the VPN list + `Add VPN…`.
* [ ] Current connection shows ESSID, signal, IPv4, VPN if any; Disconnect works.
* [ ] Known list shows all wifi profiles with available/forget/connect.
* [ ] Scan lists by signal desc; secured connect prompts for password; open connect succeeds.
* [ ] Connecting to an already-known SSID from the nearby view never prompts for a password.
* [ ] Submitting the password closes the dialog immediately; Current Connection shows `"Connecting to {ssid}…"` until the attempt resolves.
* [ ] Every new wifi connection appears in Known (NM default).
* [ ] VPN add (every installed type), import (`.ovpn`, `.conf`), edit, delete and connect work in the shell. Saved secrets are never shown; each secret is Save or Ask; Ask prompts at connect.
* [ ] No `nm-connection-editor` or `nm-applet` window ever opens (`networkmanagerapplet` is not installed).
* [ ] An active WireGuard connection shows as the active VPN.
* [ ] Vim nav + `/` filter + view commands + `r` rescan + `Esc` close all work.
* [ ] Uses `LauncherBase` + `Theme.*` tokens; no hard-coded colours.
