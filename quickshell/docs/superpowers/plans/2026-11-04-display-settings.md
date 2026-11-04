# Display Manager Per-Monitor Settings Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a runtime-only, capability-driven per-monitor settings view to the Display Manager, opened with `s`, covering Hyprland monitor settings, brightness, and color temperature.

**Architecture:** Extend `HyprService` with capability fields and one monitor-rule builder/mutator, add a `DisplaySettingsService` singleton for brightness/color-temperature backends, and extract the settings UI into `DisplaySettingsPanel.qml`. `DisplayManager.qml` keeps the existing monitor list and gains a `main`/`settings` view state.

**Tech Stack:** QML / Quickshell 0.3.2, Hyprland 0.57 (`hyprctl eval` + `hl.monitor`), `brightnessctl`, `ddcutil`, `wl-gammarelay-rs`, `busctl`.

**Spec:** `quickshell/docs/superpowers/specs/2026-11-04-display-settings-design.md`

## Global Constraints

- Repo root is the worktree root (for example `/home/asergi/dotfiles` or `/home/asergi/dotfiles/.worktrees/display-settings`); paths below are relative to it. QML root is `quickshell/`.
- The live `~/.config/quickshell` symlink points at the main checkout. In a worktree, verify with `quickshell -p "$PWD/quickshell"`; do not rely on the live symlink until the branch is merged.
- Runtime-only: no state file, no `hyprland.lua` mutation, nothing reapplied on reconnect.
- No hard-coded colours or glyphs outside `theme/Theme.qml` and `theme/Icons.qml`; use `Theme.*` / `Icons.*`.
- One `Process` per subsystem in `services/`; launchers never poll.
- All compositor mutations use `hyprctl eval` with `hl.monitor({...})` and preserve every other active non-mirrored output.
- Card stays 640px wide with `Theme.roundingLauncher`; vim keys and the `Esc` stack are required.
- Quickshell 0.3.2: no native D-Bus QML type; use `busctl` through `Process`.
- New runtime deps go in `nixos/programs/quickshell.nix`; system settings in `nixos/configuration.nix`; autostart in `hypr/hyprland.lua`.
- `quickshell -p` must stay clean; no new warnings in changed files.
- Verification uses the real session and `hyprctl output create headless` for a second monitor.

## Review Focus

- DDC unavailable, unpermitted, or failing: the brightness row must still appear with the gamma backend, not disappear or hang.
- HDR preset active: color temperature and gamma brightness must be disabled with a reason; hardware backlight/DDC brightness must stay usable.
- Mode, scale, or rotation change: the output must stay edge-adjacent to its neighbour with the new logical size, and other outputs must keep their rules.
- Monitor removed or mirrored while settings are open: the panel must close or disable compositor rows, never index a missing/changed monitor.
- Whole-branch hygiene: `quickshell -p` clean, no hard-coded `#hex`/glyphs outside the theme files, no runtime file writes.

---

### Task 1: Nix packages, i2c access, and gamma daemon

**Files:**
- Modify: `nixos/programs/quickshell.nix:23-40` (`home.packages`)
- Modify: `nixos/configuration.nix:217-232` (user groups; add system-level i2c near the existing hardware settings)
- Modify: `hypr/hyprland.lua:38-55` (`hyprland.start` block)

**Interfaces:**
- Produces: `brightnessctl`, `ddcutil`, and `wl-gammarelay-rs` on the session PATH; `/dev/i2c-*` accessible to the seated user; `rs.wl.gammarelay` on the user bus after login.

- [ ] **Step 1: Add the packages**

In `nixos/programs/quickshell.nix`, add to `home.packages`:

```nix
    brightnessctl      # internal panel backlight via logind
    ddcutil            # external monitor brightness (VCP 0x10)
    wl-gammarelay-rs   # per-output gamma brightness and color temperature
```

- [ ] **Step 2: Enable i2c and the i2c group**

In `nixos/configuration.nix`, add near the hardware settings:

```nix
  hardware.i2c.enable = true;
```

Add `"i2c"` to the user's `extraGroups` list. `hardware.i2c.enable` creates the group and grants seated users access; group membership keeps it working when seat detection is unavailable.

