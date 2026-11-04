# Display-Manager — Refined Spec

> Command: `SUPER+d` · File: `components/launchers/DisplayManager.qml` · Backend: `hyprctl monitors -j` / `hyprctl keyword monitor`

---

## 1. Purpose

Center-screen window to manage Hyprland monitors: inspect connected outputs, connect/disconnect, mirror/extend, orientation, and per-output settings (`s`).

A **bar icon** in the right group next to the USB indicator (inline in `Bar.qml`) mirrors monitor state read-only from `HyprService`: `Icons.display` at `Theme.accent` when an external monitor is connected **and enabled** (`externalConnected`), `Theme.fg` when an external output is plugged but not enabled (`externalAvailable`), `Theme.fgDim` when only the reference monitor exists or Hyprland is unavailable. The reference monitor is the built-in panel (`eDP*` / `DSI*` output name); when none exists, the first active output is the reference, so "another monitor" means a second one. Click toggles the launcher (`display`).

## 2. Window

* `LauncherBase.qml`: `width: 640`, `radius: Theme.roundingLauncher`, vim nav, `/` filter, `Esc` closes.
* Settings sub-view (`DisplaySettingsPanel.qml`): same 640 px card and `Theme.roundingLauncher`; an enumerated row opens a 380 px modal picker inside the card.

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
* **Position:** per-row `[L][R][T][B]` picker that repositions *that* output to the left/right/top/bottom edge of the whole layout, computed from every other monitor's geometry (collision-free for 3+ outputs). The current adjacent side is rendered as a **filled white chip**, captioned with the neighbour, e.g. `bottom of HDMI-A-1` (falls back to the raw `x,y` when the output is not edge-adjacent to any other). Position buttons used on a mirrored output unmirror it and place it.

### 3.4 Per-Monitor Settings (`s`)

`s` on the selected monitor row opens a settings view for that output. Rows come from the output's reported capabilities (`HyprService.mapMonitor` fields) plus the hardware descriptor owned by `DisplaySettingsService`. Baseline compositor rows (mode, scale, rotation, color preset) always render; optional capability rows and hardware rows appear only when the underlying capability or backend exists.

| Row | Control | Visible when | Behavior |
|---|---|---|---|
| Mode / refresh | picker | always; disabled with `no modes reported` when `availableModes` is missing or empty | Options from `availableModes`, labelled `1920×1080 @ 60 Hz`; the current mode is prepended when absent. |
| Scale | picker | always | `0.5, 0.75, 1, 1.25, 1.5, 1.75, 2, 2.5, 3`; a non-standard current value is inserted and sorted. |
| Rotation | picker | always | Normal / 90° / 180° / 270°. |
| Bit depth | picker | `hdrCapable \|\| wideColor \|\| bitDepth === 10` | 8-bit / 10-bit; selecting an HDR preset forces 10-bit, and the row is locked while HDR is active. |
| VRR | picker | `vrrCapable` | Off / On / Fullscreen only. `hyprctl` reports runtime activation only, so the chosen value is session-local for display, applied only on an explicit VRR change, and not re-asserted by unrelated rules. |
| Color preset | picker | always | Auto / sRGB / DCI-P3 / Display P3 / Adobe RGB / EDID; `wide` only with `wideColor`; `HDR` and `HDR (EDID)` only with `hdrCapable`. |
| HDR brightness | range 1.0–2.0, step 0.05 | color preset is `hdr` / `hdredid` | Writes `sdrbrightness`. |
| HDR saturation | range 0.8–1.2, step 0.02 | color preset is `hdr` / `hdredid` | Writes `sdrsaturation`. |
| Brightness | range 1–100%, step 5 | any detected brightness backend | Backend label `backlight`, `ddc`, or `software` (gamma). |
| Color temperature | range 1000–10000 K, step 100 | a gamma leaf exists for the output | Per-output `wl-gammarelay-rs` software temperature; not a DDC control. |

