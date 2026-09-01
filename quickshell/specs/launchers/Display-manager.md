# Display-Manager — Refined Spec

> Command: `SUPER+d` · File: `components/launchers/DisplayManager.qml` · Backend: `hyprctl monitors -j` / `hyprctl keyword monitor`

---

## 1. Purpose

Center-screen window to manage Hyprland monitors: inspect connected outputs, connect/disconnect, mirror/extend, orientation.

## 2. Window

* `LauncherBase.qml`: `width: 640`, `radius: Theme.roundingLauncher`, vim nav, `/` filter, `Esc` closes.

## 3. Sections (top → bottom)

### 3.1 Current Monitors

* Source: `hyprctl monitors -j` JSON array.
* Each row: `name` (e.g., `eDP-1`, `HDMI-A-1`) + `resolution@refresh` (e.g., `1920x1080@60.05`) + `scale` + `position` (`0x0`) + `focused` badge if `focused === true`.
* No action here beyond info; disconnect lives in 3.3.

### 3.2 Available Monitors to Connect

* Source: `hyprctl monitors all -j` or `wlr-randr`/`kscreen-doctor -o` equivalent to list **plugged but not yet enabled** outputs (those with `disabled: true` or absent from `monitors` but present in `hyprctl monitors all`).
* Each row: `name` + `preferred mode` (from `availableModes`).
* **Connect actions** (mutually exclusive modes — pick one):

  | Mode | Hyprctl effect | Description |
  |---|---|---|
  | **Extend** | `hyprctl keyword monitor {name},preferred,auto,1` (or explicit `WxH@Hz, XxY`) | Desktop spans both outputs |
  | **Duplicate / Mirror** | `hyprctl keyword monitor {name},preferred,auto,1,mirror,{primary}` | Clone primary |
  | **Only on this** | `hyprctl keyword monitor {others},disable` + enable `{name}` | Single-output |

  Buttons per row: `[ Extend ] [ Duplicate ] [ Only ]`. `Enter` on row defaults to **Extend**.
* **Orientation** (when in `extend` and `monitors.length >= 2`): per-monitor `Orientation` control:
  `Left` → `0x0` for new on left, `Right` → right of primary, `Top` / `Bottom` similarly. Implemented as `hyprctl keyword monitor {name},preferred,{x}x{y},1` where `x,y` is computed from neighbour geometry. Provide a minimal 2×2 visual (text grid) + `h/j/k/l` to pick direction.

### 3.3 Multi-Monitor Controls (visible only when `monitors.length >= 2`)

* **Disconnect:** per-row `Disconnect` button → `hyprctl keyword monitor {name},disable`. Disabled for the last remaining monitor (no-op + inline error "Cannot disable the only monitor" at `Theme.critical`).
* **Orientation summary:** for each monitor, show current `position` (e.g., `1920x0` meaning right of `eDP-1`). Allow re-orientation via the same `Left/Right/Top/Bottom` picker — re-issues `monitor` keyword with new coordinates.

## 4. Interaction

* `j/k` moves row focus; `Enter` primary action (extend/connect or dismiss error); `h/l` cycles orientation when the orientation picker is focused.
* `/` filter by monitor name substring.
* `r` refresh (re-run `hyprctl monitors -j` / `monitors all -j`).
* `Esc` hierarchy: clear filter / close orientation picker / close launcher.

## 5. Backend Notes

* Hyprland monitor config is **ephemeral** (`keyword`); it does not persist across restarts. That's correct — persistence belongs in `hyprland.lua` `hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "1" })` (already present). The launcher mutates **runtime** state only; users bake persistence by editing `hyprland.lua`.
* Alternative backends (`wlr-randr`, `kscreen-doctor`) are not required; `hyprctl` is sufficient. If `hyprctl` lacks a needed query (e.g., disconnected outputs), fall back to `hyprctl monitors all -j`.

## 6. Empty / Error States

* Single monitor only → 3.2 shows `"No additional outputs detected"` at `Theme.fgMuted`; 3.3 hidden.
* `hyprctl` failure → inline error at `Theme.critical`; retry on `r`.

## 7. Acceptance

* [ ] Current monitors show name, mode, scale, position, focused badge.
* [ ] Available outputs offer Extend / Duplicate / Only; Extend is default.
* [ ] Orientation picker (Left/Right/Top/Bottom) recomputes `monitor` position correctly for `extend`.
* [ ] Disconnect works for `n≥2` and is disabled for last monitor.
* [ ] Runtime-only changes — `hyprland.lua` not mutated.
* [ ] Vim nav + `/` filter + `r` refresh + `Esc` close work.
* [ ] Uses `LauncherBase` + `Theme.*` tokens.
