# Display-Manager — Refined Spec

> Command: `SUPER+d` · File: `components/launchers/DisplayManager.qml` · Backend: `hyprctl monitors -j` / `hyprctl keyword monitor`

---

## 1. Purpose

Center-screen window to manage Hyprland monitors: inspect connected outputs, connect/disconnect, mirror/extend, orientation.

A **bar icon** in the right group next to the USB indicator (inline in `Bar.qml`) mirrors monitor state read-only from `HyprService`: `Icons.display` at `Theme.accent` when an external monitor is connected **and enabled** (`externalConnected`), `Theme.fg` when an external output is plugged but not enabled (`externalAvailable`), `Theme.fgDim` when only the reference monitor exists or Hyprland is unavailable. The reference monitor is the built-in panel (`eDP*` / `DSI*` output name); when none exists, the first active output is the reference, so "another monitor" means a second one. Click toggles the launcher (`display`).

## 2. Window

* `LauncherBase.qml`: `width: 640`, `radius: Theme.roundingLauncher`, vim nav, `/` filter, `Esc` closes.

## 3. Sections (top → bottom)

### 3.1 Current Monitors

* Source: `hyprctl monitors -j` JSON array, exposed as `HyprService.monitors`.
* Each row: `name` (e.g., `eDP-1`, `HDMI-A-1`) + `resolution@refresh` (e.g., `1920x1080@60.05`) + `scale` + `position` (`0x0`) + `focused` badge if `focused === true`.
* No action here beyond info; disconnect lives in 3.3.

### 3.2 Available Monitors to Connect

* Source: `hyprctl monitors all -j` (fallback `hyprctl monitors -j`), exposed as `HyprService.availableMonitors` — **plugged but not yet enabled** outputs (those with `disabled: true` or absent from `monitors` but present in `hyprctl monitors all`).
* Each row: `name` + `preferred mode` (from `availableModes`).
* **Connect actions** (mutually exclusive modes — pick one):

  | Mode | Runtime effect | Description |
  |---|---|---|
  | **Extend** | `hl.monitor({output={name}, disabled=false, mirror="", mode="preferred", position="auto", scale=1})` | Desktop spans both outputs |
  | **Duplicate / Mirror** | same rule + `mirror={reference}` | Clone the reference output |

  Buttons per row: `[ Extend ] [ Duplicate ]`. Both are nav stops — `j/k` selects the option and `Enter` activates it (mouse click works too).

### 3.3 Multi-Monitor Controls (visible only when `monitors.length >= 2`)

* **Disconnect:** per-row `Disconnect` button → `hl.monitor({output={name}, disabled=true})`. Disabled for the last remaining monitor (no-op + inline error "Cannot disable the only monitor" at `Theme.critical`).
* **Mode toggle:** per-row button labelled with the *action* — `Duplicate` when the output extends, `Extend` when it mirrors — swapped in place via `mirror={reference}` / `mirror=""`. Enabled mirrors are also merged into `HyprService.monitors`, so a mirrored output stays in **Current** (Hyprland 0.56 omits mirroring outputs from `hyprctl monitors`) and remains toggleable/positionable.
* **Position:** per-row `[L][R][T][B]` picker that repositions *that* output to the left/right/top/bottom edge of the whole layout, computed from every other monitor's geometry (collision-free for 3+ outputs). The picker highlights the monitor's current adjacent side. Position buttons used on a mirrored output unmirror it and place it.

## 4. Interaction

* `j/k` moves row focus (monitor rows → each available row's Extend/Duplicate options → refresh); `Enter` acts on the focused item (monitor row → disconnect, option → connect, refresh → refresh).
* `H/J/K/L` place the selected monitor on the left/bottom/top/right edge of the layout (vim 2×2 picker).
* `/` filter by monitor name substring.
* `r` refresh (re-run `hyprctl monitors -j` / `monitors all -j`).
* `Esc` closes.

## 5. Backend Notes

* Monitor listing is owned by `HyprService.qml` (single `Process` for both `monitors -j` and `monitors all -j`, event-driven via Hyprland `monitoradded` / `monitorremoved` / `configreloaded` with a 300 ms debounce). The launcher is a pure view over `HyprService.monitors` / `HyprService.availableMonitors` — no ad-hoc listing `Process`. `HyprService.monitors` entries carry numeric geometry (`x/y/w/h/scale/transform/id/mirrorOf`) so the launcher never parses display strings for math. **Enabled mirrors from `monitors all -j` are appended to `monitors`** because Hyprland 0.56 does not list mirroring outputs under `hyprctl monitors`; `availableMonitors` is therefore just the disabled outputs.
* **Mutation backend: `hyprctl eval`.** The Hyprland in use (0.56.x, Lua config via `hyprland.lua`) rejects `hyprctl keyword monitor` (`keyword can't work with non-legacy parsers. Use eval.`). All runtime mutations go through `hyprctl eval 'hl.monitor({...})'`, e.g. `hl.monitor({output="HDMI-A-1", disabled=false, mirror="", mode="1920x1080@60", position="1920x0", scale=1})`. `hl.monitor` rules merge per-field, so every emitted rule sets `disabled`/`mirror` explicitly. Re-applying rules can auto-shuffle outputs, so every mutation (place/extend/duplicate/disconnect) emits the target's rule **plus a preserving rule for every other active non-mirrored output**.
* Hyprland monitor config is **ephemeral** (runtime rules); it does not persist across restarts. That's correct — persistence belongs in `hyprland.lua` `hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "1" })` (already present). The launcher mutates **runtime** state only; users bake persistence by editing `hyprland.lua`.
* Alternative backends (`wlr-randr`, `kscreen-doctor`) are not required; `hyprctl` is sufficient. If `hyprctl` lacks a needed query (e.g., disconnected outputs), fall back to `hyprctl monitors all -j`.

## 6. Empty / Error States

* Single monitor only → 3.2 shows `"No additional outputs detected"` at `Theme.fgMuted`; position pickers hidden and `Disconnect` shown disabled with the last-monitor guard.
* `hyprctl` failure → inline error at `Theme.critical`; retry on `r`.

## 7. Acceptance

* [ ] Current monitors show name, mode, scale, position, focused badge.
* [ ] Available outputs offer Extend / Duplicate; Extend is default.
* [ ] Per-monitor `[L][R][T][B]` picker / `H/J/K/L` places that output at the corresponding layout edge without shuffling other outputs, and highlights the current adjacent side.
* [ ] `j/k` reaches both Extend and Duplicate options for an available output; `Enter` activates the focused option.
* [ ] Row button toggles Extend ↔ Duplicate in place; a mirrored output stays visible in **Current**.
* [ ] Disconnect works for `n≥2` and is disabled for last monitor.
* [ ] Runtime-only changes — `hyprland.lua` not mutated.
* [ ] Vim nav + `/` filter + `r` refresh + `Esc` close work.
* [ ] Uses `LauncherBase` + `Theme.*` tokens.