Capability gates:

* **Mirrored output** (its `mirrorOf` resolves to another output): every compositor row — mode, scale, rotation, bit depth, VRR, color preset, HDR brightness, HDR saturation — is disabled with `mirrored — extend to configure`. Brightness and color temperature stay usable.
* **HDR active** (`cm` is `hdr` / `hdredid`): color temperature and a gamma-backed brightness row are disabled with `unavailable in HDR mode`; backlight and DDC brightness stay usable, and the two HDR rows appear. Bit depth is locked at 10-bit while HDR is active (no subline).
* Optional capability rows (bit depth, VRR, HDR brightness/saturation) and hardware rows are omitted when their capability or backend is absent; baseline compositor rows (mode, scale, rotation, color preset) always render and may be disabled with a reason such as `no modes reported`.

**Brightness precedence (per output):** kernel backlight → DDC/CI → gamma.

1. **`backlight`** — `/sys/class/backlight/*` is matched to the output by the resolved `device` basename (`card1-eDP-1` → `eDP-1`); `firmware` is preferred over `platform` over other types. Writes use `brightnessctl -d <device> set <percent>%` (logind, no root or udev changes).
2. **`ddc`** — `ddcutil detect` maps `Display N` to its DRM connector; VCP 10 is read with `getvcp 10 --terse` and written with `setvcp 10 <value>`. Failures are silent and fall through to gamma.
3. **`gamma`** — the per-output `wl-gammarelay-rs` `Brightness` property (`d`, 0–1), written as a percentage; the row labels this backend `software`.

**Color temperature:** the per-output `wl-gammarelay-rs` object at `/outputs/<normalized name>`, where non-alphanumerics in the output name become `_` (e.g. `/outputs/eDP_1`), property `Temperature` (`q`, Kelvin), read and written over `busctl`. Only the selected output's leaf is written. The well-known bus name is `rs.wl-gammarelay` (hyphen); the D-Bus interface is `rs.wl.gammarelay` (dot).

**Runtime-only:** settings are never persisted. There is no state file, `hyprland.lua` is never written, and nothing is reapplied when an output reconnects or Hyprland restarts. Compositor rows apply immediately through `hl.monitor` via `hyprctl eval` and re-assert every other active non-mirrored output's rule. A size-changing row (mode / scale / rotation) also re-places the output on its current side of its neighbour using the new logical size; with no neighbour its position is preserved. The anchored placement is kept only while the resized rectangle is collision-free: if it would overlap a farther output (e.g. the middle output of a three-output chain), the output is moved to the collision-free whole-layout slot instead. It may therefore lose adjacency rather than overlap another output; no other output is moved. Persistence remains a manual edit of `hyprland.lua`.

**`Esc` stack:** picker → settings → main → close. `Esc` dismisses the picker first, then returns to the main view, then closes the launcher. `h` cancels the picker, `l` applies the highlighted option, and `s` also returns from settings to main; `r` re-probes the hardware and refreshes `hyprctl monitors`.

## 4. Interaction

