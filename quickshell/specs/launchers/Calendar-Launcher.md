# Calendar-Launcher — Refined Spec

> Command: `SUPER+C` · File: `components/launchers/CalendarLauncher.qml`
> Bar entry: date text in the center pill (`bar/Date.md`)

---

## 1. Purpose

Lightweight, keyboard-driven month calendar. Read-only date browser with fast
vim-granularity jumps (day / week / month / year). No backend, no polling —
pure QML `Date` math. The only process spawned is `wl-copy` on `Enter`.

## 2. Window

* Centered card: `width: 480`, content-driven height capped at `560`
  (`radius: Theme.roundingLauncher`, `Esc` closes, overlay click closes).
* 480 px (not the usual 560–640) is normative: a 7-column grid stays dense
  and legible at 480; wider cards leave dead space.
* **Focus:** on open, focus the card (`mainCol.forceActiveFocus()`); the
  cursor resets to today on every open.

## 3. Behaviour

### 3.1 State

* `cursorYear / cursorMonth / cursorDay` — the vim cursor. The visible month
  **is** the cursor's month (single source; no separate view state).
* `todayYear / todayMonth / todayDay` — refreshed on open plus a 30 s `Timer`
  (only `running` while open) so the today highlight survives midnight.
* `copyNote: string` — transient `Enter` feedback, cleared after 1.5 s.

### 3.2 Grid

* Weekday header `Mo Tu We Th Fr Sa Su` (Monday-first), muted 10 px.
* 42-cell grid (`cellAt(i)`): Monday-first offset
  `(new Date(y, m, 1).getDay() + 6) % 7`, leading/trailing days from adjacent
  months rendered at `Theme.fgDim` and clickable (jump moves cursor + view).
* Header: `«` year−1 · `Icons.chevronLeft` month−1 · `MMMM yyyy` title
  (click = go to today) · `Icons.chevronRight` month+1 · `»` year+1.
  `«`/`»` are typographic text, not Nerd glyphs.
* Sub-header: `"ddd MMM dd, yyyy  ·  yyyy-MM-dd"` of the cursor (`Theme.fgMuted`).
* Day clamp on month/year jumps (Jan 31 → Feb 28/29); leap years via
  `new Date(y, m + 1, 0).getDate()`.
* Mouse wheel over the grid: up = previous month, down = next month.

### 3.3 Copy

* `Enter` runs `printf '%s' '<iso>' | wl-copy` (ISO is digits + dashes only,
  no shell-escaping risk) and shows `"Copied yyyy-MM-dd"` in the footer for
  1.5 s. Launcher stays open.

## 4. Interaction

| Key | Action |
|---|---|
| `h/l` or `Left/Right` | ∓/± 1 day |
| `j/k` or `Down/Up` | ± 1 week (±7 days) |
| `H/L` (`Shift+h/l`) | ∓/± 1 month (day clamped) |
| `J/K` (`Shift+j/k`) | ∓/± 1 year (Feb 29 → 28) |
| `PgUp/PgDn` | ∓/± 1 month (`Shift` = year, for non-vim users) |
| `Home/End` | first / last day of cursor month |
| `t`/`T` | go to today |
| `Enter` | copy cursor ISO date via `wl-copy` (stay open) |
| `Esc`, overlay click | close |

## 5. Service Contract

* None. Time comes from local `new Date()` — no service, no polling
  (except the 30 s today-refresh `Timer` while open).

## 6. Error Handling

* `wl-copy` missing → copy silently no-ops (note still shows; check journal).
  Never blocks navigation.
* Locale missing month names → `Qt.formatDateTime` falls back to numeric
  `yyyy-MM` (same degraded rule as `bar/Date.md` §6).

## 7. Styling

* Header `Text { text: "Calendar"; … }` uppercase + `Theme.border` divider
  (standard card anatomy, `STYLE.md` §5.2).
* Cells `40px` high, `radius: Theme.roundingItem`, bg `transparent`
  (all bg tokens are `#000000`): selected → `borderSelected` 2 px;
  today (not selected) → `border.color: Theme.accent` 1 px + `Theme.accent`
  bold numerals; out-of-month → `Theme.fgDim`.
* Footer hints 10 px `Theme.fgDim`, copy confirmation in `Theme.accent`.
* Icon: `Icons.calendar` (``) — used by Control-Center tile only; the card
  itself is typographic (no icon in header).

## 8. Acceptance

* [ ] `SUPER+C` and clicking the bar date text both toggle the launcher.
* [ ] Opens on the current month with today selected; `t` returns from any distance.
* [ ] `h/l` day, `j/k` week, `H/L` month, `J/K` year all move the cursor and view together.
* [ ] Month edges clamp (Jan 31 + 1 month = Feb 28/29); leap years correct.
* [ ] `Enter` copies `yyyy-MM-dd` (verify with `wl-paste`) and shows confirmation.
* [ ] `Esc` / overlay click closes; bell click still opens Notification-Center.
* [ ] No `Process` except `wl-copy` on `Enter`; idle cost zero.
* [ ] Uses `Theme.*` / `Icons.*` tokens (month chevrons via `Icons.chevronLeft/Right`).
