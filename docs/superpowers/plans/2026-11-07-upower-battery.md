# UPower-backed BatteryService Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `BatteryService`'s sysfs `Process`+`Timer` poll with Quickshell's native `Quickshell.Services.UPower`, and surface battery health and model in the Power Center.

**Architecture:** `BatteryService.qml` becomes a passive `QtObject` whose properties are bindings over `UPower.displayDevice` (aggregate) and a laptop-battery lookup in `UPower.devices`, with units normalized to the existing public contract. Consumers are unchanged except `PowerCenter`, which gains two rows and loses the manual refresh. No new dependency.

**Tech Stack:** Quickshell 0.3.2 (QML, `Quickshell.Services.UPower`), upower 1.91.5 (already running).

**Spec:** `docs/superpowers/specs/2026-11-07-upower-battery-design.md`

## Global Constraints

- No new Nix dependency (`upower` already in `programs/quickshell.nix:31`; daemon enabled at `configuration.nix:201`).
- All colours via `Theme.*`, all glyphs via `Icons.*` — no hard-coded `#hex` or glyph literals.
- Keep the public contract property names: `available`, `charging`, `plugged`, `discharging`, `capacity`, `energyNow`, `energyFull`, `powerNow`, `timeLeftMinutes`; add `health`, `healthSupported`, `model`.
- `refresh()` is deleted everywhere (service and UI).
- Conventional Commits; one commit per task.

## Review Focus

- **No battery / device not ready:** `UPower.displayDevice` may exist but be absent or not `ready`; `available` must be `false` and `capacity` must not be `NaN`. Owned by Task 2 (test in Task 1).
- **Machine without `upowerd`:** every UPower property is empty/zero; the service must degrade, never throw. Owned by Task 2.
- **`plugged` vs `charging` precedence:** while charging, `plugged` must be `false` so the charging colour/glyph win. Owned by Task 2.
- **`timeToEmpty`/`timeToFull` zero or NaN:** must map to `timeLeftMinutes === -1`, never `0m`. Owned by Task 2.
- **Aggregate vs per-battery:** state/energy/rate/time come from `displayDevice`; health/model come from the battery device. Owned by Task 2.

---

### Task 1: Probe harness + failing behavioral test

**Files:**
- Create: `quickshell/.probe-battery/shell.qml` (throwaway; removed in Task 5)
- Create: `/tmp/opencode/battery-probe-check.sh` (throwaway)

**Interfaces:**
- Consumes: the `services` module singleton `BatteryService` (existing properties, and the new `health`/`healthSupported`/`model` this test requires).
- Produces: nothing consumed by later tasks; a runnable check reused in Task 2 and Task 5.

- [ ] **Step 1: Write the probe QML**

Create `quickshell/.probe-battery/shell.qml`:

```qml
import QtQuick
import Quickshell
import "../services"

ShellRoot {
    Timer {
        interval: 1500
        running: true
        repeat: false
        onTriggered: {
            console.log("BATTERY_PROBE " + JSON.stringify({
                available: BatteryService.available,
                capacity: BatteryService.capacity,
                energyNow: BatteryService.energyNow,
                energyFull: BatteryService.energyFull,
                powerNow: BatteryService.powerNow,
                charging: BatteryService.charging,
                discharging: BatteryService.discharging,
                plugged: BatteryService.plugged,
                timeLeftMinutes: BatteryService.timeLeftMinutes,
                health: BatteryService.health,
                healthSupported: BatteryService.healthSupported,
                model: BatteryService.model,
                hasRefresh: typeof BatteryService.refresh === "function"
            }))
            Qt.exit(0)
        }
    }
}
```

- [ ] **Step 2: Write the assertion script**

Create `/tmp/opencode/battery-probe-check.sh`:

```sh
#!/usr/bin/env bash
set -euo pipefail
REPO=/home/asergi/dotfiles
out=$(cd "$REPO/quickshell" && qs -p .probe-battery/shell.qml 2>&1 | grep -m1 '^BATTERY_PROBE ' || true)
json="${out#BATTERY_PROBE }"
[ -n "$json" ] || { echo "FAIL: probe produced no output"; exit 1; }
echo "$json"
node -e '
const j = JSON.parse(process.argv[1]);
const bad = [];
const num = (x) => typeof x === "number" && !isNaN(x);
if (typeof j.available !== "boolean") bad.push("available not bool");
if (!num(j.capacity) || j.capacity < 0 || j.capacity > 100) bad.push("capacity out of range");
if (!num(j.energyNow) || j.energyNow <= 0) bad.push("energyNow invalid");
if (!num(j.energyFull) || j.energyFull <= j.energyNow) bad.push("energyFull invalid");
if (!num(j.powerNow) || j.powerNow <= 0) bad.push("powerNow invalid");
if (!num(j.timeLeftMinutes) || j.timeLeftMinutes <= 0) bad.push("timeLeftMinutes invalid");
if (typeof j.healthSupported !== "boolean") bad.push("healthSupported not bool");
if (typeof j.model !== "string") bad.push("model not string");
if (j.hasRefresh !== false) bad.push("refresh() still present");
if (j.plugged && j.charging) bad.push("plugged and charging both true");
console.log(bad.length ? "FAIL: " + bad.join("; ") : "PASS");
process.exit(bad.length ? 1 : 0);
' "$json"
```

- [ ] **Step 3: Run the test and confirm it fails**

Run: `bash /tmp/opencode/battery-probe-check.sh`
Expected: FAIL — `refresh() still present` (and/or `health`/`model` undefined) because the current service is still the sysfs one.

- [ ] **Step 4: Commit the probe**

```bash
cd /home/asergi/dotfiles
git add quickshell/.probe-battery/shell.qml
git commit -m "test(battery): add throwaway UPower probe harness"
```

---

### Task 2: Rewrite BatteryService on UPower

**Files:**
- Modify: `quickshell/services/BatteryService.qml` (full rewrite)

**Interfaces:**
- Consumes: `Quickshell.Services.UPower` (`UPower.displayDevice`, `UPower.devices`, `UPower.onBattery`, `UPowerDeviceType`, `UPowerDeviceState`).
- Produces: singleton `services/BatteryService` with `available: bool`, `capacity: int`, `energyNow: double` (µWh), `energyFull: double` (µWh), `powerNow: double` (µW), `charging: bool`, `discharging: bool`, `plugged: bool`, `timeLeftMinutes: int`, `health: double`, `healthSupported: bool`, `model: string`. No `refresh()`.

- [ ] **Step 1: Write the new service**

Replace the whole file with:

```qml
pragma Singleton
import QtQuick
import Quickshell.Services.UPower

QtObject {
    id: root

    // Aggregate across all batteries (handles multi-battery machines).
    readonly property UPowerDevice display: UPower.displayDevice

    // Per-battery device for the fields the aggregate reports as N/A
    // (health, model). Prefer the laptop battery.
    readonly property UPowerDevice battery: {
        let fallback = null
        for (const d of UPower.devices.values) {
            if (d.type !== UPowerDeviceType.Battery) continue
            if (d.isLaptopBattery) return d
            if (!fallback) fallback = d
        }
        return fallback
    }

    readonly property bool available: display ? (display.ready && display.isPresent) : false

    readonly property int capacity: {
        if (!available || isNaN(display.percentage)) return -1
        return Math.round(display.percentage)
    }
    // Normalized to the historical contract: µWh / µW. UPower reports Wh / W.
    readonly property double energyNow: available ? display.energy * 1000000 : -1
    readonly property double energyFull: available ? display.energyCapacity * 1000000 : -1
    readonly property double powerNow: available ? display.changeRate * 1000000 : -1

    readonly property bool charging: available && display.state === UPowerDeviceState.Charging
    readonly property bool discharging: available &&
        (display.state === UPowerDeviceState.Discharging || display.state === UPowerDeviceState.Empty)
    // On AC and not actively charging (covers Full / pending / not-charging).
    readonly property bool plugged: !UPower.onBattery && !charging

    readonly property int timeLeftMinutes: {
        if (!display) return -1
        let secs = -1
        if (discharging) secs = display.timeToEmpty
        else if (charging) secs = display.timeToFull
        if (isNaN(secs) || secs <= 0) return -1
        return Math.round(secs / 60)
    }

    readonly property bool healthSupported: battery ? battery.healthSupported : false
    readonly property double health: (battery && battery.healthSupported) ? battery.healthPercentage : -1
    readonly property string model: battery ? (battery.model || "") : ""
}
```

- [ ] **Step 2: Run the probe against the new service**

Run: `bash /tmp/opencode/battery-probe-check.sh`
Expected: **PASS** — values match expected shapes and `refresh()` is gone.

