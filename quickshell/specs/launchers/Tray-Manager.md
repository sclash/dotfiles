# Tray-Manager — Refined Spec

> Parent: [`SPECS.md`](../SPECS.md) · Service: `Quickshell.Services.SystemTray`
> Interaction contract: shared launcher chrome (Esc, vim nav, `/` filter, centered card).

---

## 1. Purpose

Center overlay (`SUPER+t`) that lists every app registered in the **system tray**
(`SystemTray.items` — the same StatusNotifierItems as the bar's tray) and exposes
each app's **SNI menu** (the same entries as right-clicking its bar icon) without
leaving the keyboard.

## 2. Display

* Single centered card, `LauncherBase`-class chrome: width `560`, `Theme.bgLauncher`,
  `Theme.borderActive` border, dim overlay behind, `Theme.roundingLauncher` radius.
* **Two views** in one card, switched in place:
  * **Apps view** (root): header `Tray Manager`; rows = tray apps — icon (`item.icon`,
    20px, same fallback glyph rule as `AppTray.qml`) + label (`tooltipTitle` or `id`).
  * **Options view**: breadcrumb header `<app label> › <submenu path>` (app name
    only at the menu root); rows = the focused app's menu entries — text, enabled,
    checkbox/radio indicator, submenu chevron (same row language as `TrayMenu.qml`).
* Row height 38 (apps) / 30 (options); selected row `Theme.bgSelected`, hover `Theme.bgBarAlt`.
* Footer hint: `enter open/trigger · l forward · h back · j/k navigate · / filter` at `Theme.fgDim`.
* **Selection visibility:** the `bgSelected` token is `#000000` on this theme, so
  keyboard selection renders as `Theme.bgBarAlt` row + `Theme.fgBright` medium-weight
  label — never invisible.

## 3. Behaviour

* **Apps view**
  * Rows source: `SystemTray.items.values` (event-driven; no polling).
  * `Enter` (or row left-click): `item.activate()` — open the app itself, same as
    left-clicking its bar icon; the manager stays open.
  * `l`/`Right` (or row right-click): open the **options view** for that app —
    same entries as right-clicking its bar icon; `!hasMenu` → `secondaryActivate()`.
* **Options view**
  * Rows source: `DBusMenuClient` (`components/launchers/DBusMenuClient.qml`) — a
    `busctl`-backed `org.canonical.dbusmenu` client. Required because quickshell
    0.3.0 cannot assign `DBusMenu` submenu handles to `QsMenuOpener.menu` (silent
    type-coercion failure → submenus rendered empty).
  * Entries carry `label`, `enabled`, `isSeparator`, `hasChildren`,
    `toggleType`/`toggleState`; `AboutToShow` is called before each `GetLayout`
    so lazy menus (libdbusmenu apps like nm-applet) populate; actions fire via
    the `Event` method with `clicked`.
  * Rendered in a content-sized list — **all options visible at once**, scrolling
    only past the ~360px cap.
  * `Enter` on entry: disabled/separator → no-op; submenu (`hasChildren`) →
    drill in via `menuHandle` stack (breadcrumb grows); otherwise `triggered()`
    → **return to apps view, manager stays open**.
  * `l`/`Right`: **forward only** — drill into a submenu, never triggers.
  * `h`/`Left`: **back** — pop a submenu level, or return to the apps list.
* Triggering an action or opening an app never closes the manager (multi-app
  workflow); the only close paths are `Esc` at root or clicking the dim overlay.
* **`h`/`l` are the standard back/forward at every level** of the manager:
  apps → options → suboptions (any depth) → back again.

## 4. Interaction

| Key | Context | Action |
|---|---|---|
| `j/k`, `Up/Down` | both views | move selection (real `currentIndex`, skips separators) |
| `Enter` | apps view | `item.activate()` — open the app (stays open) |
| `l`, `Right` | apps view | open options view (`!hasMenu` → `secondaryActivate()`) |
| `Enter` | options view | trigger entry / drill into submenu |
| `l`, `Right` | options view | **forward only** — drill into a submenu (never triggers) |
| `h`, `Left` | options view | **back** — pop submenu level / back to apps list |
| `/` | both views | focus filter `TextField` (substring, case-insensitive; apps: title/id, menu: entry text) |
| `Esc` | filter focused | clear filter, back to list |
| `Esc` | options view | pop submenu level / back to apps list |
| `Esc` | apps view | close manager |
| mouse | apps view | row left-click = open app; right-click = options view |
| mouse | options view | row click = trigger; dim overlay click = close |

**View transitions (STYLE.md §2.5):** apps/options swaps are animated — the
incoming view slides in (forward = from the right, back = from the left) while
the outgoing exits opposite, cross-faded over `Theme.durationNormal` OutCubic;
the card `height` animates to the incoming view's content height. Focus always
returns to the card after any transition — key handling lives there, never on
the lists.

## 5. Error Handling

* No tray items → empty-state hint `"no tray apps registered"` at `Theme.fgMuted`.
* Menu missing/unloadable (`DBusMenuClient` resolves nothing) → hint row
  `"no options available"` at `Theme.fgMuted`; while fetching → `"loading menu…"`;
  `Esc` still returns.
* Menu entries arriving async never resize the card below its minimum; rows are
  plain delegates (no `Loader` required-property pitfalls).
* Stale selection (tray item vanishes while open) → snap back to apps view.

## 6. Styling

* Tokens only — `Theme.bgLauncher` card, `Theme.border`/`Theme.borderActive` hairlines,
  `Theme.fg`/`Theme.fgMuted`/`Theme.fgDim` text, `Theme.bgSelected` selection,
  `Theme.roundingLauncher` card, `Theme.fontFamily`, spacing per `STYLE.md` §2.
* Icons/glyphs via `Icons.*` (submenu chevron, fallback glyph). No hard-coded hex/glyphs.

## 7. Registration

* IPC name: `tray` (`launcher toggle tray`, `launcher open tray`, …) — wired in
  `shell.qml` `closeAllExcept`/`toggle`/`close`/`open`.
* Bind: `SUPER+t` in `hyprland.conf` + `hyprland.lua` (`hl.bind(mainMod .. " + T", …)`),
  mirrored in `KeyLauncher.qml` + `Key-Launcher.md` tables (sync obligation).
* Control Center: entry `10 — Tray` dispatching `launcher.toggle("tray")`.

## 8. Acceptance

* [ ] `SUPER+t` opens/closes; only one launcher visible at a time (`closeAllExcept`).
* [ ] Apps list matches bar tray; icons + labels render; empty state when none.
* [ ] `/` filters both views; `j/k` moves a visible selection; `Enter` opens the focused app.
* [ ] `l` shows the app's options in a list that displays all entries at once
      (scroll only past the height cap); triggering returns to apps view, still open.
* [ ] Submenus drill in and out (`l`/`Enter` in, `h`/`Esc` out); `Esc` at root closes.
* [ ] `h`/`l` keep working across any number of enter/back cycles (focus returns
      to the card after every transition).
* [ ] View swaps animate per STYLE.md §2.5 — directional slide + cross-fade,
      card height animates; no cut.
* [ ] `Tokens only` audit passes (no hex/glyphs outside `theme/`).
