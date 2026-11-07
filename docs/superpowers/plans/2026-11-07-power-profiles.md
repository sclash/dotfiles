# Power Profiles Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add power-profile switching (performance / balanced / power-saver) to the Quickshell PowerCenter card, with an automatic rule keyed off power source and charge and a manual pick that holds until "Auto" is re-selected.

**Architecture:** A new `services/PowerProfileService.qml` singleton wraps Quickshell's native `Quickshell.Services.UPower.PowerProfiles`, reads `BatteryService` for power-source/charge, owns the auto rule + hysteresis, and is the only writer of `PowerProfiles.profile`. `PowerCenter.qml` gains a four-row profile section that calls the service. No new launcher, keybind, daemon, or Nix dependency.

**Tech Stack:** QML / Quickshell 0.3.2 (`Quickshell.Services.UPower.PowerProfiles`), power-profiles-daemon, Nerd Font glyphs.

**Spec:** `docs/superpowers/specs/2026-11-07-power-profiles-design.md`

## Global Constraints

- No new Nix dependency: `services.power-profiles-daemon.enable = true` already at `nixos/configuration.nix:204`; no TLP/auto-cpufreq.
- All colours via `Theme.*`, all glyphs via `Icons.*` — no hard-coded `#hex` or glyph literals outside `theme/Theme.qml` / `theme/Icons.qml`.
- Never write a profile PPD does not offer: guard with `PowerProfiles.hasPerformanceProfile`.
- Services are `pragma Singleton` in module `services`; launchers read services and never poll; at most one `Process` per subsystem (the availability probe is one-shot).
- `quickshell -p .` must print `Configuration Loaded` with no QML errors; idle RSS < 200 MB.
- Normative specs are updated in the same change as the code they describe (specs §3 exception for `SPECS.md`, done in Task 4).
- Conventional Commits (`feat:` / `docs:` / `chore:`); one commit per task. Commit from repo root `/home/asergi/dotfiles`; paths below are relative to `/home/asergi/dotfiles/quickshell`.

## Review Focus

Inputs/conditions the spec implies but the smoke check does not exercise — each has a verification step in the task that owns the code:

1. **Battery-less desktop** (no UPower battery): `BatteryService.available === false` → auto target must be performance (or balanced if unsupported), section still renders. (Task 2, Task 3)
2. **Unknown capacity (`-1`)** on a present-but-unready battery: must NOT be treated as low; expect balanced. (Task 2)
3. **power-profiles-daemon unreachable**: `available` probe false → profile section hidden, no writes, no QML errors. (Task 2, Task 3)
4. **Machine without a performance profile** (`hasPerformanceProfile === false`): Performance row hidden; AC target falls back to balanced. (Task 2, Task 3)
5. **Rapid plug/unplug or charge hovering 20–25%**: hysteresis keeps one profile, no flapping. (Task 3, Task 4)

---

### Task 1: Profile glyphs in `Icons.qml` + `STYLE.md`

**Files:**
- Modify: `theme/Icons.qml` (add a `// Power profiles` block; nearest existing block: `// Perf`, lines ~147-153)
- Modify: `specs/STYLE.md` (§3 code block, after the `// USB` lines ~197)

**Interfaces:**
- Produces: `Icons.profileAuto`, `Icons.profilePerformance`, `Icons.profileBalanced`, `Icons.profilePowerSaver` (all `string`), consumed by Task 3.
- Codepoints are MDI above the BMP, so they use `String.fromCodePoint` (never `\u`).

- [ ] **Step 1: Add the four glyph properties**

In `theme/Icons.qml`, add after the `// Perf` block:

```qml
    // Power profiles
    property string profileAuto:        String.fromCodePoint(0xF0069)  // nf-md-autorenew
    property string profilePerformance: String.fromCodePoint(0xF04C5)  // nf-md-speedometer
    property string profileBalanced:    String.fromCodePoint(0xF05D1)  // nf-md-scale-balance
    property string profilePowerSaver:  String.fromCodePoint(0xF032A)  // nf-md-leaf
```