* `j/k` moves row focus (monitor rows → each available row's Extend/Duplicate options → refresh); `Enter` acts on the focused item (monitor row → disconnect, option → connect, refresh → refresh).
* `s` opens per-output settings for the focused monitor row.
* `H/J/K/L` place the selected monitor on the left/bottom/top/right edge of the layout (vim 2×2 picker).
* `/` filter by monitor name substring.
* `r` refreshes monitors (`hyprctl monitors -j` / `monitors all -j`); in settings it also re-probes the hardware backends.
* Settings view: `j/k` moves between rows; `l` opens the picker for enumerated rows; `h` is a no-op on an enumerated row and backs out of an open picker; `h/l` adjusts range rows; picker `j/k` moves, `l` applies, `h`/`Esc` cancels; `Enter`/`Esc` remain fallbacks; `s` returns to main.
* Mouse: a settings row click selects it; on enumerated rows a value click opens the picker, while on range rows it steps the value; the `−`/`+` arrows adjust; a picker option click applies it.
* Footers are view-specific and exact:
  * main: `main:     j/k move · s settings · H/J/K/L position · Enter act · r refresh · Esc close`
  * settings: `settings: j/k row · l open · h/l adjust · Esc back`
  * picker: `picker:   j/k option · l apply · h/Esc back`
* `Esc` backs out one level at a time: picker → settings → main → close.

## 5. Backend Notes

* Monitor listing is owned by `HyprService.qml` (single `Process` for both `monitors -j` and `monitors all -j`, event-driven via Hyprland `monitoradded` / `monitorremoved` / `configreloaded` with a 300 ms debounce). The launcher is a pure view over `HyprService.monitors` / `HyprService.availableMonitors` — no ad-hoc listing `Process`. `HyprService.monitors` entries carry numeric geometry (`x/y/w/h/scale/transform/id/mirrorOf`) so the launcher never parses display strings for math. **Enabled mirrors from `monitors all -j` are appended to `monitors`** because Hyprland 0.56 does not list mirroring outputs under `hyprctl monitors`; `availableMonitors` is therefore just the disabled outputs.
* **Mutation backend: `hyprctl eval`.** The Hyprland in use (0.56.x, Lua config via `hyprland.lua`) rejects `hyprctl keyword monitor` (`keyword can't work with non-legacy parsers. Use eval.`). All runtime mutations go through `hyprctl eval 'hl.monitor({...})'`, e.g. `hl.monitor({output="HDMI-A-1", disabled=false, mirror="", mode="1920x1080@60", position="1920x0", scale=1})`. `hl.monitor` rules merge per-field, so every emitted rule sets `disabled`/`mirror` explicitly. Re-applying rules can auto-shuffle outputs, so every mutation (place/extend/duplicate/disconnect) emits the target's rule **plus a preserving rule for every other active non-mirrored output**.
* **Settings hardware backend: `DisplaySettingsService.qml`.** It owns every settings `Process` — backlight read/write, gamma tree/read/write, DDC detect/read/write — one per operation, serialized per backend; the panel spawns none. Probing is lazy (on `s` and `r`), cached per session by the sorted output-name set, force-refreshed on each settings open and on `r`, and invalidated when that set changes. DDC and gamma failures are silent and fall through in precedence order. Writes are debounced (120 ms), keep only the latest pending value per output/field, and serialize through one `Process` per backend.
* **Gamma bus names.** `wl-gammarelay-rs` registers `rs.wl-gammarelay` (hyphen) as the well-known bus name but exposes the interface `rs.wl.gammarelay` (dot); calls use `busctl --user get-property|set-property` with those exact names. Per-output leaves are `/outputs/<normalized name>` where non-alphanumerics become `_` (e.g. `/outputs/eDP_1`).
* **Settings re-placement.** `HyprService.positionFor(idx, dir, size, anchorName)` accepts an optional `anchorName`; settings re-placement passes the resolved neighbour so a resized output stays beside it, while main-view `[L][R][T][B]` controls omit it and keep the all-output scan.
* **Runtime dependencies:** `brightnessctl` (backlight writes through logind), `ddcutil` (external VCP 10; requires `hardware.i2c.enable` and the `i2c` group), and `wl-gammarelay-rs` (per-output gamma brightness and color temperature, started from the Hyprland autostart block). See `SPECS.md` §2.2.
* Hyprland monitor config is **ephemeral** (runtime rules); it does not persist across restarts. That's correct — persistence belongs in `hyprland.lua` `hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "1" })` (already present). The launcher mutates **runtime** state only; users bake persistence by editing `hyprland.lua`. The settings view follows the same boundary: no state file, no `hyprland.lua` writes, and nothing reapplied on reconnect or restart.
* Alternative backends (`wlr-randr`, `kscreen-doctor`) are not required; `hyprctl` is sufficient. If `hyprctl` lacks a needed query (e.g., disconnected outputs), fall back to `hyprctl monitors all -j`.

## 6. Empty / Error States

* Single monitor only → 3.2 shows `"No additional outputs detected"` at `Theme.fgMuted`; position pickers hidden and `Disconnect` shown disabled with the last-monitor guard.
* `hyprctl` failure → inline error at `Theme.critical`; retry on `r`.
* Optional capability rows and hardware rows are omitted when their capability or backend is absent. Baseline compositor rows (mode, scale, rotation, color preset) always render and may be disabled with a reason (e.g. `no modes reported`).
* Resized output whose anchored placement would overlap a farther output → the output is moved to the collision-free whole-layout slot instead, so it may lose adjacency; other outputs are never moved or overlapped.
* Mirrored output → every compositor row is disabled with `mirrored — extend to configure`; brightness and color temperature remain usable.
* HDR active → color temperature and gamma-backed brightness are disabled with `unavailable in HDR mode`; backlight/DDC brightness and the HDR rows remain usable.
* `wl-gammarelay-rs` unreachable (no probed output exposes a temperature leaf) → the color-temperature row is hidden and a muted line reads `wl-gammarelay-rs not running — color temperature unavailable`; `r` retries.
* No brightness backend → the brightness row is hidden and a muted line reads `Brightness unavailable — no backlight or DDC/CI`. A `brightnessctl` or `ddcutil` failure degrades silently (next backend, then hidden row) — no error dialog.
* `availableModes` missing or empty → the mode row is rendered disabled with `no modes reported`; it cannot open the picker or write a rule.
* Settings output removed while open (including a `hyprctl` failure that empties the list) → the view returns to main, selection and picker state reset, and no stale descriptor is rendered.

## 7. Acceptance

* [ ] Current monitors show name, mode, scale, position, focused badge.
* [ ] Available outputs offer Extend / Duplicate; Extend is default.
* [ ] Per-monitor `[L][R][T][B]` picker / `H/J/K/L` places that output at the corresponding layout edge without shuffling other outputs; the assigned side is filled and captioned (`bottom of HDMI-A-1`).
* [ ] `j/k` reaches both Extend and Duplicate options for an available output; `Enter` activates the focused option.
* [ ] Row button toggles Extend ↔ Duplicate in place; a mirrored output stays visible in **Current**.
* [ ] Disconnect works for `n≥2` and is disabled for last monitor.
* [ ] `s` on a selected monitor opens settings; `s` returns to main and the `Esc` stack is picker → settings → main → close.
* [ ] Settings rows match reported capabilities — e.g. `eDP-1` without HDR/VRR/wide support shows only mode, scale, rotation, color preset, brightness, and color temperature.
* [ ] Mode/refresh, scale, and rotation apply through `hl.monitor` and appear in `hyprctl monitors -j`; a size change keeps the output edge-adjacent to its neighbour and other outputs keep their rules.
* [ ] Bit depth, VRR, and color preset apply; HDR forces 10-bit and reveals the HDR brightness/saturation rows.
* [ ] Brightness follows `backlight` → `ddc` → `gamma` per output and is labelled `backlight` / `ddc` / `software`.
* [ ] Color temperature writes only the selected output's `wl-gammarelay-rs` leaf.
* [ ] Mirrored and HDR gates show their exact reasons and keep hardware brightness usable.
* [ ] Backend failures degrade as documented in §6 — silent fallback, no error spam, no empty or stale rows.
* [ ] Runtime-only changes — no state file, `hyprland.lua` not mutated (settings included), and nothing reapplied on reconnect or restart.
* [ ] Vim nav + `/` filter + `r` refresh + `Esc` close work; `r` in settings re-probes the hardware.
* [ ] Uses `LauncherBase` + `Theme.*` tokens; the settings panel follows the same token and `Icons.*` rule.
