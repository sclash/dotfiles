# Power-Center — Refined Spec

> Command: `SUPER+p` · File: `components/launchers/PowerCenter.qml` · Service: `services/BatteryService.qml`

---

## 1. Purpose

Center-screen battery status card. Shows charge percentage and a **live estimate of
time left unplugged** when the machine runs on battery, with state colours that
match the bar battery icon. Display-only — no power-profile mutation; power
actions (suspend/reboot/poweroff) stay in `Shutdown-Launcher.md`.

A **bar icon** in the right group (`components/bar/BatteryIcon.qml`, between VPN
and Keyboard in `Bar.qml`) mirrors charge state read-only from `BatteryService`:
tier glyph from `Icons.batteryLevels` (`cap <= 20 / 30 / 50 / 70 / 90`), `Icons.batteryCharging`
while charging, `Icons.batteryPlugged` on AC; `capacity%` caption hidden when
plugged; `Theme.critical` at `<= 20%`, `Theme.warning` at `<= 30%`,
`Theme.success` while charging; hidden entirely (`visible: false`) when no
battery is present. Click toggles this launcher (`power`).

## 2. Window

* Inline `WlrLayershell` chrome (overlay + card, same pattern as `ShutdownLauncher`):
  `width: 620`, `radius: Theme.roundingLauncher`, `Esc` closes.
* No filter field — fixed sections, filter is unnecessary.
* Refreshes `BatteryService` on open so the first paint is current.

## 3. Sections (top → bottom)

### 3.1 Hero

* 40 px state glyph (`stateGlyph` — same tier logic as the bar icon) + state label
  (`"On battery"` / `"Charging"` / `"Plugged in"` / `"No battery"`) + large `28 px`
  percent readout (hidden when plugged — plug glyph carries the state, bar parity).
* Critical wash: hero card at `Theme.bgCritical` when unplugged and `capacity <= 20`
  (`STYLE.md` §6).
* Unplugged sub-line: `"{estimate} remaining"` at `stateColor` (visible only when
  `discharging && timeLeftMinutes >= 0`).
* Charging sub-line: `"Full in {estimate}"` at `Theme.fgMuted` (visible only when
  `charging && timeLeftMinutes >= 0`).

### 3.2 Charge bar

* Full-width `6 px`, `radius: 3`, bg `Theme.border`; fill
  `width: parent.width * capacity/100`, colour `stateColor`, animated
  (`Behavior on width` at `Theme.durationNormal`, `Behavior on color` at
  `Theme.durationFast`).
* Hidden when plugged or when capacity is unknown.

### 3.3 Detail rows

Label left (`Theme.fgMuted`), value right-aligned:

| Row | Value | When |
|---|---|---|
| Charge | `{capacity}%` / `"Full / on AC"` / `"—"` | always |
| Time left unplugged | formatted `timeLeftMinutes` (`"2h 15m"`, `"45m"`, `"—"` when unknown) | `discharging` only |
| Power draw / Charge rate | `{powerNow} W` (1 decimal) | discharging or charging, when `powerNow >= 0` |
| Energy | `{energyNow} / {energyFull} Wh` (1 decimal) | when both known |
| Status | state label | always |

## 4. Service Contract — `BatteryService.qml` (extended)

```qml
// BatteryService.qml — additions over capacity/status polling
property bool discharging: false   // status === "Discharging"
property double energyNow: -1      // µWh from energy_now, -1 when unreadable
property double energyFull: -1     // µWh from energy_full
property double powerNow: -1       // µW from power_now
property int timeLeftMinutes: -1   // live estimate, -1 = unknown
function refresh(): void           // force one poll tick (called on launcher open, key `r`)
```

* **One-shot read:** a single shell invocation emits
  `status|capacity|energy_now|energy_full|power_now` for the first `BAT*` supply;
  `NONE` when no battery exists. No `upower` dependency.
* **Estimate:** discharging with `powerNow > 0` → `energyNow / powerNow * 60`;
  charging towards full → `(energyFull - energyNow) / powerNow * 60`;
  otherwise `-1` (on AC, idle draw `0`, or missing sysfs nodes — unknown, never infinite).
* **Polling:** `Timer { interval: 15000; repeat: true }` — sysfs reads are cheap;
  no DBus/event source exists for this. `refresh()` for on-demand ticks.

## 5. Interaction

* `Esc` closes. `r` forces `BatteryService.refresh()`.
* Display-only: no `Enter` action, no `j/k` cursor. Footer hint: `"r refresh · Esc close"`.
* Replaces any open launcher (shell `IpcHandler` `closeAllExcept("power")`).

## 6. Styling

* `stateColor` shared by glyph, percent, bar fill, and time rows:
  plugged → `Theme.fg`; `capacity <= 20` → `Theme.critical`;
  `<= 30` → `Theme.warning`; charging → `Theme.success`; else `Theme.fg`.
* All glyphs via `Icons.*` (`Icons.battery` for the Control-Center tile);
  all colours via `Theme.*`.

## 7. Empty / Degraded States

* No battery (`available === false`) → hero shows plug glyph at `Theme.fgDim`,
  `"No battery"` + `"No battery detected"`; bar icon hidden; detail rows collapse
  to `Charge: —` + `Status: No battery`.
* Unknown estimate (`timeLeftMinutes === -1`) → `"—"`, never `0m` or infinity.
* Missing `power_now`/`energy_*` nodes → power/energy rows hidden, percent + status
  still render.

## 8. Keybinding (moved perf drawer)

* `SUPER+p` previously toggled the perf drawer (`Bar-performance.md` §2) — it now
  toggles this launcher (`hyprland.lua` → `quickshell ipc call launcher toggle power`).
* The perf drawer moved to `SUPER+SHIFT+p` (`quickshell ipc call perf toggle`);
  `Bar-performance.md`, `Bar.md`, `Key-Launcher.md`, and `Control-Center.md` are
  updated to match.

## 9. Acceptance

* [ ] Unplugged: percent + live `"Xm remaining"` estimate + charge bar with
  `critical`/`warning` colours at the `20`/`30` thresholds.
* [ ] Charging/plugged: correct label/glyph, percent hidden when plugged,
  `"Full in …"` only while charging with known rate.
* [ ] `SUPER+p` toggles; `SUPER+SHIFT+p` toggles perf; bar battery click opens the launcher.
* [ ] No-battery machine: degraded hero, bar icon hidden, no QML errors.
* [ ] Estimate never shows infinite/negative; `r` refreshes; `Esc` closes.
* [ ] Uses `Theme.*` tokens; all glyphs via `Icons.*`.
