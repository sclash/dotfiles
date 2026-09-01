# Key-Launcher — Refined Spec

> Command: `SUPER+k` · File: `components/launchers/KeyLauncher.qml`

---

## 1. Purpose

Reference popup: a filterable table of all `SUPER+<key>` bindings. Read-only, keyboard-navigable. The single source of truth for "which key does what".

## 2. Window

* `LauncherBase.qml`: `width: 640`, `radius: Theme.roundingLauncher`, `maxHeight: 70vh` scrollable, `Esc` closes.
* No dispatch — this launcher **does not execute** bindings; it documents them.

## 3. Content — Table

* **Columns:** `Key` (left, `Theme.fg`, monospace-ish via `Theme.fontFamily`) | `Launcher / Action` (left) | `Description` (muted, optional).
* **Rows — normative bindings** (must match `SPECS.md:5.2` + `hyprland.lua`):

  | Key | Action | Notes |
  |---|---|---|
  | `SUPER+SPACE` | Control Center | meta-launcher |
  | `SUPER+r` | App Launcher | `elephant`/`walker` backend |
  | `SUPER+w` | Network-Center | Wifi |
  | `SUPER+b` | Bluetooth-Center | Bluetooth |
  | `SUPER+a` | Audio-Center | Audio |
  | `SUPER+d` | Display-Manager | monitors |
  | `SUPER+SHIFT+a` | Notification-Center | notifications |
  | `SUPER+q` | Shutdown-Launcher | power/plane |
  | `SUPER+k` | Key-Launcher | this popup |
  | `SUPER+p` | Toggle Perf Drawer | bar perf |
  | `SUPER+<number>` | Workspace switch | Hyprland dispatch |
  | `Alt+Shift` | Cycle keyboard layout | Hyprland `kb_options` |
  | `Esc` | Close launcher | global |

* **Source of truth:** bindings are **declared once** in `hyprland.lua` and **consumed** here. To avoid drift, the Key-Launcher should either:
  * (a) parse `hyprland.lua` / `hyprctl binds -j` at runtime to auto-populate, **or**
  * (b) import a shared QML `Bindings.qml` singleton that both `hyprland.lua` (via codegen) and `KeyLauncher` read.
  Minimal v1: **hard-code the table above** with a comment `// keep in sync with hyprland.lua binds`. The spec permits this, but builders must note the sync obligation.

## 4. Interaction

* `/` focuses filter `TextField` (`placeholder: "Filter keys…"`) — filters rows by key or action substring (case-insensitive).
* `j/k` or `Up/Down` moves row focus (no action on `Enter` — or `Enter` copies the key hint to clipboard via `wl-copy`, nice-to-have).
* `Esc` hierarchy: clear filter → close launcher.
* Scroll occupies remaining vertical space after the filter field.

## 5. Styling

* Header row: `font.pixelSize: Theme.fontSizeSmall; color: Theme.fgMuted; text: "KEY · ACTION"` uppercase.
* Key column: `color: Theme.accent` for the `SUPER+` prefix, `Theme.fg` for the key.
* Row hover: `Theme.bgHover`; focused: `Theme.bgSelected`.
* Separator line between header and rows at `Theme.border`.

## 6. Acceptance

* [ ] Shows every normative binding from the table above; values match `hyprland.lua`.
* [ ] `/` filter narrows rows substring-wise; `Esc` clears then closes.
* [ ] Vim `j/k` scrolls; no dispatch on `Enter` (read-only).
* [ ] Overflow scrolls within `70vh` card, not the whole screen.
* [ ] Drift risk documented (source-of-truth comment or shared singleton).
* [ ] Uses `LauncherBase` + `Theme.*` tokens.
