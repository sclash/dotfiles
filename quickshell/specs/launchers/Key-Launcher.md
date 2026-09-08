# Key-Launcher — Refined Spec

> Command: `SUPER+/` · File: `components/launchers/KeyLauncher.qml`

---

## 1. Purpose

Reference popup: a **sectioned**, filterable table of keybindings grouped by config source — Shell (quickshell launchers), Hyprland, Ghostty, Tmux, Herdr. Read-only, keyboard-navigable, sections seamlessly navigable. The single source of truth for "which key does what, where".

## 2. Window

* `LauncherBase.qml`: `width: 640`, `radius: Theme.roundingLauncher`, card grows with rows, list capped ~430 px scrollable (`70vh` max card), `Esc` closes.
* No dispatch — this launcher **does not execute** bindings; it documents them.

## 3. Content — Sectioned Table

* **Sections (normative order):** `Shell` · `Hyprland` · `Ghostty` · `Tmux` · `Herdr`, rendered as a pill tab bar under the header (numbered `1..5`).
* **Columns:** `Key` (left, `Theme.fg`) | `Action` (left) | `Description` (muted) — in filter mode the third column becomes the row's `Section` (muted, italic).
* **Sources of truth (keep in sync):**

  | Section | Source file | Notes |
  |---|---|---|
  | Shell | `hyprland.lua` quickshell-launcher binds + `shell.qml` IpcHandler | launcher toggles only; `SUPER+c` → Calendar-Launcher |
  | Hyprland | `hypr/hyprland.lua` | `SUPER+SHIFT+c` → Close active window (`killactive`); window/workspace/group/submap/multimedia binds; `kb_options grp:alt_shift_toggle` |
  | Ghostty | `ghostty/config` `keybind =` lines only | un-commented binds |
  | Tmux | `~/.config/tmux/tmux.conf` (+ sensible defaults) | `prefix = C-b`; `v/C-v/y` in copy-mode-vi; `alt+*` root binds |
  | Herdr | `~/.config/herdr/config.toml` `[keys]` | `prefix = ctrl+b` |

* Minimal v1: hard-code each section's table in `KeyLauncher.qml` with a `// keep in sync with:` comment block. Spec permits this; builders must note the sync obligation per section.

## 4. Interaction

* **Section navigation (seamless):**
  * `Tab` / `Shift+Tab` cycles sections forward/backward (wraps).
  * `←` / `→` also cycle sections.
  * `1..5` jumps directly to the numbered section.
  * Clicking a pill switches sections (mouse optional, keyboard-first).
* `/` focuses filter `TextField` (`placeholder: "Filter keys…"`) — filters **across all sections** by key/action substring (case-insensitive); a section name match shows that whole section. Matched rows show their section in the third column. Clearing the query returns to the current section.
* `j/k` or `Up/Down` scrolls rows (no action on `Enter` — read-only).
* `Esc` hierarchy: clear filter → close launcher.
* List occupies remaining vertical space after the tab bar/filter field; card height adapts to section row count (min ~240 px, max ~430 px list).

## 5. Styling

* Section pills: `radius: Theme.roundingItem`; active — `bg: Theme.bgBarAlt`, `border: Theme.borderActive`, text `Theme.fg`; inactive — transparent, text `Theme.fgMuted`; leading number `Theme.fgDim`.
* Header row: `font.pixelSize: Theme.fontSizeSmall; color: Theme.fgMuted; text: "KEY · ACTION"` uppercase.
* Key column: `color: Theme.fg`; description/section column: `Theme.fgMuted` (section tag: `Theme.fgDim` italic in filter mode).
* Footer: keyboard hints (left, `Theme.fgDim`) + sync note listing source files (right, `Theme.fgDim` italic).
* Separator line between header and rows at `Theme.border`.

## 6. Acceptance

* [ ] Shows all five sections; each section's rows match its source file (`hyprland.lua`, `ghostty/config`, `tmux.conf`, `herdr/config.toml`).
* [ ] `Tab`/`Shift+Tab`, `←/→` cycle sections; `1..5` jumps; active pill visibly highlighted.
* [ ] `/` filter narrows rows across all sections and shows section per row; `Esc` clears then closes.
* [ ] Vim `j/k` scrolls; no dispatch on `Enter` (read-only).
* [ ] Overflow scrolls within the card, not the whole screen; card adapts to section size.
* [ ] Drift risk documented per section (source-of-truth comment block).
* [ ] Uses `Theme.*` tokens — no hard-coded hex/glyphs.