- [ ] **Step 3: Cross-check values against upower**

Run:
```bash
cd /home/asergi/dotfiles/quickshell && qs -p .probe-battery/shell.qml 2>&1 | grep -m1 BATTERY_PROBE
upower -i /org/freedesktop/UPower/devices/DisplayDevice | grep -E 'energy|percentage|rate|state|time'
upower -i /org/freedesktop/UPower/devices/battery_BAT0 | grep -E 'capacity|model'
```
Expected: `capacity` ≈ displayDevice `percentage`; `energyNow`/`energyFull`/`powerNow` equal the Wh/W figures ×1e6; `health` ≈ battery `capacity` (65.2%); `model` = `Primary`.

- [ ] **Step 4: qmllint the file**

Run: `qmllint quickshell/services/BatteryService.qml 2>&1 | grep -cE 'Error|Syntax error'`
Expected: `0` (import-resolution warnings are pre-existing and expected).

- [ ] **Step 5: Commit**

```bash
cd /home/asergi/dotfiles
git add quickshell/services/BatteryService.qml
git commit -m "refactor(battery): read BatteryService from UPower"
```

---

### Task 3: Update PowerCenter (rows + drop refresh)

**Files:**
- Modify: `quickshell/components/launchers/PowerCenter.qml`

**Interfaces:**
- Consumes: `BatteryService.health`, `BatteryService.healthSupported`, `BatteryService.model` (Task 2). No `BatteryService.refresh()`.
- Produces: nothing consumed by later tasks.

- [ ] **Step 1: Remove the refresh call sites**

In `onIsOpenChanged`, change:

```qml
onIsOpenChanged: {
    if (isOpen) { BatteryService.refresh(); Qt.callLater(() => mainCol.forceActiveFocus()) }
}
```
to:
```qml
onIsOpenChanged: {
    if (isOpen) { Qt.callLater(() => mainCol.forceActiveFocus()) }
}
```

In `Keys.onPressed`, remove the `r`/`R` branch so only Escape remains:
```qml
Keys.onPressed: (e) => {
    if (e.key === Qt.Key_Escape) { root.close(); e.accepted = true }
}
```

- [ ] **Step 2: Update the footer hint**

Change the footer text from `"r refresh · Esc close"` to `"Esc close"`.

- [ ] **Step 3: Add the Health and Model rows**

In the details `ColumnLayout` (after the Energy row, before the Status row), insert:

```qml
RowLayout {
    visible: BatteryService.available && BatteryService.healthSupported
    Layout.fillWidth: true
    Text { text: "Health"; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeLauncher; color: Theme.fgMuted; Layout.fillWidth: true }
    Text {
        text: Math.round(BatteryService.health) + "%"
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeLauncher
        color: Theme.fg
    }
}
RowLayout {
    visible: BatteryService.available && BatteryService.model !== ""
    Layout.fillWidth: true
    Text { text: "Model"; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeLauncher; color: Theme.fgMuted; Layout.fillWidth: true }
    Text {
        text: BatteryService.model
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeLauncher
        color: Theme.fg
    }
}
```

- [ ] **Step 4: Verify no stale references and clean load**

Run:
```bash
cd /home/asergi/dotfiles
grep -rn "BatteryService.refresh\|r refresh" quickshell/ || echo "no stale references"
qmllint quickshell/components/launchers/PowerCenter.qml 2>&1 | grep -cE 'Error|Syntax error'
```
Expected: `no stale references`; error count `0`.

- [ ] **Step 5: Commit**

```bash
git add quickshell/components/launchers/PowerCenter.qml
git commit -m "feat(power-center): show battery health and model, drop manual refresh"
```

---

### Task 4: Update the specs

**Files:**
- Modify: `quickshell/specs/launchers/Power-Center.md` (§4 lines ~63–88, §5, §7 line ~104)
- Modify: `quickshell/specs/SPECS.md` (lines 43, 66, 118)

**Interfaces:**
- Consumes: the property contract from Task 2.
- Produces: nothing.

- [ ] **Step 1: Rewrite the Power-Center §4 service contract**

Replace the sysfs contract block (the `property double energyNow … // µWh from energy_now` block and the "One-shot read / Scheme normalization / Polling" bullets, including the line **`NONE` when no battery exists. No `upower` dependency.**) with a UPower-backed contract:

- Source: `UPower.displayDevice` for state/percentage/energy/rate/time; the `UPower.devices` laptop-battery entry for health/model.
- Units: normalized to µWh/µW/minutes; `energyNow`/`energyFull`/`powerNow` derive from `energy`/`energyCapacity`/`changeRate` ×1e6; `timeLeftMinutes` from `timeToEmpty`/`timeToFull` ÷60.
- New props `health: double`, `healthSupported: bool`, `model: string`.
- No `refresh()` (UPower is push-based); no `Process`/`Timer`, no polling.

- [ ] **Step 2: Update §5 interaction and §7 degraded**

In §5, remove the `r` refresh bullet and change the footer to `"Esc close"`. In §7, reword the "missing nodes" bullet to: no present battery device → `available === false`; `health`/`model` rows hidden when unsupported/unknown.

- [ ] **Step 3: Update SPECS.md**

- Line 43: battery source `sysfs `BAT*`, no UPower dep` → `UPower (Quickshell.Services.UPower)`.
- Line 66: dependency-table `upower` row → not optional ("required, native Quickshell module; `services.upower.enable = true`").
- Line 118: `BatteryService.qml` comment `sysfs BAT* status/capacity/energy/power + time-left estimate` → UPower-backed description.

- [ ] **Step 4: Verify no stale sysfs/upower-dependency claims remain**

Run:
```bash
cd /home/asergi/dotfiles
grep -rn "no UPower dep\|No \`upower\` dependency\|sysfs BAT" quickshell/specs/ || echo "clean"
```
Expected: `clean`.

- [ ] **Step 5: Commit**

```bash
git add quickshell/specs/launchers/Power-Center.md quickshell/specs/SPECS.md
git commit -m "docs(battery): document UPower-backed BatteryService"
```

---

### Task 5: Remove the probe and final verification

**Files:**
- Delete: `quickshell/.probe-battery/shell.qml`
- Delete: `/tmp/opencode/battery-probe-check.sh`

**Interfaces:**
- Consumes: everything above.
- Produces: a clean, verified branch.

- [ ] **Step 1: Run the full shell clean-start check**

Run: `cd /home/asergi/dotfiles && timeout 8 quickshell -p quickshell/shell.qml 2>&1 | grep -iE 'error|warning' || echo "clean"`
Expected: `clean` (no QML errors/warnings during load).
Note: `quickshell` here is the same `qs` binary; if `-p` on the live session conflicts, use `qs -n -p quickshell/shell.qml`.

- [ ] **Step 2: Confirm no hard-coded colours/glyphs were introduced**

Run: `grep -R "#[0-9a-fA-F]\{3,6\}" --include="*.qml" quickshell/ | grep -v "theme/Theme.qml" || echo "clean"`
Expected: `clean`.

- [ ] **Step 3: Remove the throwaway harness**

```bash
cd /home/asergi/dotfiles
rm -rf quickshell/.probe-battery
rm -f /tmp/opencode/battery-probe-check.sh
```

- [ ] **Step 4: Commit the removal**

```bash
git add -A quickshell/.probe-battery
git commit -m "test(battery): remove throwaway probe harness"
```

- [ ] **Step 5: Final status check**

Run: `git -C /home/asergi/dotfiles status --short && git -C /home/asergi/dotfiles log --oneline -5`
Expected: clean tree; the five commits present.

---

## Self-Review

- **Spec coverage:** contract preserved (T2), health/model added (T2) and surfaced (T3), refresh deleted service+UI (T2/T3), detection universal via UPower (T2), specs incl. the "no upower dependency" line updated (T4), no Nix change (constraint). ✔
- **Step scan:** each step yields one checkable result; no "TBD"/"handle edge cases". Probe/assert content given because it is the test. ✔
- **Type consistency:** `health`/`healthSupported`/`model`/`capacity`/`energyNow`/`energyFull`/`powerNow`/`timeLeftMinutes` named identically across T2 (produce) and T3/T4 (consume). ✔
- **Review Focus:** no-battery/not-ready and no-upowerd (T2, probe asserts shapes), plugged-vs-charging (probe asserts mutual exclusion), time zero/NaN (T2 guard), aggregate-vs-per-battery (T2 sources; T3 cross-check). ✔
- **Proportion:** plan ≈1.3× the spec; code blocks are the two files being rewritten, not a transcript. ✔
