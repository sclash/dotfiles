# Power profiles (auto + manual) — Design

- **Date:** 2026-11-07
- **Status:** proposed (awaiting approval)
- **Scope size:** small change
- **Touches:** `quickshell/services/PowerProfileService.qml` (new),
  `quickshell/services/qmldir`, `quickshell/components/launchers/PowerCenter.qml`,
  `quickshell/theme/Icons.qml`, `quickshell/specs/launchers/Power-Center.md`,
  `quickshell/specs/SPECS.md`, `quickshell/specs/STYLE.md`

## Intent (the why)

power-profiles-daemon is enabled (`nixos/configuration.nix:204`), the three profiles
are live (`powerprofilesctl` shows performance/balanced/power-saver), but **nothing in
the shell can switch them** and **PPD does not switch on its own** — a plugged laptop
sits on `balanced` today. The user wants profile control in the shell plus an automatic
default keyed off power source and charge:

- **on AC (plugged)** → performance
- **on battery, capacity > 20%** → balanced
- **on battery, capacity ≤ 20%** → power-saver

with a manual pick that **sticks until "auto" is explicitly re-enabled** (chosen:
option B), and a little **hysteresis** so the 20% boundary doesn't flap.

## Goals

- Read + apply the current profile through Quickshell's native
  `Quickshell.Services.UPower.PowerProfiles` (no `Process`, no `powerprofilesctl`
  polling, no `Timer`).
- Automatic rule (AC / on-battery / low) with hysteresis; **auto is the default**.
- Manual selection holds until the user re-selects **Auto** (option B).
- Surface it in the existing **PowerCenter** card (battery UI) — not a new launcher.
- Keyboard-driven: `j/k` move, `Enter` apply, `1`–`4` direct select, `Esc` close.
- Degraded state when PPD is unreachable or the machine has no performance profile.

## Non-goals

- PPD per-application **holds** (`PowerProfiles.holds`) UI.
- Per-profile tuning (EPP, governor) — PPD owns the hardware knobs.
- A bar indicator for the current profile.
- Persisting a manual choice across shell restarts (auto is the on-start mode).
- Setting profiles from a keybind / IPC (no new keybind; `SUPER+p` already opens the card).

## Anti-goals (a failure even if it "works")

- Any QML error, or idle RSS regression past the `<200 MB` budget.
- Flapping at the 20% boundary (hysteresis is mandatory).
- Fighting PPD: never write a profile PPD does not offer (`hasPerformanceProfile` guard).
- Hard-coded `#hex`/glyphs — everything via `Theme.*` / `Icons.*`.
- Overflow/underflow in the card (STYLE §5.7) — adding a section must not spill.

## Constraints

- No new Nix dependency: `services.power-profiles-daemon.enable = true` is already set
  (`configuration.nix:204`); `powerprofilesctl` is on PATH; no TLP/auto-cpufreq to
  conflict with.
- Quickshell 0.3.2 exposes `PowerProfiles` with `profile` (read/write), the
  `PowerProfile` enum (`PowerSaver`/`Balanced`/`Performance`), `hasPerformanceProfile`,
  `degradationReason` (`None`/`LapDetected`/`HighTemperature`), and `holds`.
- Services are `pragma Singleton` in module `services`; one source of truth per
  subsystem; launchers read services and never poll.
- Specs are normative and updated in the same change.

## Approaches considered

- **A — new `PowerProfileService` singleton + a section in `PowerCenter` (chosen).**
  The auto rule and hysteresis live in one service; the card gains a profile switcher.
  Matches the "logic in services, one source of truth" rule, no new surface, no new key.
- **B — a separate "Performance Center" launcher (new keybind).** Rejected: duplicates
  the power surface (the battery card *is* the power UI, bound to the battery icon and
  `SUPER+p`), needs a new keybind, and buys nothing over a section.
- **C — auto-switch outside the shell (systemd/udev/script + `powerprofilesctl`).**
  Rejected: breaks the "logic lives in QML services, no shell scripts" rule and creates
  a second source of truth next to the shell's own state.

## Decided how (Approach A)

### 1. Service — `services/PowerProfileService.qml` (new singleton)