- [ ] **Step 3: Autostart the gamma daemon**

In the `hl.on("hyprland.start", ...)` block in `hypr/hyprland.lua`, add:

```lua
		hl.exec_cmd("pkill wl-gammarelay-rs || wl-gammarelay-rs")
```

- [ ] **Step 4: Check the NixOS configuration builds**

Run from the repo root:

```bash
nixos-rebuild build --flake ./nixos#nixos-os
```

Expected: build succeeds. If the executor cannot run Nix builds, stop and hand this step to the user.

- [ ] **Step 5: Apply and re-login**

Run:

```bash
sudo nixos-rebuild switch --flake "$PWD/nixos#nixos-os"
```

Then log out and back in (or reboot) so the `i2c-dev` module and `i2c` group membership take effect.

- [ ] **Step 6: Verify the session has the tools and bus name**

Run:

```bash
command -v brightnessctl ddcutil wl-gammarelay-rs
ls /dev/i2c-* 2>/dev/null
busctl --user status rs.wl.gammarelay
```

Expected: all three paths resolve; `/dev/i2c-*` lists at least one bus when an external display is connected; `busctl` reports the gamma daemon's bus name. If the daemon is not running, start it once for the check: `wl-gammarelay-rs &`.

- [ ] **Step 7: Commit**

```bash
git add nixos/programs/quickshell.nix nixos/configuration.nix hypr/hyprland.lua
git commit -m "chore(display): add brightness, ddc and gamma dependencies"
```

---

### Task 2: HyprService monitor capabilities

**Files:**
- Modify: `quickshell/services/HyprService.qml:68-83` (`mapMonitor`)

**Interfaces:**
- Consumes: `hyprctl monitors -j` / `hyprctl monitors all -j`.
- Produces: every mapped monitor also carries `description`, `make`, `model`, `serial`, `refreshRate`, `availableModes`, `dpmsStatus`, `vrrActive`, `vrrCapable`, `hdrCapable`, `wideColor`, `cm`, `sdrBrightness`, `sdrSaturation`, `currentFormat`, and `bitDepth`.

- [ ] **Step 1: Record the fields Hyprland reports**

Run:

```bash
hyprctl monitors all -j | jq '.[0] | {description, availableModes, hardwareDetails, colorManagementPreset, sdrBrightness, sdrSaturation, currentFormat, vrr, dpmsStatus}'
```

Expected: the fields exist, with `hardwareDetails` containing `vrrCapable`, `hdr`, `bt2020`, and `chroma`.

- [ ] **Step 2: Extend `mapMonitor`**

Add the fields from the Interfaces block. Gate capabilities exactly as follows:

```text
vrrCapable  = !!m.hardwareDetails.vrrCapable
hdrCapable  = !!m.hardwareDetails.hdr
wideColor   = !!m.hardwareDetails.bt2020
bitDepth    = /2101010/.test(m.currentFormat || "") ? 10 : 8
sdrBrightness = m.sdrBrightness !== undefined ? m.sdrBrightness : 1
sdrSaturation = m.sdrSaturation !== undefined ? m.sdrSaturation : 1
cm = m.colorManagementPreset || "srgb"
```

Do not use `hardwareDetails.chroma` for wide-gamut gating.

- [ ] **Step 3: Verify Quickshell still loads**

Run:

```bash
quickshell -p "$PWD/quickshell" 2>&1 | grep -iE "error|warning|unable" | head
```

Expected: no `HyprService.qml` or monitor-mapping errors.

- [ ] **Step 4: Verify the existing monitor list is unchanged**

Open the Display Manager:

```bash
quickshell ipc call launcher toggle display
```

Expected: current/available monitor rows show the same name, mode, scale, position, and focus badge as before.

- [ ] **Step 5: Commit**

```bash
git add quickshell/services/HyprService.qml
git commit -m "feat(display): expose per-monitor capabilities in HyprService"
```

---

### Task 3: HyprService rule builder and mutation refactor

