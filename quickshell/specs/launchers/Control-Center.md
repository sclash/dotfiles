# Control-Center — Refined Spec

> Command: `SUPER+SPACE` · File: `components/launchers/ControlCenter.qml` extends `LauncherBase.qml`

---

## 1. Purpose

Meta-launcher: a single entry point that **lists and dispatches to every other launcher**. A keyboard-driven command palette for the shell.

## 2. Layout — `LauncherBase` + grid

* **Base:** centered card (`LauncherBase.qml`) — `width: 600`, `radius: Theme.roundingLauncher`, `color: Theme.bgLauncher`, `border: Theme.borderActive`, shadow `range: 12`.
* **Header:** `Text { text: "Control Center"; font.pixelSize: Theme.fontSizeSmall; color: Theme.fgMuted }` + `Icons.search` filter field (`placeholder: "Type to filter…"`, focus on open, `vim` nav in list, `Esc` closes).
* **Body:** grid or list of launcher entries. Recommended: **2-column grid** of cards (icon + label + key hint).

## 3. Entries (normative, in this order)

| # | Launcher | Key hint | Icon | Dispatch |
|---|---|---|---|---|
| 1 | Network | `SUPER+w` | `` / `` | `launcher.toggle("network")` — close self, open `NetworkCenter` |
| 2 | Bluetooth | `SUPER+b` | `󰂯` | `launcher.toggle("bluetooth")` |
| 3 | Audio | `SUPER+a` | `` | `launcher.toggle("audio")` |
| 4 | Display | `SUPER+d` | `󰍹` | `launcher.toggle("display")` |
| 5 | Notifications | `SUPER+SHIFT+a` | `` | `launcher.toggle("notification")` |
| 6 | App Launcher | `SUPER+r` | `` | `launcher.toggle("app")` |
| 7 | Shutdown | `SUPER+q` | `` | `launcher.toggle("shutdown")` |
| 8 | Key Hints | `SUPER+k` | `` | `launcher.toggle("keys")` |

> The Control Center **does not duplicate** launcher UIs inside itself — it dispatches to them. Selecting an entry closes Control Center and opens that launcher (replace, don't stack).

## 4. Interaction

* **Open:** `SUPER+SPACE` (`hyprctl` → `quickshell ipc call launcher toggle control`).
* **Filter:** typing filters entries by label or key hint (fuzzy, case-insensitive). `j/k` or `Up/Down` moves selection; `Enter` dispatches; `Esc` closes.
* **Direct key:** pressing the target launcher's bound key while Control Center is open may either dispatch immediately or just filter — implement **dispatch on Enter only** for consistency; key hints are informational.
* **Close:** `Esc`, clicking outside the card, or dispatching.

## 5. Styling

* Selected row: `Theme.bgSelected` + `border.color: Theme.borderSelected` focus ring.
* Key hints right-aligned in `Theme.fgMuted`, `font.pixelSize: Theme.fontSizeSmall`.
* Icons at `Theme.fontSizeLauncher:13` in `Theme.fg`.

## 6. Acceptance

* [ ] Lists all 8 launchers with correct icons + key hints.
* [ ] Fuzzy filter + vim nav + `Enter` dispatch works; `Esc` closes.
* [ ] Dispatching closes self and opens the target launcher (no stacking).
* [ ] `SUPER+SPACE` toggles open/close.
* [ ] Uses `LauncherBase` + `Theme.*` tokens.
