# Bluetooth-Center — Refined Spec

> Command: `SUPER+b` · File: `components/launchers/BluetoothCenter.qml` · Service: `BluetoothService.qml`

---

## 1. Purpose

Center-screen window to manage Bluetooth: connected devices, known devices, scan/pair. Mutations reflect in the `Bluetooth` bar icon via the shared `BluetoothService`.

## 2. Window

* `LauncherBase.qml`: `width: 620`, `radius: Theme.roundingLauncher`, vim nav, `/` filter, `Esc` closes.

## 3. Sections (top → bottom)

### 3.1 Connected Devices

* List of `BluetoothService.devices.filter(d => d.connected)`.
* Each row: `alias` (bold) + `address` (`Theme.fgMuted`, `fontSizeSmall`) + `battery` if present (`" 82%"` at `Theme.fg`) + signal/battery bar if available.
* **Actions:**
  * `Disconnect` — `bluetoothctl disconnect {address}` or DBus `Device1.Disconnect`.
  * Row `Enter` also disconnects (primary action is disconnect for connected).

### 3.2 Known Devices

* List of paired/trusted but not necessarily currently connected: `bluetoothctl paired-devices` or DBus `Adapter1.Devices` where `Paired===true`.
* Each row: `alias` + `address` + availability dot:
  * `●` at `Theme.success` if device is in current scan results (in range).
  * `●` at `Theme.fgDim` if not seen recently.
* **Actions:**
  * `Connect` — `bluetoothctl connect {address}`.
  * `Forget` — `bluetoothctl remove {address}` / DBus `Adapter1.RemoveDevice` with confirm.
* **Auto-add:** every newly connected device that was not previously paired should be trusted/paired automatically — BlueZ does this when `pairable on` and `trust` is set on connect. After a successful `scan → connect`, call `bluetoothctl trust {address}` if `Trusted===false` so the device appears in Known next time.

### 3.3 Scan for Devices

* **Trigger:** `Scan` button or `r` key → `bluetoothctl scan on` (timeout 10s) then `bluetoothctl devices`.
* Display: all discovered devices sorted by RSSI (signal) desc, deduped. Each row: `alias` (or `address` if alias empty / `<unknown>`) + `RSSI` bar + `Paired` badge if already known.
* **Connect flow:** select row → `bluetoothctl pair {address}` if not paired (may trigger agent prompt), then `trust` + `connect`. If pairing requires PIN/passkey, show an inline `TextField` (`placeholder: "PIN for {alias}"`, numeric) and feed to `bluetoothctl` agent or BlueZ `Agent1.RequestPinCode`.
  * Minimal v1 may delegate pairing PIN to `blueman-manager` or `bluetuith` as fallback — document if native PIN form is deferred, but the scan list itself must be native.
* **Stop scan** after 10s or on `Esc` from scan section (`scan off`).

## 4. Shared Behaviours

* `/` filter across all lists; `j/k` moves focus; `Enter` primary action; `Esc` hierarchy: clear filter → stop scan → close launcher.
* `r` rescan; `Ctrl+r` reload known + rescan.
* Inline errors (`Theme.critical`) under the relevant section; clear on next success.
* Empty states at `Theme.fgMuted`: "No connected devices", "No known devices — scan to discover", "Scan to see nearby devices".

## 5. Service Contract

All `bluetoothctl` / DBus calls via `BluetoothService.qml`:

```qml
function disconnect(address: string): void
function connect(address: string): void
function forget(address: string): void
function trust(address: string): void
function startScan(): void
function stopScan(): void
```

DBus `PropertiesChanged` propagates to the bar icon.

## 6. Acceptance

* [ ] Connected section shows alias, address, battery/signal, with Disconnect.
* [ ] Known shows paired devices with availability dot; Forget with confirm; Connect works.
* [ ] Every newly connected device is trusted and appears in Known next open.
* [ ] Scan lists all nearby devices by signal; connect prompts for PIN when required.
* [ ] Vim nav + `/` filter + `r` rescan + `Esc` close/scan-stop all work.
* [ ] Uses `LauncherBase` + `Theme.*` tokens.