**Files:**
- Modify: `quickshell/services/HyprService.qml` (add rule helpers after `mapMonitor`)
- Modify: `quickshell/components/launchers/DisplayManager.qml:244-377` (replace local rule/geometry helpers with service calls)

**Interfaces:**
- Consumes: extended monitor objects from Task 2.
- Produces:
  - `HyprService.monitorRule(m, overrides) -> string`
  - `HyprService.preserveRules(exceptIdx) -> string`
  - `HyprService.applyMonitor(name, overrides) -> void`
  - `HyprService.applyLua(lua) -> void`
  - `HyprService.logicalSize(m) -> {w, h}`
  - `HyprService.monitorRelation(idx) -> {dir, name} | null`
  - `HyprService.anchorFor(m) -> monitor | null`
  - `HyprService.positionFor(idx, dir, size) -> {x, y} | null`
  - `overrides` accepts `mode`, `position`, `scale`, `transform`, `vrr`, `bitdepth`, `cm`, `sdrbrightness`, `sdrsaturation`, `mirror`, `disabled`.

- [ ] **Step 1: Add the eval process to HyprService**

```qml
property Process evalProc: Process {
    stdout: StdioCollector { onStreamFinished: root.refreshMonitors() }
}
```

- [ ] **Step 2: Implement `monitorRule` and `preserveRules`**

For an enabled output, `monitorRule` always sets `output`, `disabled=false`, `mirror`, `mode`, `position`, and `scale`. It sets `transform`, `vrr`, `bitdepth`, `cm`, `sdrbrightness`, and `sdrsaturation` only when the override/current value is present. `mirror` is the mirror target's output name, or `""`. For `overrides.disabled === true`, emit only `{output, disabled=true}` so disconnect stays minimal. `preserveRules` emits a full rule for every other active non-mirrored output.

- [ ] **Step 3: Implement `applyMonitor` and `applyLua`**

`applyMonitor(name, overrides)` finds the monitor, builds the target rule plus preserve rules, runs `hyprctl eval`, and refreshes monitors when the process finishes. `applyLua(lua)` is the raw path for connect cases where the output is not yet in `monitors`; `connectProc` builds `monitorRule({name, mode, position, scale, mirror}, {}) + preserveRules(-1)` and calls `applyLua`.

- [ ] **Step 4: Move geometry helpers from DisplayManager to HyprService**

Move `logicalSize`, `monitorRelation`, `anchorFor`, `mirrorName`, and the position math without changing their behavior. Add `positionFor(idx, dir, size)` that returns the collision-free position for a hypothetical size.

- [ ] **Step 5: Update DisplayManager to call the service**

`placeMonitor`, `toggleMirror`, `disconnectIndex`, and `connectProc` must call `HyprService.applyMonitor` / `applyLua`; `placeFocused` and the `[L][R][T][B]` click handlers call the service helpers. Remove the duplicate `evalProc`, `runLua`, `luaQuote`, `luaRule`, `preserveRules`, `mirrorName`, `logicalSize`, `anchorFor`, `monitorRelation`, and local position math from `DisplayManager.qml`. Keep thin wrapper functions only where a QML binding already references them.

- [ ] **Step 6: Verify the existing acceptance behavior**

Run `quickshell -p "$PWD/quickshell" 2>&1 | grep -iE "error|warning|unable" | head` and expect no errors.

Create a second output:

```bash
hyprctl output create headless
hyprctl monitors -j | jq '.[].name'
```

Expected: a new `HEADLESS-*` output appears in Available. In the Display Manager: Extend it, place it L/R/T/B, toggle Duplicate/Extend, disconnect it, then remove it (use the actual name from `hyprctl monitors -j`):

```bash
hyprctl output remove HEADLESS-1
```

Expected: same behavior as before the refactor; no output shuffle or overlap.

- [ ] **Step 7: Commit**

```bash
git add quickshell/services/HyprService.qml quickshell/components/launchers/DisplayManager.qml
git commit -m "refactor(display): centralize monitor rule building in HyprService"
```

---

### Task 4: DisplaySettingsService, settings shell, and hardware rows

