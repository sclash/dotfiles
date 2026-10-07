# Desktop Environment — Bar Left (Workspaces) — Refined Spec

> Parent: [`Bar.md`](../../bar/Bar.md) · Service: `Quickshell.Hyprland`

---

## 1. Purpose

Leftmost bar pill: indicates Hyprland workspaces as **dots**. Provides click-to-navigate and per-workspace app indicators when feasible. Anchors the bar's spatial model.

## 2. Display

* **Glyph:** `Icons.workspaceDot` (``) — Waybar `hyprland/workspaces.format: {icon}`. Replaced by numerals when multiple monitors are connected (§2.1).
* **States:**

  | State | Colour | Notes |
  |---|---|---|
  | **Active** | `Theme.fg` (`#ffffff`) | `text-shadow: 0 0 2px rgba(0,0,0,0.5)` (Waybar `#workspaces button.active`) |
  | **Inactive, occupied** | `Theme.fgDim` (`rgba(89,89,89,0.67)`) | |
  | **Empty, persistent** | `Theme.fgDim` at same opacity | still rendered if `persistent-workspaces` |
  | **Hover** | `rgba(0,0,0,0)` with glow `text-shadow` | Waybar `button:hover` semantics — replicated as `Theme.fg` brightening |

* **Ordering:** strictly numeric ascending (Waybar `persistent-workspaces: {"*":[1]}` ensures at least workspace 1 exists; this spec extends to **at least 3 dots** always).
* **Count rule (normative):**

  ```
  let n = max(3, maxOccupiedId, focusedId)
  // if workspaces 1,2,4 are occupied and 3 is empty, show 1..4 (4 dots)
  // if only 1,2 occupied, show 1..3 (3 dots)
  // if 1..5 occupied, show 1..6 (one extra empty dot as affordance)
  ```
  In other words: **at least 3 dots; if exactly k are occupied, show k+1 up to the max id; never show fewer than the highest id.**
* **Per-dot interaction:** `MouseArea { onClicked: Hyprland.dispatch("workspace " + id) }`.
* **Font size:** `10px` equivalent (Waybar workspace buttons use `padding: 0 5px` with dot glyph ~10px). Use `font.pixelSize: 10` for the dot, with `spacing: Theme.gapS` between dots.

### 2.1 Monitor grouping (external-display UX)

> Makes it obvious which workspaces belong to an external display.

* Workspaces are grouped **per monitor**, ordered by each monitor's lowest
  workspace id ascending, so the numerals read left-to-right (panels/workspace
  1 first). Monitors without workspaces fall back to physical position
  (`Hyprland.monitors` sorted by `x`, then `y`).
* Each group is prefixed by a micro-label: `Icons.laptop` for built-in
  (`eDP*`/`DSI*`) + monitor name (`eDP-1`), `Icons.display` for external
  (`HDMI-A-1`), at `Theme.fontSizeSmall`; label colour `Theme.fgMuted` on the
  bar's own screen, `Theme.fgDim` otherwise. Tooltip names the display kind
  (built-in/external) and the monitor `description`.
* Groups are separated by a 1 px `Theme.border` divider.
* **Slots switch from glyph to numeral when > 1 monitor is connected:**
  `text: String(workspaceId)` instead of `Icons.workspaceDot` (focused:
  13 px + `Theme.fontWeightMedium`; others 12 px; slot widens 20 → 22 px).
  Identifies the workspace inside each monitor group — the dot alone carries
  no identity. Single-monitor setups keep the plain dot glyph.
* Labels and dividers render **only when more than one monitor is connected**;
  single-monitor setups keep the plain dot row.
* Groups not matching the bar's `screenName` (passed from `Bar.qml`,
  `barWin.screen.name`) render at `opacity: 0.55` — other-screen workspaces
  remain visible and clickable but clearly secondary.
* Dot colours: focused `Theme.fg`; active on another monitor (`ws.active`)
  `Theme.fg` @ 0.85; occupied inactive `Theme.fgDim` @ 0.85; synthetic /
  empty `Theme.fgDim` @ 0.55. Dot size: 10 px focused, 9 px active, 8 px rest.
* Synthetic dots (no `HyprlandWorkspace` yet) live in the **focused monitor's
  group** — the monitor where `workspace <id>` creates them; the >= 3 dots
  rule and the create-workspace affordance are unchanged in count, only their
  group placement follows focus. Slots sort numerically inside a group, so a
  gap-filling create slot sits at its number position (e.g. `3 4`).

