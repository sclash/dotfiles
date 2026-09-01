# Network-Center — Refined Spec

> Command: `SUPER+w` · File: `components/launchers/NetworkCenter.qml` · Service: `NetworkService.qml`

---

## 1. Purpose

Center-screen window to inspect and mutate network state: current connection, known networks, scan, VPN. Mutations reflect in the `Wifi` bar icon via the shared `NetworkService`.

## 2. Window

* `LauncherBase.qml`: centered, `width: 620`, `radius: Theme.roundingLauncher`, `focusable: true`, `Esc` closes, vim `j/k` + `/` filter, `Enter` acts.
* **Hyprland:** layer on top; `layerrule = blur, quickshell` if compositor blur desired.

## 3. Sections (top → bottom, collapsible via keyboard)

### 3.1 Current Connection

* **Fields:** `ESSID` (bold), signal `({signal}%)`, `IPv4` (`ipaddr`), `VPN` line if `vpnActive` ("via {vpnName}").
* **Actions:** `Disconnect` button (visible only when `connected`). Calls `NetworkService.disconnect()` → `nmcli connection down id "{essid}"`.
* **Empty state:** if `!connected` → `"Not connected — scan or pick a known network"` at `Theme.fgMuted`.

### 3.2 Known Networks

* List of `nmcli -t -f NAME,TYPE connection show` wifi entries.
* Each row: `ssid` + `available` dot (`●` at `success` if in scan results, `fgDim` if not) + actions:
  * `Connect` — `nmcli connection up id "{name}"`.
  * `Forget` — `nmcli connection delete id "{name}"` with confirm (`y/n`).
* New wifi connections are **auto-added** to known — this is `NetworkManager` default (`connection.autoconnect`); no extra code needed, just don't disable it.

### 3.3 Scan Networks

* Trigger scan: `nmcli device wifi rescan` then `nmcli -t -f SSID,SIGNAL,SECURITY device wifi list --rescan no`.
* Display: list sorted by signal desc. Each row: `SSID` + `signal%` bar (text or thin `Rectangle` width = `signal%`) + `SECURITY` lock icon if not `--`.
* **Connect flow:** select row → if open network: `nmcli device wifi connect "{ssid}"`. If secured: prompt for password via an inline `TextField` (`placeholder: "Password for {ssid}"`, `echoMode: Password`), then `nmcli device wifi connect "{ssid}" password "{pwd}"`. On failure, show inline error (`Theme.critical`) + allow retry. On success, the new connection auto-appears in Known.

### 3.4 VPN

* List: `nmcli -t -f NAME,TYPE connection show | grep vpn` — `vpnName` + `Connected` pill if active.
* Actions per row:
  * `Connect` — `nmcli connection up id "{vpnName}"`.
  * `Disconnect` — `nmcli connection down id "{vpnName}"` (if active).
  * `Delete` — `nmcli connection delete id "{vpnName}"` with confirm.
* **Add new VPN:** `Add VPN…` button → opens a minimal form (name, type dropdown `wireguard/openvpn`, gateway, credentials). On submit: `nmcli connection import type {type} file {path-or-inline}` or `nmcli connection add type vpn …`. Because VPN flavours vary widely, v1 may delegate to `nm-connection-editor` or `nmtui` as a fallback button: `Process { command: ["nm-connection-editor"] }`. Document the delegation if the native form is deferred.

## 4. Shared Behaviours

* **Search/filter:** `/` focuses a `TextField`; typing filters all lists (current excluded). `Esc` when filter focused clears filter, second `Esc` closes launcher.
* **Vim nav:** `j/k` moves `currentIndex`, `Enter` acts on focused row/button. Section headers are not focusable.
* **Refresh:** `r` rescans wifi; `Ctrl+r` rescans + reloads known/VPN.
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

* [ ] Current connection shows ESSID, signal, IPv4, VPN if any; Disconnect works.
* [ ] Known list shows all wifi profiles with available/forget/connect.
* [ ] Scan lists by signal desc; secured connect prompts for password; open connect succeeds.
* [ ] Every new wifi connection appears in Known (NM default).
* [ ] VPN list/connect/delete/add works; `nm-connection-editor` fallback documented if native form deferred.
* [ ] Vim nav + `/` filter + `r` rescan + `Esc` close all work.
* [ ] Uses `LauncherBase` + `Theme.*` tokens; no hard-coded colours.
