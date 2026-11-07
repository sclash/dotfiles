# UPower-backed BatteryService — Design

- **Date:** 2026-11-07
- **Status:** proposed (awaiting approval)
- **Scope size:** small change
- **Touches:** `quickshell/services/BatteryService.qml`, `quickshell/components/launchers/PowerCenter.qml`, `quickshell/specs/launchers/Power-Center.md`, `quickshell/specs/SPECS.md`

## Intent (the why)

The current `BatteryService` polls sysfs with a `Process` (a shell + ~11 `cat`s) on a
15 s `Timer`. It costs ~74 ms wall / ~12 process spawns per tick, wakes the system
~0.9×/s, only understands the energy- *or* charge-based sysfs scheme (patched in
`a907651`), and only discovers batteries named `BAT*`.

Quickshell 0.3.2 ships a native `Quickshell.Services.UPower` module. `upowerd` is
**already running** here (`services.upower.enable = true`) and `upower` is already
installed, so switching is a **zero-dependency, zero-new-daemon** change that becomes
event-driven, discovers any battery regardless of sysfs naming, aggregates multiple
batteries, and unlocks battery **health %** and **model** for the UI.

## Goals

- `BatteryService` reads live from UPower; no `Process`, no `Timer`, no subprocess.
- The existing public contract is preserved so `BatteryIcon` needs no changes.
- New `health` / `healthSupported` / `model` surfaced as rows in `PowerCenter`.
- Detection independent of sysfs naming; multi-battery handled via the aggregate device.

## Non-goals

- Cycle count, vendor/serial (not exposed by Quickshell's `UPowerDevice`).
- Power-profile switching (`PowerProfiles`) — out of scope.
- Supporting machines without `upowerd` (NixOS config enables it; not our concern).

## Anti-goals (a failure even if it "works")

- Any QML error, or idle RSS regression past the `<200 MB` budget.
- Losing the no-battery degraded state.
- Forcing unit changes into `PowerCenter` / `BatteryIcon`.

## Constraints

- No new Nix dependency (`upower` already present at `programs/quickshell.nix:31`;
  daemon enabled at `configuration.nix:201`).
- All colours/glyphs via `Theme.*` / `Icons.*`.
- Normative specs updated in the same change.

## Approaches considered

- **A — adapter over UPower, contract preserved (chosen):** a thin translation layer
  keeps the documented µWh/µW/minutes contract; only `PowerCenter` gains rows.
  Least churn, detection becomes universal, poll cost goes to zero.
- **B — re-export the UPower shape (Wh/W/sec), rewrite consumers:** less service code,
  but churns both consumers, breaks the documented contract, no visible gain. Rejected.
- **C — keep sysfs, add UPower for health/model only:** two sources of truth, two
  wake-up paths, keeps the `^BAT` flaw. Rejected.

## Decided how (Approach A)

`BatteryService.qml` becomes a `QtObject` whose readable properties are derived from
`UPower.displayDevice` (aggregate) plus a laptop-battery lookup over `UPower.devices`:

| Public property | Source | Notes |
|---|---|---|
| `available` | `displayDevice.isPresent` (and `ready`) | false → degraded |
| `capacity` | `Math.round(displayDevice.percentage)` | int 0–100 |
| `energyNow` | `displayDevice.energy × 1e6` | Wh → µWh |
| `energyFull` | `displayDevice.energyCapacity × 1e6` | Wh → µWh |
| `powerNow` | `displayDevice.changeRate × 1e6` | W → µW |
| `charging` | `state === UPowerDeviceState.Charging` | |
| `discharging` | `state === Discharging \|\| state === Empty` | |
| `plugged` | `!UPower.onBattery && !charging` | matches old "Full / Not charging" |
| `timeLeftMinutes` | discharging → `round(timeToEmpty/60)`; charging → `round(timeToFull/60)`; else `-1` | 0/NaN → `-1` |
| `health` (new) | `battery.healthPercentage` | `-1` when unsupported |
| `healthSupported` (new) | `battery.healthSupported` | |
| `model` (new) | `battery.model` | `""` when unknown |

`refresh()` is **deleted** — UPower is push-based, so a manual refresh is meaningless.
Its call sites in `PowerCenter` (on-open and the `r` key) are removed too.

`battery` = first `UPower.devices` entry with `isLaptopBattery`, else first of type
`Battery`. The `capacity` thresholds, colours, glyphs and layout in `PowerCenter` are
unchanged; two rows are added:

- **Health** — visible when `available && healthSupported` → `health + "%"`.
- **Model** — visible when `available && model !== ""` → `model`.

`PowerCenter` drops its two `BatteryService.refresh()` calls and the `r` key handler;
the footer hint becomes `"Esc close"` (UPower is live, so manual refresh is meaningless).

`BatteryIcon.qml` is unchanged. Specs updated:

- `Power-Center.md` §4 (contract) — replace the sysfs contract/`energy_now` comments and
  the **"No `upower` dependency."** line (77) with the UPower-backed one; add
  `health`/`healthSupported`/`model`; drop the `refresh()` entry and the polling bullet (88).
- `Power-Center.md` §5 (interaction) — remove `r` refresh; footer `"Esc close"`.
- `Power-Center.md` §7 (degraded) — reword the missing-node case in UPower terms.
- `SPECS.md:43` — battery row `sysfs `BAT*`, no UPower dep` → UPower-backed.
- `SPECS.md:118` — `BatteryService.qml` file-layout comment sysfs → UPower.
- `SPECS.md:66` — dependency-table `upower` entry: no longer "optional / if kept".

## Calls I made (check these)

- `plugged` excludes the actively-charging case so the charging glyph/colour still win.
- `refresh()` and its UI (`r` key + footer hint) are deleted outright, not stubbed.
- `Empty` counted as discharging.
- Health/model read from the per-battery device (not the aggregate), since `DisplayDevice` reports them as N/A.

## Left to the builder

- Exact QML wiring for iterating `UPower.devices` and holding the resolved `battery`.
- Guarding `timeToEmpty`/`timeToFull` when `0`/`NaN`.
- Verification method (qml lint + `quickshell -p` clean + cross-check against `upower -i`).

## Verification (intent)

- `qmllint` on changed QML: no parse/syntax errors.
- `quickshell -p`: clean start, no QML warnings.
- Derived values match `upower -i /org/freedesktop/UPower/devices/DisplayDevice` and the
  `battery_BAT0` device (percentage, energy, rate, time, health, model).
- Degraded path reasoned through by code inspection (no-battery machine).
