# Power-Center — Refined Spec

> Command: `SUPER+p` · File: `components/launchers/PowerCenter.qml` · Service: `services/BatteryService.qml`

---

## 1. Purpose

Center-screen battery status card. Shows charge percentage and a **live estimate of
time left unplugged** when the machine runs on battery, with state colours that
match the bar battery icon. Also hosts the **power-profile switcher** (Automatic
plus manual picks) backed by `PowerProfileService.qml`; power actions
(suspend/reboot/poweroff) stay in `Shutdown-Launcher.md`.

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
* Body scrolls (`Flickable` + thin `ScrollBar`) so the battery + profile content can
  never overflow the card (`STYLE.md` §5.7); card height caps at 620.

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

### 3.3 Power profile

Visible only when `PowerProfileService.available` (PPD reachable). Uppercase
`"Power profile"` sub-header, then four rows in `j/k` order:

| Row | Meaning |
|---|---|
| **Auto** | Follow the power source (rule below). Right-aligned `→ <target>` shows the profile the rule is driving. |
| **Performance** | Manual — hidden when `!PowerProfileService.hasPerformance`. |
| **Balanced** | Manual. |
| **Power Saver** | Manual. |

* Row chrome per `STYLE.md` §5.3: `radius: Theme.roundingItem`, `Layout.preferredHeight: 34`,
  `border.color: Theme.borderSelected` when selected else `Theme.border`.
* Leading `Icons.profile*` glyph (`Theme.fgMuted`) + label (`Theme.fg`).
* **One** check indicator (`Icons.check`, `Theme.success`): on the **Auto** row while
  auto mode is engaged, otherwise on the row matching `PowerProfileService.current`.
* **Degraded note** below the rows when `PowerProfileService.degraded`:
  `Icons.warning` + `" performance degraded: lap detected"` / `"…: high temperature"`
  in `Theme.warning`.
* Interaction: `j`/`k` (or arrows) move the selection; `Enter` applies the selected row
  (`Auto` → re-enable auto; a profile → manual hold); `1`–`4` select directly.

### 3.4 Detail rows

Label left (`Theme.fgMuted`), value right-aligned:

| Row | Value | When |
|---|---|---|
| Charge | `{capacity}%` / `"Full / on AC"` / `"—"` | always |
| Power draw / Charge rate | `{powerNow} W` (1 decimal) | discharging or charging, when `powerNow >= 0` |
| Energy | `{energyNow} / {energyFull} Wh` (1 decimal) | when both known |
| Health | `{health}%` (0 decimals) | `healthSupported` |
| Model | `model` | when non-empty |
| Status | state label | always |

## 4. Service Contract — `BatteryService.qml`

Backed by Quickshell's native `Quickshell.Services.UPower` — no sysfs parsing,
no `Process`, no `Timer`, no polling. State is push-based over DBus.

```qml
// BatteryService.qml — properties bound over UPower
property bool available: false      // displayDevice.ready && isPresent
property bool charging: false       // state === Charging
property bool discharging: false    // state === Discharging || Empty
property bool plugged: false        // !UPower.onBattery && !charging
property int capacity: -1           // round(displayDevice.percentage * 100), 0..100
property double energyNow: -1       // µWh = displayDevice.energy (Wh) × 1e6
property double energyFull: -1      // µWh = displayDevice.energyCapacity (Wh) × 1e6
property double powerNow: -1        // µW = displayDevice.changeRate (W) × 1e6
property int timeLeftMinutes: -1    // timeToEmpty/timeToFull ÷ 60; -1 = unknown
property bool healthSupported: false
property double health: -1          // battery device healthPercentage (0..100)
property string model: ""           // battery device model
```

* **Source:** `UPower.displayDevice` (the aggregate over all batteries — handles
  multi-battery machines and any sysfs naming) for state / percentage / energy /
  rate / time; the `UPower.devices` entry with `isLaptopBattery` (else the first
  `Battery`) for `health` / `model`.
