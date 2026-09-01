# App-Launcher — Refined Spec

> Command: `SUPER+r` · File: `components/launchers/AppLauncher.qml` · Backend: `elephant` (or `walker`) already in autostart

---

## 1. Purpose

Center-screen fuzzy app launcher. Parity with current `SUPER+R → walker/elephant` behaviour, rendered natively in Quickshell instead of as an external window, with vim nav and consistent theming.

## 2. Window

* `LauncherBase.qml`: `width: 600`, `maxHeight: 60vh` scrollable, `radius: Theme.roundingLauncher`, `Esc` closes.
* **Focus:** on open, focus the `TextField` so typing immediately filters. `elephant`/`walker` backend may be invoked lazily.

## 3. Behaviour

### 3.1 Search

* **Input:** `TextField { placeholderText: "Search apps…"; focus: true }`.
* **Backend:**
  * Primary: `elephant` — already autostarted (`hyprland.lua:38`). Query via `Process { command: ["elephant","search", query] }` or its DBus/socket API if documented. Parse stdout (typically `name|exec|icon` per line).
  * Fallback: `walker` (previous `SUPER+R` backend) — same pattern: `walker --query "{query}"` or `walker --dmenu` mode. Support whichever is installed; probe at startup (`command -v elephant`).
  * If neither is available, degrade to `ls /usr/share/applications/*.desktop` + `DesktopEntry` parsing via `Quickshell.DesktopEntries` (built-in). This is the **always-available** fallback.
* **Debounce:** 120 ms after keystroke before issuing a new search.
* **Ranking:** backend ranking is used verbatim; no re-ranking in QML.

### 3.2 Results

* **List:** `ListView` with delegate rows: `icon` (from `DesktopEntry.icon` or backend-provided) + `name` (bold) + `exec`/`comment` (`Theme.fgMuted`, `fontSizeSmall`).
* **Ordering:** backend order. Highlight the `currentIndex` row at `Theme.bgActive`.
* **Empty state:** if query empty → show recent/frequent apps (backend's history) or a hint `"Type to search"` at `Theme.fgMuted`. If no results → `"No results for \"{query}\""`.
* **Icons:** `Image { source: Quickshell.iconPath(entry.icon, "application-x-executable") }` or `DesktopEntry.icon`. Size `20px`.

### 3.3 Launch

* `Enter` on focused row → `Process { command: ["gtk-launch", desktopId] }` or `command: entry.exec.split(" ")` with `Exec` field sanitised (strip `%U %F %u %f`). For `elephant` results that return a direct `exec`, use that.
* After launch, **close the launcher** (`LauncherBase.close()`).
* Optional: `Ctrl+Enter` to launch without closing (keeps launcher for successive launches) — nice-to-have.

## 4. Interaction

| Key | Action |
|---|---|
| `Esc` (filter focused) | clear filter; second `Esc` closes launcher |
| `j/k`, `Up/Down` | move selection |
| `Enter` | launch selected app + close |
| `Ctrl+Enter` | launch without closing (if implemented) |
| `Ctrl+u` | clear filter |
| Typing | filter (debounced) |

## 5. Error Handling

* Backend not installed → fall back to `DesktopEntries`; show inline hint `"elephant/walker not found — using desktop entries"` at `Theme.warning`.
* `Process` failure → keep existing results, show error at `Theme.critical` under the input, allow retry.
* Malformed `.desktop` `Exec` → skip entry, log.

## 6. Styling

* Input field: `radius: Theme.roundingItem`, `color: Theme.bgActive`, `border.color: Theme.accent` when focused.
* Result rows: `radius: Theme.roundingItem`, hover `Theme.bgHover`, selected `Theme.bgActive` + `border.color: Theme.accent`.
* Input + list share the card padding (`Theme.padM`).

## 7. Acceptance

* [ ] `SUPER+r` focuses the input; typing filters via `elephant`/`walker`/`DesktopEntries` fallback.
* [ ] Results show icon + name + exec/comment; vim `j/k` + `Enter` launches and closes.
* [ ] Debounce 120 ms, no blocking UI thread.
* [ ] Empty query shows recents/hint; no results shows correct message.
* [ ] Backend degradation chain works (elephant → walker → DesktopEntries).
* [ ] Uses `LauncherBase` + `Theme.*` tokens.