**Files:**
- Create: `quickshell/services/DisplaySettingsService.qml`
- Create: `quickshell/components/launchers/DisplaySettingsPanel.qml`
- Modify: `quickshell/services/qmldir`
- Modify: `quickshell/components/launchers/DisplayManager.qml`

**Interfaces:**
- Consumes: `HyprService.monitors`, `busctl`, `brightnessctl`, `ddcutil`.
- Produces:
  - `DisplaySettingsService.hardware`, `.probing`, `.error`
  - `DisplaySettingsService.invalidate()`, `.probe(monitors, force)`, `.hardwareFor(name)`
  - `DisplaySettingsService.setBrightness(name, percent)`, `.setTemperature(name, kelvin)`
  - `DisplaySettingsPanel.monitor`, `.hardware`, `.selIndex`, `.pickerOpen`, `.pickerIndex`, `.pickerOptions`
  - Signals: `closeRequested()`, `setBrightness(real percent)`, `setTemperature(int kelvin)`
  - Methods: `moveSel(delta)`, `adjust(delta)`, `activate()`, `back()`, `handleKey(event)`
  - `DisplayManager.view` (`"main"` / `"settings"`) and `settingsName`

- [ ] **Step 1: Register the singleton**

Add to `quickshell/services/qmldir`:

```text
singleton DisplaySettingsService 1.0 DisplaySettingsService.qml
```

- [ ] **Step 2: Implement the service cache and probe API**

`hardwareFor(name)` returns the cached descriptor or an empty descriptor with `available: false`. `invalidate()` clears the cache. `probe(monitors, force)` is idempotent and sets `probing` while work is in flight.

- [ ] **Step 3: Implement the backlight probe**

Run a single `sh -c` process that, for each `/sys/class/backlight/*`, prints `device|connector|current|max|type`; resolve the connector from the `device` symlink basename. Match it to an output by the `-<output>` suffix. Prefer `firmware`, then `platform`, then the first match. Convert `current/max` to a percent for the descriptor (`value = Math.round(current / max * 100)`, `min = 1`, `max = 100`, `nativeMax = 100`).

- [ ] **Step 4: Implement the gamma probe**

Run `busctl --user tree rs.wl-gammarelay`, parse `/outputs/<name>` paths, and map each leaf to an output by comparing it to `outputName.replace(/[^A-Za-z0-9]/g, "_")` (for example `eDP-1` → `eDP_1`). For each path, read `Temperature` and `Brightness` with `busctl --user get-property`. Convert the `Brightness` double to percent (`value = Math.round(d * 100)`, `min = 1`, `max = 100`, `nativeMax = 100`). If the bus name is absent, mark gamma unavailable and set no error.

- [ ] **Step 5: Implement the DDC probe**

Run `ddcutil detect` asynchronously. Parse `Display N` blocks and their `DRM connector`; strip the `cardN-` prefix to get the output name. For each match, run `ddcutil --display N getvcp 10 --terse` and parse `VCP 10 C <current> <max>`. Store `value = Math.round(current / max * 100)`, `min = 1`, `max = 100`, and `nativeMax = max`. A missing `ddcutil`, no i2c devices, or an `ERR` response falls through to gamma. Never block the UI thread.

- [ ] **Step 6: Implement deduplicated writes**

Use one `Process` per backend plus a `busy` flag and a pending-value map. `setBrightness`/`setTemperature` clamp the value, update the cached descriptor optimistically, and debounce for 120 ms; only the latest pending value is written. Writes:

```text
backlight: brightnessctl -d <device> set <percent>%
ddc:       ddcutil --display <display> setvcp 10 <round(percent / 100 * nativeMax)>
gamma:     busctl --user set-property rs.wl-gammarelay <path> rs.wl.gammarelay Brightness d <0..1>
temperature: busctl --user set-property rs.wl-gammarelay <path> rs.wl.gammarelay Temperature q <kelvin>
```

For backlight, `percent` maps directly because sysfs current/max are already normalized to percent by `brightnessctl`. For DDC, `nativeMax` is the monitor's raw VCP maximum.

- [ ] **Step 7: Build the panel shell with hardware rows**