- [ ] **Step 2: Mirror them into the STYLE glyph map**

In `specs/STYLE.md` §3, add the same four lines to the `Icons.qml` code block (keep the existing comment style).

- [ ] **Step 3: Verify the codepoints exist in the installed Nerd Font**

Run:
```bash
for cp in f0069 f04c5 f05d1 f032a; do echo "$cp -> $(fc-list ":charset=$cp" 2>/dev/null | grep -ci jetbrainsmono)"; done
```
Expected: each prints a non-zero count.

- [ ] **Step 4: Smoke check**

Run: `cd /home/asergi/dotfiles/quickshell && timeout 6 quickshell -p . 2>&1 | grep -E "Configuration Loaded|Error|TypeError"`
Expected: `Configuration Loaded`, no `Error`/`TypeError` lines.

- [ ] **Step 5: Commit**

```bash
cd /home/asergi/dotfiles
git add quickshell/theme/Icons.qml quickshell/specs/STYLE.md
git commit -m "feat(icons): add power-profile glyphs"
```

---

### Task 2: `PowerProfileService` singleton

**Files:**
- Create: `services/PowerProfileService.qml`
- Modify: `services/qmldir` (add a `singleton` line after line 9)

**Interfaces:**
- Consumes: `BatteryService` (`available`, `plugged`, `charging`, `capacity`) — same module, so in scope without an explicit import; `PowerProfiles` / `PowerProfile` / `PerformanceDegradationReason` from `Quickshell.Services.UPower`.
- Produces (consumed by Task 3):
  - `readonly property bool available`
  - `readonly property bool hasPerformance`
  - `readonly property int current` (`PowerProfile.*`)
  - `readonly property bool degraded`
  - `property bool auto`
  - `readonly property int autoTarget` (`PowerProfile.*`)
  - `function setProfile(p: int): void`
  - `function setAuto(): void`

- [ ] **Step 1: Write the service**

Create `services/PowerProfileService.qml`. The rule + hysteresis are the non-obvious logic, so the full body is fixed; the availability probe line may be adapted (Step 3).

```qml
pragma Singleton
import QtQuick
import Quickshell.Services.UPower

QtObject {
    id: root

    // PPD reachable — set by the one-shot probe below.
    property bool _probed: false
    readonly property bool available: _probed

    readonly property bool hasPerformance: PowerProfiles.hasPerformanceProfile
    readonly property int  current: PowerProfiles.profile
    readonly property int  degradation: PowerProfiles.degradationReason
    readonly property bool degraded: degradation !== PerformanceDegradationReason.None

    // Auto mode follows the power source; a manual pick holds until setAuto().
    property bool auto: true
    // Hysteresis latch: true once capacity dropped to <= 20 on battery.
    property bool _low: false

    // The profile the auto rule wants right now (no side effects).
    // NB: capacity is -1 when unknown, so the low tests require >= 0.
    function _target() {
        if (!BatteryService.available || BatteryService.plugged)
            return hasPerformance ? PowerProfile.Performance : PowerProfile.Balanced
        if (BatteryService.capacity >= 0 && BatteryService.capacity <= 20)
            return PowerProfile.PowerSaver
        if (_low && BatteryService.capacity < 25)
            return PowerProfile.PowerSaver
        return PowerProfile.Balanced
    }
    readonly property int autoTarget: _target()

    function setProfile(p) { auto = false; PowerProfiles.profile = p }
    function setAuto()     { auto = true; _apply() }

    function _apply() {
        if (!BatteryService.available || BatteryService.plugged) _low = false
        else if (BatteryService.capacity >= 0 && BatteryService.capacity <= 20) _low = true
        if (auto && available) PowerProfiles.profile = _target()
    }

    property Connections batteryConn: Connections {
        target: BatteryService
        function onCapacityChanged() { root._apply() }
        function onPluggedChanged()  { root._apply() }
        function onChargingChanged() { root._apply() }
    }

    property Process probe: Process {
        command: ["powerprofilesctl", "list"]
        running: true
        onExited: (code) => { root._probed = (code === 0); root._apply() }
    }

    Component.onCompleted: _apply()
}
```

