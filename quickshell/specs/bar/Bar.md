# Bar — Refined Spec

> Parent: [`SPECS.md`](../SPECS.md) · Style: [`STYLE.md`](../STYLE.md)
> File: `Bar.qml`. One `PanelWindow` per screen via `Variants { model: Quickshell.screens }`.

---

## 1. Purpose

Top-of-screen shell bar. Keyboard-driven: every icon is display-only but clicking
(or pressing its bound `SUPER+<key>`) opens the corresponding launcher. The bar
itself never captures text input.

## 2. Geometry

* `PanelWindow` with `anchors { top: true; left: true; right: true }`.
* `exclusionMode: ExclusionMode.Auto` — reserves space so tiled windows sit below.
* `implicitHeight: Theme.barHeight` (30 px, matching `Bar.qml:18` and Waybar).
* Transparent window (`color: "transparent"`), inner pill `Rectangle`:
  * `color: Theme.bgBar`, `radius: Theme.roundingBar`, `border { width: 1; color: Theme.border }`.
  * Outer margins: `10px` top, `5px` bottom, `10px` left/right split across three pills
    — replicate Waybar's `.modules-left/center/right` (see `waybar/style.css:11-33`):
    * Left pill: `margin: 10px 0 5px 10px`
    * Center pill: `margin: 10px 0 5px 0`
    * Right pill: `margin: 10px 10px 5px 0`
  * Each pill: `padding: Theme.padM (7px)`, `shadow: Theme.shadow` range 4.
* Alternatively implement as **single full-width `PanelWindow`** with three
  internal `RowLayout`s (left / center / right) inside one pill — either is
  acceptable as long as the visual result matches the three-pill Waybar look.
  Preferred: **three pills** to preserve Waybar parity; if compositor layer
  ordering makes that fragile, fallback to single pill with internal groups.

## 3. Layout (left → right)

```
┌─────────────────────────────────────────────────────────────────┐
│ [Workspaces · AppTray]      [  Date  (· bell)  ]    [◀ Perf][Audio][BT][Wifi][KB][Tray] │
│  left pill                   center pill              right pill                        │
└─────────────────────────────────────────────────────────────────┘
```

* **Left pill** — `Bar-Desktop-Environment.md` + `Bar-App-Tray.md` (`components/bar/Workspaces.qml`, `AppTray.qml`). See `./desktop-environnment/*`.
* **Center pill** — `Date.md` (`components/bar/DateBlock.qml`). Includes notification-bell glyph.
* **Right pill** — left-to-right inside the pill:
  1. `Bar-performance.md` drawer handle + collapsed/expanded metrics (`PerfDrawer.qml`)
  2. `Audio.md` (`AudioIcon.qml`)
  3. `Bluetooth.md` (`BluetoothIcon.qml`)
  4. USB storage indicator (`launchers/Usb-Manager.md` — inline in `Bar.qml`, `UsbService`)
  5. `Wifi.md` (`WifiIcon.qml`)
  6. `KeyBoard.md` (`KeyboardIcon.qml`)
  7. `Battery` (`BatteryIcon.qml`, rightmost — hidden when no battery present)
  8. `SystemTray` (`AppTray.qml` tray overflow or inline — see decision below)

Order is normative; do not reorder without updating `SPECS.md:5.1`.

## 4. Component Contract

Each bar icon is a **pure view** over a shared singleton service:

| Icon | Service | Properties consumed |
|---|---|---|
| Wifi | `NetworkService` | `status`, `signalStrength`, `vpnActive` |
| Audio | `AudioService` / `Pipewire` | `volume`, `muted`, `sinkName` |
| Bluetooth | `BluetoothService` | `powered`, `connected`, `connectedCount` |
| USB storage | `UsbService` | `available`, `hasStorage`, `anyMounted`, `busyNode` |
| Keyboard | Hyprland IPC | `layoutName` (e.g., `US`, `IT`) |
| Battery | `BatteryService` | `capacity`, `charging`, `available` |
| Perf | `PerfService` | `cpu/gpu`, `mem`, `disk`, `temp` |
| Tray | `SystemTray` | `items` |
| Date | local `Timer` | `formattedDate` |

No icon polls on its own; only services poll or listen to DBus/PipeWire.

## 5. Interaction

* **Click** on an icon → `IpcHandler` toggles the matching launcher (see `SPECS.md:3.4`).
  * Wifi → `Network-Center` (`SUPER+w`)
  * Audio → `Audio-Center` (`SUPER+a`)
  * Bluetooth → `Bluetooth-Center` (`SUPER+b`)
  * Keyboard → `hyprctl switchxkblayout … next` (no launcher; cycles layout)
  * Perf handle → expands/collapses the perf drawer (also `SUPER+p`)
  * Date → toggles `Notification-Center` (`SUPER+SHIFT+a`) — see `Date.md`
  * Workspaces → `hyprctl dispatch workspace <id>` (handled by `Hyprland` singleton)
* **Hover** → `Theme.durationNormal` colour transition; tooltip shows detail (see each icon spec).
* **No text input** on the bar itself.

## 6. States

* **Normal** — all icons at `Theme.fg` on `Theme.bgBar`.
* **Hover** — `color: rgba(255,255,255,0.7)` transition (Waybar semantics).
* **Warning / Critical** — perf metrics tint per thresholds; battery (if added) tints similarly. Other icons do not blink.
* **Degraded** — if a service reports `unavailable`, icon dims to `Theme.fgDim` and tooltip explains (e.g., "NetworkManager unavailable").

## 7. Multi-monitor

* `Variants { model: Quickshell.screens }` — one bar per screen.
* Workspaces shown are those assigned to that screen (`Hyprland.workspaces` filtered by `monitor`).
* Center/right pills are identical across screens; no per-screen perf divergence.

## 8. Acceptance

* [ ] Renders on every screen without QML warnings.
* [ ] Three-pill geometry matches Waybar screenshots at 1920×1080.
* [ ] Each icon opens its launcher (or cycles layout for Keyboard) via click and via `SUPER+<key>`.
* [ ] No icon performs its own polling; services are shared.
* [ ] `Theme.*` tokens used exclusively; no hard-coded colours.
* [ ] Degraded states render with tooltip.
