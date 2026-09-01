# App-Tray — Bar Left — Refined Spec

> Parent: [`Bar.md`](../../bar/Bar.md) · Service: `Quickshell.Services.SystemTray`

---

## 1. Purpose

Left pill, **immediately to the right of Workspaces**, shows `StatusNotifierItem` icons for
apps that register a tray item (e.g., **Flameshot**, network applets, media players). These are
apps "common to all desktop environments" — i.e., not tied to a single workspace.

## 2. Display

* **Source:** `Quickshell.Services.SystemTray.items` — list of `SystemTrayItem`.
* **Layout:** horizontal `RowLayout` with `spacing: 12`, `icon-size: 12` — Waybar `tray: { icon-size: 12, spacing: 12 }` parity.
* **Each item:**
  * `Image { source: item.icon; width: 12; height: 12; smooth: true }` (or `IconImage` if provided by Quickshell).
  * `MouseArea { onClicked: item.activate(); onPressAndHold / rightClicked: item.secondaryActivate() /* context menu */ }`.
  * Tooltip: `item.tooltipTitle` / `item.tooltipDescription` on hover.
* **Overflow:** if more than ~6 icons, collapse extras into a `…` affordance that expands on click. Minimal v1 may simply show all without collapse.
* **Empty state:** if `SystemTray.items.length === 0`, render nothing (no placeholder). The left pill shrinks to just Workspaces.

## 3. Interaction

| Action | Effect |
|---|---|
| Left click | `item.activate()` — app-defined (often opens the app) |
| Right click | `item.secondaryActivate()` or `item.display(window, x, y)` — context menu |
| Hover | tooltip |

No keyboard binding; tray is mouse/touch affordance within a keyboard-driven bar. Optional: `SUPER+t` could focus the tray row for keyboard activation — nice-to-have.

## 4. Distinction from Workspaces

* **Workspaces** = Hyprland desktops (dots). Workspace-local app icons (if implemented) are `Hyprland.toplevels` filtered per workspace — those are *window* indicators.
* **App-Tray** = `SystemTray` items — these are *background services* with tray icons (Flameshot, etc.). Do not conflate the two. The spec's "common to all desktop environment" phrase maps to `SystemTray`, not to per-workspace toplevels.

## 5. Error Handling

* `SystemTray` unavailable (no `StatusNotifierWatcher` on session bus) → render nothing, no error. This is a valid headless state.
* Item icon fails to load → fallback to `Icons.warning` (``) at `Theme.fgDim`.

## 6. Acceptance

* [ ] Flameshot (or any `StatusNotifierItem` app) appears as a 12px icon with correct spacing.
* [ ] Left/right click dispatch to the item's actions.
* [ ] Empty `SystemTray` renders no placeholder.
* [ ] No confusion with workspace window indicators — tray icons are service-level.