- [ ] **Step 2: Register the singleton**

In `services/qmldir`, add (after `DisplaySettingsService`):

```
singleton PowerProfileService 1.0 PowerProfileService.qml
```

- [ ] **Step 3: Smoke check + choose the probe command**

Run: `cd /home/asergi/dotfiles/quickshell && timeout 6 quickshell -p . 2>&1 | tee /tmp/qs-pp.log | grep -E "Configuration Loaded|Error|TypeError|not defined"`
Expected: `Configuration Loaded`, no error/undefined lines. If `powerprofilesctl` is not the right availability signal, substitute a one-shot `["busctl","--system","call","net.hadess.PowerProfiles","/net/hadess/PowerProfiles","org.freedesktop.DBus.Peer","Ping"]` and re-run.

- [ ] **Step 4: Verify the auto rule (Review Focus 1, 2, 4)**

Inspect the `_target()` body against each row of the design's semantics table and record the outcome:
- no battery / plugged → performance (balanced if `!hasPerformance`);
- on battery `capacity >= 0 && <= 20` → power-saver;
- `capacity == -1` → falls through to balanced (never power-saver);
- `!hasPerformance` → performance branch yields balanced.
This is a code-inspection check (no QML test runner in this repo); state each box explicitly in the task notes.

- [ ] **Step 5: Commit**

```bash
cd /home/asergi/dotfiles
git add quickshell/services/PowerProfileService.qml quickshell/services/qmldir
git commit -m "feat(power): add PowerProfileService with auto rule and hysteresis"
```

---

### Task 3: Profile section in `PowerCenter.qml` + `Power-Center.md`

**Files:**
- Modify: `components/launchers/PowerCenter.qml`
- Modify: `specs/launchers/Power-Center.md` (§1 purpose, §3 add a Profile subsection, §5 interaction, §9 acceptance)

**Interfaces:**
- Consumes: `PowerProfileService.*` (Task 2), `Icons.profile*` (Task 1).
- Produces: nothing consumed later.

- [ ] **Step 1: Make the card scrollable (STYLE §5.7)**

Convert the card body to the `AudioCenter` pattern: wrap `mainCol` in a `Flickable` (`anchors.fill`, `anchors.margins: Theme.padL`, `clip: true`, `contentWidth: width`, `contentHeight: mainCol.implicitHeight`, `boundsBehavior: Flickable.StopAtBounds`, `ScrollBar.vertical` with 4 px `Theme.borderActive` handle), give `mainCol` `width: scrollFlick.width`, and raise the card cap to `Math.min(620, mainCol.implicitHeight + Theme.padL * 2)`. Keep `clip: true` on the card. Keep the existing `Keys.onPressed` (currently on `mainCol`).

- [ ] **Step 2: Add the profile section**

In `PowerCenter.qml` add state at the root:

