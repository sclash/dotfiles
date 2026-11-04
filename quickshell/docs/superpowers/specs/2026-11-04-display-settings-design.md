# Display Manager — Per-Monitor Settings Design

**Date:** 2026-11-04
**Status:** Approved
**Scope:** `quickshell` Display Manager, supporting services, Nix wiring, Hyprland autostart.

## 1. Intent

The Display Manager manages monitor layout today — connect, mirror, position, disconnect — but cannot adjust the properties of a specific output. Add a per-monitor settings view opened with `s` from the selected monitor row.

The settings must be per-display and device-agnostic: each display shows only the controls it reports support for, with no hardcoded model or output lists. Changes are runtime-only. They are not written to `hyprland.lua`, not stored in a profile file, and not reapplied when a display reconnects.

## 2. Goals

- `s` on the selected monitor row opens a settings sub-view for that output.
- Every row is derived from the output's reported capabilities and current values.
- Compositor settings apply immediately through `hl.monitor` and preserve every other active output.
- Brightness is controlled per output: hardware backlight where available, DDC/CI for external displays, software gamma as the final fallback.
- Color temperature is controlled per output through `wl-gammarelay-rs`.
- Keyboard and mouse both work; `Esc` backs out one level at a time.
- Every backend failure leaves a usable degraded state rather than an empty or broken view.

## 3. Non-goals

- Persistence across Hyprland restarts, logout, or monitor reconnect.
- Writing generated monitor rules into `hyprland.lua`.
- Per-display ICC profile management.
- DDC color-temperature presets; color temperature is software-based and continuous.
- Global night-light controls (`hyprsunset` or similar).
- Changing the existing connect/mirror/position/disconnect behavior beyond the rule-builder refactor.

## 4. Constraints

- Hyprland 0.57 with the Lua config parser. Runtime mutation uses `hyprctl eval` with `hl.monitor({...})`; `hyprctl keyword monitor` is rejected by this parser.
- Quickshell 0.3.2 / QtQuick. No native D-Bus QML type in use; D-Bus calls go through `busctl` in `Process` commands, following `DBusMenuClient.qml`.
- One `Process` per subsystem in `services/`. Launchers never poll.
- No hard-coded colours or glyphs outside `theme/Theme.qml` and `theme/Icons.qml`.
- Existing card geometry, `Theme.roundingLauncher`, 640px width, and vim navigation stay intact.
- `quickshell -p` must stay clean.
- New runtime dependencies belong in `nixos/programs/quickshell.nix`; system-level settings in `nixos/configuration.nix`; session autostart in `hypr/hyprland.lua`.
- No files are written at runtime by the settings feature.

## 5. Approaches Considered

**A — minimal touch.** Keep the settings view inside `DisplayManager.qml` and reuse its existing rule builder. Smallest diff, but the launcher would roughly double in size and rule construction would remain embedded in the view.

**B — split the screen.** Extract `DisplaySettingsPanel.qml` and move monitor-rule construction/preservation into `HyprService`, so both the main view and the settings view share one builder. More files and a small refactor of working code, but clear responsibilities and testable pieces.

**Chosen: B.** `DisplayManager.qml` is already ~380 lines, and rule building needs one owner. The main-view acceptance checks (position, mirror, disconnect) guard the refactor.

## 6. Capability Model

`HyprService.mapMonitor()` is extended with:

| Field | Source |
|---|---|
| `description`, `make`, `model`, `serial` | `hyprctl monitors all -j` EDID fields |
| `refreshRate` | `refreshRate` |
| `availableModes` | `availableModes` |
| `dpmsStatus` | `dpmsStatus` |
| `vrrActive` | `vrr` |
| `vrrCapable` | `hardwareDetails.vrrCapable` |
| `hdrCapable` | `hardwareDetails.hdr` |
| `wideColor` | `hardwareDetails.bt2020` |
| `cm` | `colorManagementPreset` |
| `sdrBrightness` | `sdrBrightness`, default `1` |
| `sdrSaturation` | `sdrSaturation`, default `1` |
| `currentFormat` | `currentFormat` |
| `bitDepth` | `10` when `currentFormat` contains `2101010`, otherwise `8` |

`hardwareDetails.chroma` is not used to gate wide gamut; `bt2020` is the capability signal.

`DisplaySettingsService` adds a per-output hardware descriptor:

```text
hardware[output] = {
  brightness: {
    available: bool,
    backend: "backlight" | "ddc" | "gamma",
    value: number,          // percentage 1..100
    min: number, max: number,
    nativeMax: number,      // raw DDC max for writes; 100 for other backends
    device: string,         // backlight device name, or ""
    display: string,        // ddcutil display number, or ""
    path: string            // gamma D-Bus object path, or ""
  },
  temperature: {
    available: bool,
    value: number,          // Kelvin
    min: 1000, max: 10000,
    path: string
  },
  error: string
}
```

## 7. Settings Rows

Rows are generated for the selected output, in this order:

| Row | Kind | Visibility |
|---|---|---|
| Mode / refresh | picker | always; options from `availableModes` |
| Scale | picker | always; 0.5–3.0, current value inserted |
| Rotation | picker | always; Normal / 90° / 180° / 270° |
| Bit depth | picker | `hdrCapable || wideColor || bitDepth === 10` |
| VRR | picker | `vrrCapable`; Off / On / Fullscreen only |
| Color preset | picker | always for auto/sRGB/EDID; wide only if `wideColor`; HDR only if `hdrCapable` |
| HDR brightness | range | current preset is `hdr` or `hdredid` |
| HDR saturation | range | current preset is `hdr` or `hdredid` |
| Brightness | range | any detected backend |
| Color temperature | range | gamma daemon present and preset is not HDR |

Selecting an HDR preset forces `bitdepth=10`. Leaving HDR leaves the chosen bit depth alone. While HDR is active, the bit-depth row is locked to 10-bit.

Scale options: `0.5, 0.75, 1, 1.25, 1.5, 1.75, 2, 2.5, 3`; a non-standard current value is inserted and sorted.

Mode options preserve the raw `availableModes` string for the rule. The display label is formatted as `1920×1080 @ 60 Hz`. If the current mode is absent from the list it is added as the first option.

VRR values: `0` Off, `1` On, `2` Fullscreen only.

Color preset options: `auto`, `srgb`, `dcip3`, `dp3`, `adobe`, `edid`, plus `wide` when `wideColor`, plus `hdr` and `hdredid` when `hdrCapable`.

HDR brightness range: 1.0–2.0, step 0.05. HDR saturation range: 0.8–1.2, step 0.02.

Brightness range: 1–100%, step 5. Color temperature range: 1000–10000K, step 100.

## 8. Interaction

Main view:

- `s` on a monitor nav item opens settings for that output.
- Existing `Enter` (disconnect), `d`, `H/J/K/L`, `r`, and `Esc` behavior is unchanged.

Settings view:

- `j/k` moves between rows.
- `Enter` opens the picker for enumerated rows; no-op for range rows.
- `h/l` adjusts range rows and cycles enumerated rows as a fast path.
- Picker: `j/k` moves, `Enter` applies, `Esc` closes the picker.
- `Esc` stack: picker → settings → main → close.
- `s` also returns from settings to main.
- `r` re-probes hardware and refreshes monitors.
- Mouse: row click selects; value/arrow click changes; picker option click applies.

Footer hints change per view. Styling uses `Theme.*` and `Icons.*` only.

When a size-changing row is applied (mode, scale, rotation), the output is re-placed on its current side of its neighbour using the new logical size. If it has no neighbour, its position is preserved.

Mirrored outputs show compositor rows disabled with the reason `mirrored — extend to configure`; brightness and color temperature remain available.

## 9. Hardware Backends

### Brightness precedence

1. **Kernel backlight (`backlight`).** Discover `/sys/class/backlight/*`, resolve each `device` symlink basename (for example `card1-eDP-1`), and match it to the output name. Prefer `type` `firmware`, then `platform`, then the first match. Read current/max from sysfs; write with `brightnessctl -d <device> set <percent>%`, which uses the systemd-logind API and needs no root/udev changes.
2. **DDC/CI (`ddc`).** Run `ddcutil detect` lazily when settings open, parse `Display N` blocks and their `DRM connector`, strip the `cardN-` prefix, and map to the output. Probe `ddcutil --display N getvcp 10 --terse` for `VCP 10 C <current> <max>`; write with `ddcutil --display N setvcp 10 <value>`. Failures fall through to gamma.
3. **Gamma (`gamma`).** Use the per-output `wl-gammarelay-rs` D-Bus object. Read `Brightness` (`d`, 0–1) and write with `busctl --user set-property rs.wl-gammarelay <path> rs.wl.gammarelay Brightness d <0..1>`.

### Color temperature

Hyprland has no per-monitor Kelvin rule and `hyprsunset` is global. Use the per-output `wl-gammarelay-rs` object under `/outputs/<normalized-name>`: read `Temperature` (`q`, Kelvin), write with `busctl --user set-property ... Temperature q <kelvin>`.

Gamma-based rows (temperature and gamma brightness) are disabled while an HDR preset is active because Hyprland's CM/ICC path may own the gamma ramps. Hardware backlight and DDC brightness remain available.

### Probing and writes

- Probing is lazy: it runs when `s` is pressed and on `r`, never at shell startup or on a timer.
- Results are cached per session and invalidated when `HyprService.monitors` changes.
- DDC detection and gamma reads are asynchronous and serialized per backend. DDC failures are silent; the next backend is used.
- Writes are debounced (120 ms), keep only the latest pending value, and serialize through one `Process` per backend.
- No polling.

## 10. Files and Interfaces

### `services/HyprService.qml`

Adds:

```text
mapMonitor(m) -> extended monitor object
monitorRule(m, overrides) -> string
preserveRules(exceptIdx) -> string
applyMonitor(name, overrides) -> void
applyLua(lua) -> void
logicalSize(m) -> {w, h}
monitorRelation(idx) -> {dir, name} | null
anchorFor(m) -> monitor | null
positionFor(idx, dir, size) -> {x, y} | null
```

`overrides` keys: `mode`, `position`, `scale`, `transform`, `vrr`, `bitdepth`, `cm`, `sdrbrightness`, `sdrsaturation`, `mirror`, `disabled`.

`monitorRule` always sets `output`, `disabled`, `mirror`, `mode`, `position`, and `scale`; it sets the optional fields only when present. `applyMonitor` emits the target rule plus `preserveRules` for every other active non-mirrored output, then refreshes.

### `services/DisplaySettingsService.qml` (new singleton)

```text
property var hardware
property bool probing
property string error
invalidate() -> void
probe(monitors, force) -> void
hardwareFor(name) -> descriptor
setBrightness(name, percent) -> void
setTemperature(name, kelvin) -> void
```

### `components/launchers/DisplaySettingsPanel.qml` (new)

```text
property var monitor
property var hardware
property int selIndex
property bool pickerOpen
property int pickerIndex
property var pickerOptions
signal closeRequested()
signal applyCompositor(string key, var value)
signal setBrightness(real percent)
signal setTemperature(int kelvin)
moveSel(delta) -> void
adjust(delta) -> void
activate() -> void
back() -> void
handleKey(event) -> bool
```

### `components/launchers/DisplayManager.qml`

Adds `view` (`"main"` / `"settings"`), `settingsName`, settings key routing, the `s` binding, and the panel instance. Existing nav, connect, mirror, position, and disconnect behavior stays.

### `services/qmldir`

Registers `singleton DisplaySettingsService 1.0 DisplaySettingsService.qml`.

## 11. Nix and Session Wiring

`nixos/programs/quickshell.nix`:

- Add `brightnessctl`, `ddcutil`, and `wl-gammarelay-rs` to `home.packages`.

`nixos/configuration.nix`:

- `hardware.i2c.enable = true;`
- Add `"i2c"` to the user's `extraGroups`.

`hypr/hyprland.lua`:

- Add `hl.exec_cmd("pkill wl-gammarelay-rs || wl-gammarelay-rs")` to the `hyprland.start` block.

Enabling i2c and the group requires `nixos-rebuild switch` and a re-login so the module and group take effect.

## 12. Degraded States

- `hyprctl` failure: existing `hyprctl failed` line; settings cannot open.
- `availableModes` empty: mode row disabled with `no modes reported`.
- VRR/HDR/wide rows absent when unsupported.
- Mirrored output: compositor rows disabled with `mirrored — extend to configure`.
- HDR active: color temperature and gamma brightness disabled with `unavailable in HDR mode`; hardware brightness remains.
- DDC absent, not permitted, or failing: brightness falls back to gamma; the row shows the `software` backend.
- `brightnessctl` failure: falls back to gamma.
- `wl-gammarelay-rs` not running: color temperature and gamma brightness rows are hidden; a muted line says `wl-gammarelay-rs not running`.
- Monitor removed while settings are open: settings close and the main view returns; no stale index or QML error.

## 13. Acceptance

- [ ] `s` on the selected monitor opens settings; `Esc` backs out picker → settings → main → close.
- [ ] Rows match capabilities: on `eDP-1` no VRR/HDR/wide rows; on capable hardware they appear.
- [ ] Mode/refresh, scale, and rotation apply through `hl.monitor` and update `hyprctl monitors -j`.
- [ ] Layout stays edge-adjacent after a size change; other outputs keep their rules.
- [ ] Bit depth, VRR, and color preset apply; HDR forces 10-bit.
- [ ] Brightness works on the internal panel through the kernel backlight; on an external output it uses DDC when available and gamma otherwise.
- [ ] Color temperature changes only the selected output.
- [ ] Runtime-only: no state file, no `hyprland.lua` mutation, nothing reapplied on reconnect.
- [ ] Backend failures degrade as described in §12.
- [ ] No hardcoded colours/glyphs; `quickshell -p` is clean.

## 14. Known Limits

- Hyprland reports whether VRR is currently active, not the configured rule. The panel keeps a session-local VRR value.
- Bit depth is inferred from `currentFormat`, HDR, and wide-colour support. An EDID-only 10-bit panel without those signals may be under-detected.
- `hardwareDetails.hdr` depends on Hyprland's EDID parsing; some panels may under-report HDR.
- DDC cannot be tested without an external display. The gamma fallback covers that path.
- Gamma changes may be reset by DPMS cycles or a daemon restart.
- Runtime compositor settings reset on Hyprland restart; runtime gamma settings reset on daemon restart.
- A size change keeps the output beside its resolved neighbour only while that anchored rectangle stays collision-free. If it would overlap a farther output (e.g. the middle output of a three-output chain), the output is moved to the collision-free whole-layout slot instead; it may lose adjacency rather than overlap another output.