A `QtObject` wrapping the native `PowerProfiles` singleton; it references `BatteryService`
(same module) for `available` / `plugged` / `charging` / `capacity`. The auto rule itself is
a dependency-free `.pragma library` module, `services/powerProfileRule.js`, unit-tested by
`tests/tst_power_profile_rule.qml` (run with `quickshell/tests/run.sh`).

```qml
pragma Singleton
import QtQuick
import Quickshell.Io
import Quickshell.Services.UPower
import "powerProfileRule.js" as ProfileRule

QtObject {
    id: root

    // PPD reachable — one-shot probe (see "left to the builder").
    property bool _probed: false
    readonly property bool available: _probed
    readonly property bool hasPerformance: PowerProfiles.hasPerformanceProfile
    readonly property int  current: PowerProfiles.profile          // PowerProfile.* enum
    readonly property int  degradation: PowerProfiles.degradationReason
    readonly property bool degraded: degradation !== PerformanceDegradationReason.None

    property bool auto: true                       // auto mode vs manual hold
    property bool _low: false                      // hysteresis latch: dropped to <=20 on battery

    // Input snapshot for the pure rule (services/powerProfileRule.js).
    // `plugged` is false while charging, so onAC = plugged || charging.
    function _inputs() {
        return {
            available: BatteryService.available,
            onAc: BatteryService.plugged || BatteryService.charging,
            capacity: BatteryService.capacity,
            hasPerformance: hasPerformance
        }
    }
    function _toEnum(name) {
        if (name === "performance") return PowerProfile.Performance
        if (name === "power-saver") return PowerProfile.PowerSaver
        return PowerProfile.Balanced
    }
    function _target() { return _toEnum(ProfileRule.target(_inputs(), _low)) }
    readonly property int autoTarget: _target()

    // Manual pick — holds until setAuto() (option B).
    function setProfile(p) { auto = false; PowerProfiles.profile = p }
    // Re-enable auto and apply immediately.
    function setAuto()     { auto = true; _apply() }

    function _apply() {
        _low = ProfileRule.latch(_inputs(), _low)
        if (auto && available) PowerProfiles.profile = _target()
    }

    property Connections _battery: Connections {
        target: BatteryService
        function onCapacityChanged() { root._apply() }
        function onPluggedChanged()  { root._apply() }
        function onChargingChanged() { root._apply() }
    }
    // Quickshell populates PowerProfiles asynchronously (hasPerformanceProfile
    // is false for the first ~0.5s); re-apply when the real value lands, else
    // the initial AC->performance write is silently skipped.
    property Connections _pp: Connections {
        target: PowerProfiles
        function onHasPerformanceProfileChanged() { root._apply() }
    }
    property Process _probe: Process {
        command: ["powerprofilesctl", "list"]
        running: true
        onExited: (code) => { root._probed = (code === 0); root._apply() }
    }
    Component.onCompleted: _apply()
}
```

**Rule semantics (exact):**

| Condition | Auto target |
|---|---|
| no battery present, or on AC (plugged **or** charging) | Performance (Balanced if `!hasPerformance`) |
| on battery, `capacity ≤ 20` | Power-saver (latches `_low = true`) |
| on battery, `_low && capacity >= 0 && capacity < 25` | Power-saver (stays until recovery) |
| on battery, otherwise | Balanced |

- **Hysteresis:** drop to power-saver at `≤ 20`, return to balanced at `≥ 25`; between
  20–25 the current latch decides. Sitting on AC clears the latch, so unplugging at
  `≥ 25` gives balanced and at `≤ 20` gives power-saver.
- **Unknown capacity (`-1`):** never treated as low — the low tests require
  `capacity >= 0`, so an unknown reading falls through to balanced.
- **Auto is the on-start mode.** A manual selection survives until the user re-selects
  Auto; nothing is persisted across a shell/daemon restart.
- Writes are programmatic, so the rule never flips `auto` to false — only `setProfile()`
  does.

### 2. UI — a "Profile" section in `PowerCenter.qml`

Add below the charge bar (above the existing detail rows), card width stays 620:

- Sub-header `PROFILE` (uppercase, `Theme.fgMuted`, `Theme.fontSizeSmall`).
- **Four rows** in a `ColumnLayout`, `height ~34`, STYLE §5.3 row chrome
  (`radius: Theme.roundingItem`, `border` idle, `borderSelected` selected):
  `Auto`, `Performance`, `Balanced`, `Power Saver`.
  Each row: leading `Icons.profile*` glyph + label; right-aligned trailing state.
- **State indicator (one check, never two):**
  - `auto == true` → `Icons.check` (`Theme.success`) on the **Auto** row; that row shows
    a right-aligned `"→ <target>"` (e.g. `→ Performance`) so the driven profile is legible.
  - `auto == false` → `Icons.check` on the row matching `current`.
- **Performance row hidden** when `!hasPerformance` (machine without a performance profile).
- **Degraded note:** when `degraded` and performance is the effective profile, a
  `Theme.warning` sub-line under the section: `"!" + " performance degraded: lap detected"` /
  `"…: high temperature"` (`Icons.warning`).
- **Availability:** when `!available` the whole section hides (no profiles to switch).

**Interaction** (in the existing `Keys.onPressed`): `j`/`Down` and `k`/`Up` move the
selection among rows; `Enter` applies the selected row (`Auto` → `setAuto()`, a profile →
`setProfile(enum)`); `1`–`4` select directly (`1 Auto, 2 Performance, 3 Balanced,
4 Power Saver`); `Esc` closes. Selection is a border ring (STYLE §6), never a tint.
Footer becomes `"j/k select · Enter apply · Esc close"`.

**Overflow guard (STYLE §5.7):** wrap the card content in the `AudioCenter` scroll
pattern (`Flickable` + `ScrollBar.vertical` + clamped `contentY`) and raise the card cap
(e.g. `Math.min(620, …)`) so the taller content can never spill.

### 3. Icons — `theme/Icons.qml`

Four new MDI glyphs (codepoints verified present in the installed JetBrainsMono Nerd Font):

```qml
property string profileAuto:        String.fromCodePoint(0xF0069)  // nf-md-autorenew
property string profilePerformance: String.fromCodePoint(0xF04C5)  // nf-md-speedometer
property string profileBalanced:    String.fromCodePoint(0xF05D1)  // nf-md-scale-balance
property string profilePowerSaver:  String.fromCodePoint(0xF032A)  // nf-md-leaf
```

## Calls I made (check these)

- **Auto is the mode on start**; a manual pick is not persisted across restarts.
- **AC clears the hysteresis latch**; unplug outside 20–25% resolves immediately.
- **A battery-less machine** (desktop) counts as plugged → performance.
- **`!hasPerformance`** hides the Performance row and makes the AC target Balanced.
- **Degradation** is surfaced as a warning sub-line, not a separate row.
- **`1`–`4` direct keys** in addition to `j/k` + `Enter`.
- **One check indicator**, on Auto (auto mode) or the current profile (manual mode).
- **Availability probe** uses one one-shot `powerprofilesctl` process (see below).

## Left to the builder

- **Daemon availability:** Quickshell's `PowerProfiles` exposes no `available` flag.
  Probe once on `Component.onCompleted` with a one-shot `Process` (`["powerprofilesctl",
  "list"]`, exit 0 → `available = true`); re-probe is unnecessary (PPD is Nix-guaranteed).
  If a cleaner native signal is found, prefer it.
- Exact QML wiring for the section's selection index, `Enter`/digit handling, and the
  `Flickable` conversion; keep `Keys`/focus behavior identical to today.
- Confirm `BatteryService` resolves from within the `services` module (same-module type);
  if not, import the module explicitly.
- Verification (below).

## Verification (intent)

- `powerprofilesctl get` matches the row selected in the UI, and matches the auto target
  on plug/unplug.
- Plug/unplug at `>20%` and `≤20%`, and a crossing of 20↔25%, produce the expected
  profile with no flapping.
- Manual pick holds across AC/battery changes until **Auto** is re-selected.
- `qmllint` on changed QML: no parse errors; `quickshell -p`: clean start, no warnings.
- `grep` for hard-coded `#hex`/inline glyphs in `components/` is empty (STYLE §9).
- Degraded paths reasoned through: no PPD, no performance profile, no battery.