```qml
    property int profileSel: 0
    readonly property var profileRows: {
        const rows = [{ key: "auto", label: "Auto", glyph: Icons.profileAuto }]
        if (PowerProfileService.hasPerformance) rows.push({ key: "performance", label: "Performance", glyph: Icons.profilePerformance })
        rows.push({ key: "balanced",    label: "Balanced",    glyph: Icons.profileBalanced })
        rows.push({ key: "powerSaver",  label: "Power Saver", glyph: Icons.profilePowerSaver })
        return rows
    }
    function applyRow(i) {
        const r = profileRows[i]
        if (!r) return
        if (r.key === "auto") PowerProfileService.setAuto()
        else if (r.key === "performance") PowerProfileService.setProfile(PowerProfile.Performance)
        else if (r.key === "balanced")    PowerProfileService.setProfile(PowerProfile.Balanced)
        else                              PowerProfileService.setProfile(PowerProfile.PowerSaver)
    }
    function engaged(r) {
        if (r.key === "auto") return PowerProfileService.auto
        if (PowerProfileService.auto) return false
        if (r.key === "performance") return PowerProfileService.current === PowerProfile.Performance
        if (r.key === "balanced")    return PowerProfileService.current === PowerProfile.Balanced
        return PowerProfileService.current === PowerProfile.PowerSaver
    }
    function targetLabel() {
        const p = PowerProfileService.autoTarget
        if (p === PowerProfile.Performance) return "Performance"
        if (p === PowerProfile.Balanced) return "Balanced"
        return "Power Saver"
    }
```

Add `import Quickshell.Services.UPower` at the top of the file. In `mainCol`, insert a `Power profile` section **between the charge bar and the detail-row divider**, visible only when `PowerProfileService.available`:
- an uppercase `Text` header (`Theme.fgMuted`, `Theme.fontSizeSmall`, `capitalization: Font.AllUppercase`, `letterSpacing: 1.2`);
- a `ColumnLayout` with a `Repeater { model: root.profileRows }`, delegate a `Rectangle` row: `Layout.fillWidth: true`, `Layout.preferredHeight: 34`, `radius: Theme.roundingItem`, `color: "transparent"`, `border.width: 1`, `border.color: (root.profileSel === index) ? Theme.borderSelected : Theme.border`. Inside: `Text` glyph (`Theme.fgMuted`), `Text` label (`Theme.fg`, `Theme.fontSizeLauncher`), `Layout.fillWidth: true`; trailing `Text` — `Icons.check` at `Theme.success` when `root.engaged(modelData)`, otherwise when `modelData.key === "auto"` a `Theme.fgMuted` `"→ " + root.targetLabel()`. Optional `MouseArea` setting `root.profileSel = index` and `root.applyRow(index)`;
- a degraded note below the rows: `visible: PowerProfileService.degraded`, `Text { text: Icons.warning + " performance degraded: " + (<reason>) ; color: Theme.warning; font.pixelSize: Theme.fontSizeSmall }` where reason is `"lap detected"` for `PerformanceDegradationReason.LapDetected`, else `"high temperature"`.

- [ ] **Step 3: Extend the key handler and footer**

In the existing `Keys.onPressed`, before the `Esc` branch order matters only for `Esc`; add:
- `j`/`Down` → `root.profileSel = Math.min(root.profileRows.length - 1, root.profileSel + 1)`;
- `k`/`Up` → `root.profileSel = Math.max(0, root.profileSel - 1)`;
- `Return`/`Enter` → `root.applyRow(root.profileSel)`;
- digits `1`–`4` → `root.applyRow(n - 1)` when that row exists.
Keep `Esc` → `root.close()`. Change the footer `Text` to `"j/k select · Enter apply · Esc close"`.

- [ ] **Step 4: Update `specs/launchers/Power-Center.md`**

- §1: replace "Display-only — no power-profile mutation" with a sentence that the card shows battery status **and** the power-profile switcher (auto + manual), backed by `PowerProfileService`; power actions still live in `Shutdown-Launcher.md`.
- §3: add a "3.x Power profile" subsection describing the four rows, the Auto `→ <target>` hint, the single check indicator, the degraded note, hidden when `!available`, and the `j/k` + `Enter` + `1`–`4` interaction.
- §5: update the interaction bullets (remove "no j/k cursor, no Enter action") and the footer hint.
- Add a §4 contract for `PowerProfileService.qml` (the Task 2 Interfaces block, plus the auto-rule table and hysteresis).
- §9: add acceptance boxes — auto on AC/battery/threshold, hysteresis no-flap, manual hold until Auto, degraded/no-ppd/no-battery paths.

