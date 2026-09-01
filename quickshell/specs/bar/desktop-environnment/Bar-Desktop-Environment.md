# Desktop Environment — Bar Left (Workspaces) — Refined Spec

> Parent: [`Bar.md`](../../bar/Bar.md) · Service: `Quickshell.Hyprland`

---

## 1. Purpose

Leftmost bar pill: indicates Hyprland workspaces as **dots**. Provides click-to-navigate and per-workspace app indicators when feasible. Anchors the bar's spatial model.

## 2. Display

* **Glyph:** `Icons.workspaceDot` (``) — Waybar `hyprland/workspaces.format: {icon}`.
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

## 3. Per-Workspace App Tray (Implemented)

> "If possible each desktop environment should have an associated app tray" (original spec).

* Inline to the **right of each dot**, a micro-row of app icons for windows on that workspace
  (`Hyprland.toplevels` filtered by `workspace.id`, via `components/bar/Workspaces.qml`).
* **Data source:** `Quickshell.Hyprland.toplevels` (`ObjectModel<HyprlandToplevel>`) — event-driven
  via `openwindow` / `closewindow` / `movewindowv2` / `windowtitlev2` IPC events. **No polling.**
* **Icon resolution:** `Quickshell.iconPath(toplevel.wayland.appId)`; fallback glyph `Icons.window`
  when the appId is empty (XWayland) or the theme has no icon.
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
* [x] Per-workspace app icons appear inline next to each dot, update live on open/close/move.
* [x] Icon click focuses the window (`focuswindow address:`); dot click switches workspace.
* [x] Fallback `Icons.window` glyph when no themed icon resolves.
* [ ] No hard-coded colours — all via `Theme.*`.
