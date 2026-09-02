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
| `/vpn` | vpn | current connection + VPN networks + config options (`Add VPN…`, `Open connection editor…`) |

The **Current Connection** status card (§3.1) and the scan/filter row are always visible in every view. Typing any other text filters the list of the active view.

### 3.1 Current Connection

* **Fields:** `ESSID` (bold), signal `({signal}%)`, `IPv4` (`ipaddr`), `VPN` line if `vpnActive` ("via {vpnName}").
* **Actions:** `Disconnect` button (visible only when `connected`). Calls `NetworkService.disconnect()` → `nmcli connection down id "{essid}"`.
* **Empty state:** if `!connected` → `"Not connected — scan or pick a known network"` at `Theme.fgMuted`.

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
* **Connect flow:** select row → if open network: `nmcli device wifi connect "{ssid}"`. If secured: prompt for password via an inline dialog (`placeholder: "Password for {ssid}"`, `echoMode: Password`), then `nmcli device wifi connect "{ssid}" password "{pwd}"`. The password field has a show/hide toggle: the eye button or `Ctrl+s` flips `echoMode` between `Password` and `Normal`. On failure, show inline error (`Theme.critical`) + allow retry. On success, the new connection auto-appears in Known.

### 3.4 VPN (`/vpn`)

* List: `nmcli -t -f NAME,TYPE connection show | grep vpn` — `vpnName` + `Connected` pill if active.
* Actions per row:
  * `Connect` — `nmcli connection up id "{vpnName}"`.
  * `Disconnect` — `nmcli connection down id "{vpnName}"` (if active).
  * `Delete` — `nmcli connection delete id "{vpnName}"` with confirm.
* **Configuration options:**
  * `Add VPN…` — opens `nm-connection-editor -c -t vpn` to create a new VPN profile.
  * `Open connection editor…` — opens `nm-connection-editor` for full management/editing of all profiles.
* **Empty state:** if no VPN profiles → `"No VPN connections"` at `Theme.fgDim`.

## 4. Shared Behaviours

* **Search/filter:** `/` focuses a `TextField`; typing filters the list of the active view (current excluded). `Esc` when filter focused clears filter, second `Esc` closes launcher.
* **View commands:** typing `/nearby`, `/known` or `/vpn` (with or without leading slash) switches the view and clears the field; the view persists until another command or the launcher closes (reopens to `nearby`).
* **Vim nav:** `j/k` moves `currentIndex`, `Enter` acts on focused row/button. Section headers are not focusable.
* **Refresh:** opening the launcher auto-triggers a wifi rescan (`NetworkService.rescanWifi()`) so the nearby list is fresh; `r` rescans again; `Ctrl+r` rescans + reloads known/VPN.
* **Error toast:** inline `Text { color: Theme.critical }` under the relevant section, auto-cleared on next success.

## 5. Service Contract

All `nmcli` invocations go through `NetworkService.qml` — no ad-hoc `Process` in the launcher.

```qml
// NetworkService extensions used here
function disconnect(): void
function connectKnown(name: string): void
function connectScanned(ssid: string, password?: string): void
function forget(name: string): void
function rescanWifi(): void
function vpnConnect(name: string): void
function vpnDisconnect(name: string): void
function vpnDelete(name: string): void
function vpnAdd(config: var): void
```

DBus `PropertiesChanged` or next poll propagates changes back to the `Wifi` icon.

## 6. Acceptance

* [ ] Launcher opens to `nearby` view by default; only nearby networks shown.
* [ ] `/nearby` shows only nearby; `/known` shows only known; `/vpn` shows VPN list + `Add VPN…` + `Open connection editor…`.
* [ ] Current connection shows ESSID, signal, IPv4, VPN if any; Disconnect works.
* [ ] Known list shows all wifi profiles with available/forget/connect.
* [ ] Scan lists by signal desc; secured connect prompts for password; open connect succeeds.
* [ ] Every new wifi connection appears in Known (NM default).
* [ ] VPN list/connect/delete/add works; `nm-connection-editor` fallback documented if native form deferred.
* [ ] Vim nav + `/` filter + view commands + `r` rescan + `Esc` close all work.
* [ ] Uses `LauncherBase` + `Theme.*` tokens; no hard-coded colours.