- [ ] **Step 5: Smoke check (Review Focus 1, 3, 4)**

Run: `cd /home/asergi/dotfiles/quickshell && timeout 6 quickshell -p . 2>&1 | tee /tmp/qs-pc.log | grep -E "Configuration Loaded|Error|TypeError|not defined|Unable to assign"`
Expected: `Configuration Loaded`, no error lines. Confirm by reading the section markup that it is `visible: PowerProfileService.available` (Review Focus 3) and that the Performance row is gated on `hasPerformance` (Review Focus 4).

- [ ] **Step 6: Commit**

```bash
cd /home/asergi/dotfiles
git add quickshell/components/launchers/PowerCenter.qml quickshell/specs/launchers/Power-Center.md
git commit -m "feat(power-center): add power-profile switcher section"
```

---

### Task 4: `SPECS.md` updates + end-to-end acceptance

**Files:**
- Modify: `specs/SPECS.md`

**Interfaces:**
- Consumes: everything from Tasks 1–3.

- [ ] **Step 1: Update `SPECS.md`**

- §2.2 dependency table: add a row `power-profiles-daemon | CPU platform profiles | **yes** | services.power-profiles-daemon.enable (configuration.nix)`.
- §3.1 file layout: add `PowerProfileService.qml` under `services/` with the comment `# Singleton — PPD profile read/write + auto rule (hysteresis)`.
- §5.1 inventory: extend the Battery row to note the card also switches power profiles (`PowerProfileService`).
- §5.blue: no new launcher, so no row in §5.2.

- [ ] **Step 2: End-to-end acceptance (Review Focus 5)**

Restart the running shell so the new service loads (`quickshell -p . &` in a spare session, or re-login), then:
- **Plugged:** `powerprofilesctl get` → `performance`.
- **Unplug, capacity > 20%:** → `balanced`. Plug back → `performance`.
- **Unplug with capacity ≤ 20%** (or force the threshold by reasoning if the battery is high): → `power-saver`.
- **Hysteresis:** with the battery near 20–25%, confirm the profile does not oscillate between balanced and power-saver across several seconds.
- **Manual hold:** open PowerCenter (`SUPER+p`), pick Balanced while plugged → stays `balanced` after un/replug until the **Auto** row is re-selected, which re-applies `performance`.
Record each result as a checked box.

- [ ] **Step 3: Final compliance checks**

Run:
```bash
cd /home/asergi/dotfiles/quickshell
grep -R "#[0-9a-fA-F]\{3,8\}" --include="*.qml" components/ theme/ | grep -v "theme/Theme.qml" | grep -v "theme/Icons.qml"   # expect empty
grep -R "Process" --include="*.qml" components/ | grep -v "DBus"   # expect empty (launchers don't spawn services)
```
Expected: both empty.

- [ ] **Step 4: Commit**

```bash
cd /home/asergi/dotfiles
git add quickshell/specs/SPECS.md
git commit -m "docs(specs): document power profiles in master spec"
```

---

## Self-Review

- **Spec coverage:** intent/goals → Tasks 2–3; hysteresis + option-B hold → Task 2 rule + Task 3 UI; icons → Task 1; degraded/no-battery/no-perf → Tasks 2–3 verification; spec updates → Tasks 3–4; acceptance → Task 4. No gaps.
- **Type consistency:** `setProfile(p)` / `setAuto()` / `available` / `hasPerformance` / `current` / `auto` / `autoTarget` / `degraded` are named identically in the Task 2 Interfaces, the code, and Task 3's helpers; `Icons.profile*` names match Task 1.
- **Review Focus:** each of the five lines has an owning task step (Task 2 Step 4; Task 3 Step 5; Task 4 Step 2).
- **Proportion:** the only transcript is the service body (the auto rule is the algorithm the plan must fix); the UI is specified by structure + exact tokens, not full code.
