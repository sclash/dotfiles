# Bar Performance Section — Refined Spec

> Parent: [`Bar.md`](./Bar.md) · Service: `services/PerfService.qml`
> Legacy refs: `waybar/config.jsonc` — `disk`, `cpu`, `memory`, `temperature`, `group/expand`; `waybar/style.css` — `#cpu/#memory/#disk/#temperature` states.

---

## 1. Purpose

Collapsible metrics strip in the **right pill**, hidden by default to keep the bar minimal. Reveals CPU / RAM / Disk / Temperature when expanded.

## 2. Placement & Toggle

* Lives at the **leftmost edge of the right pill**, immediately left of `AudioIcon`.
* **Collapsed:** only a handle glyph `Icons.expand` (``) at `Theme.fgDim` is visible. Waybar drawer semantics (`config.jsonc:77-98`): `click-to-reveal: true`, `transition-duration: 600`.
* **Expanded:** handle rotates or flips to `Icons.collapse` (``) + four metric blocks in order:
  ```
    💿 12Gb 34%  󰻠 18% 0.42   3.2GiB 41%   52°C  |
  disk          cpu            memory          temp   endpoint
  ```
  Order is normative: **disk → cpu → memory → temperature → endpoint bar** — matches Waybar `group/expand.modules: [custom/expand, disk, cpu, memory, temperature, custom/endpoint]`.
* **Toggle triggers:**
  1. Click on ``/`` handle.
  2. `SUPER+p` (Hyprland bind → `quickshell ipc call perf toggle`).
  3. Hover is **not** a toggle — click only, to avoid accidental expand.
* **Animation:** `transition-duration: Theme.durationDrawer (600ms)`, `easeOutQuint`. Prefer `Behavior on width` or `NumberAnimation` on a `RowLayout` width. Launcher-style implicit resize is acceptable if Waybar `transition-to-left: true` parity is preserved (drawer expands leftwards).

## 3. Metrics

Each metric mirrors Waybar `format` + thresholds.

| Metric | Format (display) | Source | Thresholds (`warning` / `critical`) |
|---|---|---|---|
| **Disk** | `" 💿 {used}Gb {percentage}%"` | `statfs /` or `df -h /` | warning 60, critical 90 |
| **CPU** | `"󰻠 {usage}% {load}"` | `/proc/stat` (1s delta) | warning 60, critical 90 |
| **Memory** | `"  {used}GiB {percentage}%"` | `/proc/meminfo` | warning 60, critical 90 |
| **Temperature** | `" {temp}°C"` | `/sys/class/thermal/thermal_zone*/temp` or `sensors -j` | warning 60, critical 80 — see note |

* **Disk:** `used` in integer GB, `percentage_used` 0–100. Poll `statvfs` on `/`.
* **CPU:** `usage` is overall % from `/proc/stat` delta; `load` is 1-min `loadavg` (Waybar shows both). Two-decimal load.
* **Memory:** `used = MemTotal - MemAvailable` (GiB), `percentage = used / MemTotal * 100`.
* **Temperature:** Waybar `critical-threshold: 80` and `#temperature` is `#1189f2` by default. Prefer the `x86_pkg_temp` thermal zone (CPU die); fall back to the **hottest** numeric thermal zone (skip acpitz/INT3400 ambient zones — `thermal_zone0` is ambient on many laptops and reads ~20° while the CPU is hot). Unit °C. If no sensor, render ` --°C` dimmed.

**Colour by state:**

* `good` (<30): `Theme.fg` for all metrics (temperature included — `Theme.accent` is reserved for warnings/states elsewhere).
* `warning` (30/60–80/90): `Theme.warning` (`#c63d3d`).
* `critical` (>80/90): `Theme.critical` `#f53c3c` + `Theme.bgCritical` wash; for bar perf the Waybar `blink` animation is required (see `STYLE.md:6`): `SequentialAnimation on color { loops: Animation.Infinite }`.

## 4. Service Contract — `PerfService.qml`

```qml
QtObject {
  property bool expanded
  property bool available   // false if /proc not readable (never on Linux, but guard)
  // metrics
  property int cpuUsage          // 0-100
  property real cpuLoad          // 1-min loadavg
  property int memUsedGiB        // GiB
  property int memPercent        // 0-100
  property int diskUsedGb        // GB
  property int diskPercent       // 0-100
  property int tempC             // -1 if unavailable
  // control
  function toggle(): void
}
```

* **Polling:** `Timer { interval: 2000; running: expanded; repeat: true }` — **paused when collapsed**. No background polling when the drawer is hidden (cost budget in `SPECS.md:2.3`). One `Process` per tick that reads all four sources in one shell invocation (e.g., `cat /proc/stat; echo ---; cat /proc/meminfo; echo ---; df -BG /; echo ---; cat /sys/class/thermal/thermal_zone0/temp`).
* **Startup:** populate once on `Component.onCompleted` regardless of `expanded`, so the first expand is instant.

## 5. Layout

```
Collapsed:  []
Expanded:   [  💿 12Gb 34%  󰻠 18% 0.42   3.2GiB 41%   52°C  |]
             ^handle  ^disk      ^cpu         ^memory       ^temp ^endpoint
```

* Each block: `padding: 0 5px` (Waybar `#cpu/#memory/#disk/#temperature`).
* Endpoint `|` (`custom/endpoint`) is `color: transparent` with `text-shadow: 0 0 1.5px rgba(0,0,0,1)` — Waybar semantics for a hairline separator. Replicate with a `Rectangle { width: 1; color: Theme.border }` if glyph rendering differs.
* Handle `` at `color: alpha(Theme.fg, 0.2)` idle, `rgba(255,255,255,0.2)` on hover — Waybar `#custom-expand` parity.

## 6. Interaction

* Click handle → `PerfService.toggle()` + `launcher` IPC only for `SUPER+p` path; both toggle the same `expanded` property.
* Hover on any metric → tooltip with more detail (e.g., CPU per-core, memory `free -h`, disk `df -h`).
* No keyboard focus inside the drawer — it's display-only. Full details live elsewhere if needed.

## 7. Error Handling

* Missing sensor → ` --°C` dimmed, no `critical` state.
* `/proc` read failure → `available=false`, drawer shows `—` placeholders, tooltip explains.

## 8. Acceptance

* [ ] Collapsed shows only ``; expanded shows four metrics + handle + endpoint in the specified order.
* [ ] `SUPER+p` and click both toggle; animation is 600ms `easeOutQuint`.
* [ ] No polling when collapsed (verified via `ps` / `PerfService` timer `running`).
* [ ] Colours and `blink` on critical match `waybar/style.css` parity.
* [ ] Temperature falls back to `--°C` when no sensor.