## 3. Per-Workspace App Tray (Implemented)

> "If possible each desktop environment should have an associated app tray" (original spec).

* Inline to the **right of each dot**, a micro-row of app icons for windows on that workspace
  (`Hyprland.toplevels` filtered by `workspace.id`, via `components/bar/Workspaces.qml`).
* **Data source:** `Quickshell.Hyprland.toplevels` (`ObjectModel<HyprlandToplevel>`) — event-driven
  via `openwindow` / `closewindow` / `movewindowv2` / `windowtitlev2` IPC events. **No polling.**
* **Icon resolution:** `Icons.appIconFor(appId, wmClass)` (see `theme/Icons.qml`). A window's
  appId and its icon-theme name are different namespaces and frequently disagree, so a bare
  `Quickshell.iconPath(appId)` is not sufficient — that call always returns a non-empty
  `image://icon/<name>` url and its provider paints a placeholder tile rather than failing,
  so no `Image` ever errors and no fallback can trigger. Resolution order:
  1. `Icons.appIconOverride(appId)` — bundled SVG overrides.
  2. Desktop-entry `StartupWMClass` match → its `Icon=` (`"Tor Browser"`→`tor-browser`,
     `"ZenNotes"`→`zennotes-desktop`). Built once from `Quickshell.DesktopEntries.applications`.
  3. `Quickshell.hasThemeIcon(appId)`, then a lowercased/punctuation-dashed variant
     (`"Tor Browser"`→`tor-browser`).
  4. `""` → fallback glyph `Icons.window`.
  Every theme lookup goes through `Quickshell.iconPath(name, true)` so a miss yields `""`.
  `wmClass` (`toplevel.lastIpcObject["class"]`) is supplied for XWayland windows, which expose
  no wayland handle and therefore no appId.
* **States:** activated window icon at full opacity (`toplevel.activated`), others at 0.55;
  hover shows `Theme.bgHover` wash + tooltip with the window title.
* **Overflow:** max `Theme.wsAppIconMax` (3) icons per workspace; extra windows collapse into a `+n` count.
* **Interaction:** click icon → `Hyprland.dispatch("focuswindow address:<address>")` (focus follows,
  workspace switches if needed); click dot → switch workspace (unchanged).

## 4. Data Source

* `Quickshell.Hyprland.workspaces` (list of `HyprlandWorkspace { id, name, focused, active }`)
* `Quickshell.Hyprland.focusedWorkspace` for active highlight.
* Event-driven — no polling. `Hyprland` singleton emits `workspacesChanged`, `focusedWorkspaceChanged`.

## 5. Error Handling

* Hyprland IPC disconnected → dots dimmed, tooltip "Hyprland unavailable". Retries via `Hyprland` reconnect timer (Quickshell handles internally).
* Workspaces list empty at startup → render 3 dim dots as placeholder.

## 6. Acceptance

* [ ] At least 3 dots always; extra dot appears when k workspaces are occupied.
* [ ] Active workspace is white; others are `Theme.fgDim`.
* [ ] Clicking a dot dispatches `hyprctl dispatch workspace <id>` and focus follows.
* [ ] No polling; updates are event-driven via `Quickshell.Hyprland`.
* [ ] With > 1 monitor: per-monitor labels (laptop/monitor glyph + name) and
      `Theme.border` dividers; other-screen groups dimmed (opacity 0.55).
* [ ] With > 1 monitor: slots show workspace numbers (not dots); with a single
      monitor the dot glyph is used.
* [ ] Monitor groups are ordered by lowest workspace number ascending, and
      slots sort numerically within each group.
* [ ] Label/dot tooltip names the monitor; external displays read "external".
* [ ] With a single monitor: no labels/dividers — unchanged flat dot row.
* [x] Per-workspace app icons appear inline next to each dot, update live on open/close/move.
* [x] Icon click focuses the window (`focuswindow address:`); dot click switches workspace.
* [x] Fallback `Icons.window` glyph when no themed icon resolves — no placeholder tile.
* [ ] An app whose appId differs from its icon name (Tor Browser, ZenNotes) still renders its
      real icon, via the `StartupWMClass` desktop-entry lookup.
* [ ] No hard-coded colours — all via `Theme.*`.