`DisplaySettingsPanel.qml` renders a header (`<name> · <description>` and `Settings`), a scrollable row list, and a footer. For this task the rows are only **Brightness** (range 1–100, step 5) and **Color temperature** (range 1000–10000K, step 100). Hide a row when its descriptor is unavailable. Show the brightness backend (`backlight`, `ddc`, `software`) as a muted suffix.

- [ ] **Step 8: Wire `s` and the view state**

In `DisplayManager.qml`, add `view` and `settingsName`, plus `readonly property var settingsHardware: DisplaySettingsService.hardware[settingsName] || ({})`, and pass it to the panel. Reset `view` and `settingsName` in `onIsOpenChanged` when the launcher opens. `s` on a monitor nav item sets `settingsName`, `view = "settings"`, calls `DisplaySettingsService.probe(monitors)`, and focuses the panel. `Esc` in settings returns to main (the picker stack is added in Task 5). Route `j/k/h/l/Enter/Esc` through `DisplaySettingsPanel.handleKey` while `view === "settings"`; the parent handles `r` by calling `probe(monitors, true)` and `refresh()`. Extend `onMonitorsChanged` so it invalidates `DisplaySettingsService` only when the sorted output-name set changes; compositor value refreshes must not trigger a DDC re-scan.

- [ ] **Step 9: Verify the hardware path**

Run `quickshell -p "$PWD/quickshell" 2>&1 | grep -iE "error|warning|unable" | head` and expect no errors. Open the Display Manager, select `eDP-1`, press `s`.

- Brightness row: backend `backlight`; `h/l` changes the value; run `cat /sys/class/backlight/<matched-device>/brightness` (on this laptop `intel_backlight`) and confirm it changed.
- Color temperature row: change the value; run `busctl --user get-property rs.wl-gammarelay /outputs/eDP_1 rs.wl.gammarelay Temperature` and confirm it changed.
- Stop the daemon with `pkill wl-gammarelay-rs`, reopen settings, and confirm the temperature row is hidden and the muted hint appears. Restart the daemon and press `r`.
- With no external display, confirm the failed DDC probe does not block or error; brightness still uses the backlight.

- [ ] **Step 10: Commit**

```bash
git add quickshell/services/DisplaySettingsService.qml quickshell/services/qmldir quickshell/components/launchers/DisplaySettingsPanel.qml quickshell/components/launchers/DisplayManager.qml
git commit -m "feat(display): add settings view with brightness and color temperature"
```

---

### Task 5: Compositor settings rows, picker, and layout preservation

**Files:**
- Modify: `quickshell/components/launchers/DisplaySettingsPanel.qml`
- Modify: `quickshell/components/launchers/DisplayManager.qml`

**Interfaces:**
- Consumes: Task 2 capabilities and Task 3 `HyprService.monitorRule` / `applyMonitor` / `positionFor`.
- Produces: `DisplaySettingsPanel.applyCompositor(string key, var value)`; rows for mode, scale, rotation, bit depth, VRR, color preset, HDR brightness, HDR saturation. `DisplayManager` keeps `property var vrrOverrides: ({})` keyed by output name and passes `DisplaySettingsPanel.vrrOverride` (`-1` when unknown, otherwise `0|1|2`).

- [ ] **Step 1: Add the compositor row definitions**

Add rows before brightness/temperature in the order from the spec §7. Gate bit depth on `hdrCapable || wideColor || bitDepth === 10`, VRR on `vrrCapable`, wide/HDR presets on `wideColor`/`hdrCapable`, and HDR brightness/saturation on `cm === "hdr" || cm === "hdredid"`. The VRR row value is `vrrOverride >= 0 ? vrrOverride : (monitor.vrrActive ? 1 : 0)`.

- [ ] **Step 2: Add the picker**

Add a modal list inside the panel: `pickerOpen`, `pickerIndex`, `pickerOptions`. `Enter` opens it for enumerated rows; `j/k` moves; `Enter` applies and closes; `Esc` closes only the picker. `h/l` cycles enumerated values directly as a fast path.

- [ ] **Step 3: Apply enumerated compositor rows**

`DisplayManager` handles `applyCompositor`:

