# Bluetooth — Bar Icon — Refined Spec

> Parent: [`Bar.md`](./Bar.md) · Service: `services/BluetoothService.qml`

---

## 1. Purpose

Glyph in the right group reflecting Bluetooth controller power + connection state.
Click opens `Bluetooth-Center` (`SUPER+b`).

## 2. States & Glyphs

| State | Condition | Glyph | Colour | Tooltip |
|---|---|---|---|---|
| **Off / disabled** | `!powered` or `!available` | `Icons.bluetoothOff` (`󰂲`) | `Theme.fgDim` | `"Bluetooth off"` / `"No adapter"` |
| **On, no device** | `powered && connectedCount===0` | `Icons.bluetoothOn` (`󰂯`) | `Theme.fg` | `"{controllerAlias}\n0 connected"` |
| **Connected** | `connectedCount > 0` | `󰂯` + optional count badge | `Theme.accent` (or `Theme.fg` + count) | `"{controllerAlias}\n{connectedCount} connected\n{deviceList}"` |
| **Connected + battery** | device reports battery | same + `" {battery}%"` | `Theme.fg` | include battery per device |

Parity with Waybar's commented `bluetooth` block (`waybar/config.jsonc:56-68`):
`format-on: 󰂯`, `format-off: BT-off`, `format-disabled: 󰂲`.

* If a connected device reports `battery_percentage`, append `" 82%"` next to the glyph (Waybar `format-connected-battery`).
* Do not show per-device aliases on the bar — count is enough; details live in `Bluetooth-Center`.

## 3. Service Contract — `BluetoothService.qml`

```qml
QtObject {
  property bool available        // false if no adapter / BlueZ not running
  property bool powered
  property int connectedCount
  property string controllerAlias
  property string controllerAddress
  // enriched for launcher
  property list<QtObject> devices  // { alias, address, connected, battery, trusted, paired }
}
```

* **Data source:** DBus `org.bluez` — `org.bluez.Adapter1.Powered`, `org.bluez.Device1.Connected` + `PropertiesChanged` signals. This is event-driven; no polling.
* **Fallback:** `Process { command: ["bluetoothctl","show"] }` + `["bluetoothctl","devices","Connected"]` polled at 5s if DBus not available.
* **Adapter absence:** BlueZ service not running or `hciconfig` shows no `hci0` → `available=false`.

## 4. Interaction

* **Click** → `launcher.toggle("bluetooth")`.
* **Hover** → tooltip with controller alias + address + `"{n} connected"` + enumerate when connected (Waybar `tooltip-format*` parity).

## 5. Launcher Sync

`Bluetooth-Center` mutates the same `BluetoothService` (`connect`, `disconnect`, `remove`). Icon count/colour updates via DBus `PropertiesChanged` within 500 ms.

## 6. Error Handling

* No adapter → `󰂲` dimmed, tooltip "No Bluetooth adapter — is `bluetoothd` running?". No error spam.
* Permission denied on DBus → fallback to `bluetoothctl`; log once per 30s.

## 7. Acceptance

* [ ] Toggling Bluetooth power via `Bluetooth-Center` or `bluetoothctl power on/off` updates icon within 500 ms.
* [ ] Connecting/disconnecting a device updates count and tooltip.
* [ ] No adapter renders degraded glyph with explanatory tooltip.
* [ ] No per-icon polling; single `BluetoothService` owns all BlueZ interaction.