* **Units:** UPower reports Wh / W / seconds; the public contract stays µWh / µW /
  minutes. `capacity` scales `percentage` by 100 (Quickshell exposes it as a
  `0..1` fraction, unlike `healthPercentage`).
* **Estimate:** `discharging` → `timeToEmpty`; `charging` → `timeToFull`;
  a value `≤ 0` or NaN → `-1` (unknown, never infinite).
* **No `refresh()`:** UPower pushes updates, so there is no manual poll or key.

### Service contract — `PowerProfileService.qml`

Backed by Quickshell's native `Quickshell.Services.UPower.PowerProfiles`; no
`Process` polling (one one-shot `powerprofilesctl` probe for availability). It
reads `BatteryService` (`available`, `plugged`, `charging`, `capacity`) and is the
only writer of `PowerProfiles.profile`.

```qml
property bool available            // PPD reachable (one-shot powerprofilesctl probe)
property bool hasPerformance       // PowerProfiles.hasPerformanceProfile
property int  current              // PowerProfiles.profile (PowerProfile.* enum)
property bool degraded             // degradationReason !== None
property bool auto                 // true = follow the rule; false = manual hold
property int  autoTarget           // the PowerProfile.* the rule wants now
function setProfile(p: int): void  // manual pick; sets auto = false
function setAuto(): void           // re-enable auto and apply
```

Auto rule (AC = `plugged || charging`; `capacity` is `-1` when unknown):

| Condition | Target |
|---|---|
| no battery present, or on AC | Performance (Balanced if `!hasPerformance`) |
| on battery, `capacity ≤ 20` | Power-saver (latches low) |
| on battery, latched & `0 ≤ capacity < 25` | Power-saver |
| on battery, otherwise | Balanced |

Hysteresis: drop at `≤ 20`, recover at `≥ 25`; AC clears the latch. Unknown
capacity (`-1`) is never treated as low. The rule is a dependency-free module,
`services/powerProfileRule.js`, unit-tested by `tests/tst_power_profile_rule.qml`.
`auto` is the default at startup; a manual pick holds until the **Auto** row is
re-selected.

## 5. Interaction

* `Esc` closes. No refresh key — UPower is live.
* Battery rows are display-only. The **profile section** (visible when
  `PowerProfileService.available`) is interactive: `j/k` or arrows move the selection,
  `Enter` applies it, `1`–`4` select directly. Footer hint:
  `"j/k select · Enter apply · Esc close"`.
* Replaces any open launcher (shell `IpcHandler` `closeAllExcept("power")`).

## 6. Styling

* `stateColor` shared by glyph, percent, bar fill, and time rows:
  plugged → `Theme.fg`; `capacity <= 20` → `Theme.critical`;
  `<= 30` → `Theme.warning`; charging → `Theme.success`; else `Theme.fg`.
* All glyphs via `Icons.*` (`Icons.battery` for the Control-Center tile);
  all colours via `Theme.*`.

## 7. Empty / Degraded States

* No present battery (`available === false`) → hero shows plug glyph at `Theme.fgDim`,
  `"No battery"` + `"No battery detected"`; bar icon hidden; detail rows collapse
  to `Charge: —` + `Status: No battery`.
* Unknown estimate (`timeLeftMinutes === -1`) → `"—"`, never `0m` or infinity.
* `healthSupported === false` → Health row hidden; empty `model` → Model row hidden.
  A machine without `upowerd` yields `available === false` (degraded, not an error).

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
* [ ] Estimate never shows infinite/negative; `Esc` closes.
* [ ] Uses `Theme.*` tokens; all glyphs via `Icons.*`.
* [ ] On AC (including while charging): Auto drives Performance; unplug → Balanced;
  `≤ 20%` → Power Saver; hovering the 20–25% band does not flap.
* [ ] A manual pick holds across plug/unplug until the Auto row is re-selected.
* [ ] Degraded note shows on lap-detected / high-temperature; profile section hidden
  when PPD is unreachable; Performance row hidden when unsupported.