```text
mode      -> parse the raw availableModes string; apply {mode}
scale     -> apply {scale}
rotation  -> apply {transform}
bitdepth  -> apply {bitdepth}
vrr       -> apply {vrr}; store the value in `vrrOverrides[settingsName]`
cm        -> hdr/hdredid force {cm, bitdepth: 10}; other presets apply {cm}
sdrbrightness -> apply {sdrbrightness}
sdrsaturation -> apply {sdrsaturation}
```

Use `HyprService.applyMonitor(settingsName, overrides)`.

- [ ] **Step 4: Re-place after size changes**

For mode, scale, and rotation, compute the new logical size, resolve the monitor's current relation, and call `HyprService.positionFor(idx, dir, newSize)`. If a position is returned, include it in the same rule; otherwise preserve the current position. If the monitor has no neighbour, preserve the position.

- [ ] **Step 5: Lock bit depth while HDR is active**

When `cm` is `hdr` or `hdredid`, render bit depth as `10-bit` and disable changing it. When leaving HDR, leave the current bit depth alone.

- [ ] **Step 6: Verify on `eDP-1`**

Open settings and check:

- Mode picker lists the modes from `availableModes`; applying one changes `hyprctl monitors -j` width/height/refresh.
- Scale applies and the value persists in the list.
- Rotation applies; `hyprctl monitors -j` shows the new transform.
- VRR, HDR, and wide rows are absent on this panel.
- Color preset options exclude `wide`, `hdr`, and `hdredid`.

- [ ] **Step 7: Verify layout preservation with a headless output**

```bash
hyprctl output create headless
```

Extend the headless output, place it right of `eDP-1`, then change its scale and rotation from settings. Use the actual `HEADLESS-*` name reported by `hyprctl monitors -j`. Run:

```bash
hyprctl monitors -j | jq '.[] | {name, x, y, width, height, scale, transform}'
```

Expected: the headless output stays edge-adjacent to `eDP-1`; no overlap; `eDP-1` keeps its rule. Remove it with `hyprctl output remove HEADLESS-1`.

- [ ] **Step 8: Commit**

```bash
git add quickshell/components/launchers/DisplaySettingsPanel.qml quickshell/components/launchers/DisplayManager.qml
git commit -m "feat(display): add compositor settings and layout preservation"
```

---

### Task 6: Degraded states, hotplug, and polish

**Files:**
- Modify: `quickshell/components/launchers/DisplaySettingsPanel.qml`
- Modify: `quickshell/components/launchers/DisplayManager.qml`

**Interfaces:**
- Consumes: everything from Tasks 4-5.
- Produces: final key/mouse behavior, disabled-row reasons, hotplug handling, and error hints.

- [ ] **Step 1: Disable compositor rows for mirrored outputs**

When the selected output is mirrored (`mirrorName(m) !== ""`), render mode/scale/rotation/bit depth/VRR/color rows disabled with the reason `mirrored — extend to configure`. Keep brightness and temperature enabled.

- [ ] **Step 2: Disable gamma rows under HDR**

When `cm` is `hdr` or `hdredid`, disable color temperature and any brightness row whose backend is `gamma`, with the reason `unavailable in HDR mode`. Hardware backlight/DDC brightness stays enabled.

- [ ] **Step 3: Handle monitor changes**

`onMonitorsChanged` in `DisplayManager` (extend the existing handler, do not replace it):

- Compare the sorted output-name list; only when it changes, call `DisplaySettingsService.invalidate()` and re-probe if the panel is open.
- If `settingsName` no longer exists, set `view = "main"` and `settingsName = ""`.
- Clamp `settingsPanel.selIndex` and `pickerIndex`.

- [ ] **Step 4: Add backend/error hints**

Show a muted line in the panel when:

- `wl-gammarelay-rs` is not reachable: `wl-gammarelay-rs not running — color temperature unavailable`.
- `ddcutil` fails but gamma is available: no modal; the brightness row's backend label reads `software`.
- `brightnessctl` fails and gamma is available: same fallback.
- `hyprctl` fails: existing main-view error line remains; settings do not open.

- [ ] **Step 5: Finish mouse and footer behavior**

Rows and picker options are clickable. Clicking a row selects it; clicking the value/arrows changes it; clicking a picker option applies it. Footer hints are:

```text
main:     j/k move · s settings · H/J/K/L position · Enter act · r refresh · Esc close
settings: j/k row · Enter choose · h/l adjust · Esc back
picker:   j/k option · Enter apply · Esc back
```

- [ ] **Step 6: Verify hotplug and mirror degradation**

```bash
hyprctl output create headless
```

Open settings on the new `HEADLESS-*` output (use the actual name from `hyprctl monitors -j`), then remove it:

```bash
hyprctl output remove HEADLESS-1
```

Expected: settings closes to main, no QML errors, no stale index.

Mirror `eDP-1` with the headless output and open settings on the mirrored one. Expected: compositor rows disabled with the reason; brightness/temperature still enabled.

- [ ] **Step 7: Verify HDR gating**

On HDR-capable hardware, select an HDR preset and confirm color temperature and gamma brightness are disabled with `unavailable in HDR mode`, while backlight/DDC brightness stays usable. If no HDR-capable display is available, try `hl.monitor({output="HEADLESS-1", cm="hdr", bitdepth=10})`; if Hyprland accepts it, run the same check. If it falls back to `srgb`, mark the check as code-review-only and confirm the gating condition in `DisplaySettingsPanel.qml`.

- [ ] **Step 8: Verify daemon absence**

```bash
pkill wl-gammarelay-rs
```

Open settings. Expected: temperature row hidden, muted hint visible, no error spam. Restart with `wl-gammarelay-rs &`, press `r`, and confirm the row returns.

- [ ] **Step 9: Commit**

```bash
git add quickshell/components/launchers/DisplaySettingsPanel.qml quickshell/components/launchers/DisplayManager.qml
git commit -m "fix(display): degrade settings cleanly on hotplug and backend failure"
```

---

### Task 7: Spec updates and final verification

**Files:**
- Modify: `quickshell/specs/launchers/Display-manager.md`
- Modify: `quickshell/specs/SPECS.md`

**Interfaces:**
- Consumes: the completed implementation.
- Produces: normative documentation matching the shipped behavior.

- [ ] **Step 1: Add the settings section to the Display Manager spec**

Add §3.4 `Per-Monitor Settings (s)` with the row table, capability gates, brightness precedence, color-temperature backend, runtime-only note, and the `Esc` stack. Update §4 interaction, §5 backend notes, §6 degraded states, and §7 acceptance. Keep the existing §3.1-3.3 behavior text intact.

- [ ] **Step 2: Update the project inventory**

In `quickshell/specs/SPECS.md`, add `services/DisplaySettingsService.qml` and `components/launchers/DisplaySettingsPanel.qml` to the file layout, and add `brightnessctl`, `ddcutil`, `wl-gammarelay-rs`, and `hardware.i2c.enable` to the dependency section. Note the runtime-only boundary.

- [ ] **Step 3: Run the full clean-load check**

```bash
quickshell -p "$PWD/quickshell" 2>&1 | grep -iE "error|warning|unable" | head
```

Expected: no output from the changed files.

- [ ] **Step 4: Run the theme-token check**

```bash
grep -R "#[0-9a-fA-F]" --include="*.qml" "$PWD/quickshell" | grep -v "theme/Theme.qml"
```

Expected: empty.

- [ ] **Step 5: Run the manual acceptance checklist**

Walk spec §13 top to bottom. Record any failing item and fix it before committing.

- [ ] **Step 6: Commit**

```bash
git add quickshell/specs/launchers/Display-manager.md quickshell/specs/SPECS.md
git commit -m "docs(display): document per-monitor settings"
```

---

## Post-Plan Review

After Task 7, run a whole-branch review with a fresh reviewer. Check the completed branch against the spec, with particular attention to:

- The rule-builder refactor preserving the existing position/mirror/disconnect behavior.
- DDC and gamma fallback ordering under real failures.
- Layout recomputation after mode/scale/rotation.
- No runtime file writes and no `hyprland.lua` mutations.
