# Date — Bar Center — Refined Spec

> Parent: [`Bar.md`](./Bar.md) · Tryout already implemented in `Bar.qml`

---

## 1. Purpose

Center pill: the primary temporal anchor and the entry point to `Notification-Center`.

## 2. Display

* **Format:** `"Mon Aug 31, 21:14:52"` — locale weekday abbrev, month abbrev,
  day zero-padded, 24h time (`%a %b %d, %H:%M:%S`).
* Waybar parity (`config.jsonc:45-57`):
  ```json
  "clock": { "format": "{:%a | %d-%m-%Y | %H:%M:%S} " }
  ```
  This spec uses the friendlier prose format `"Mon Aug 31, 21:14:52"` (as in the
  original `Date.md`), keeping `|` separators as an alternative. **Normative:**
  implement `"%a %b %d, %H:%M:%S"` and offer a toggle to Waybar's `"%a | %d-%m-%Y | %H:%M:%S"` via `Theme.dateFormat` if needed. The default shown to the user is the prose form.
* **Implementation:** do **not** spawn `date` every second (current `Bar.qml:27-50` does). Replace with Qt's `Qt.formatDateTime(new Date(), "ddd MMM dd, hh:mm:ss")` inside a `Timer { interval: 1000 }` — zero process cost. Keep the `Process` path only as a fallback if `Qt.formatDateTime` locale differs.
* **Font:** `Theme.fontFamily`, `Theme.fontSizeBar:14`, `Theme.fg`.

## 3. Notification Bell

* **Icon:** `Icons.notification` (``) immediately to the **right** of the date text, padded `Theme.padS`.
* **State:**

  | Notification state | Bell |
  |---|---|
  | Idle, no unread | `` at `Theme.fg` |
  | Unread notifications | `` at `Theme.accent` + optional count badge (`•` or number ≤9, `9+` beyond) |
  | **Silenced / DND** | `` with a strike or distinct muted glyph (e.g., `` at `Theme.fgDim` + `󰂛` overlay) + tooltip "Notifications silenced" |
* **Tooltip (date):** calendar (`<tt>{calendar}</tt>` parity) — Waybar `tooltip-format` shows a mini calendar with today `span color='#fAfBfC'`. Replicate with a `Popup` containing a lightweight month grid or a `Process { command: ["cal"] }` fallback. Minimal v1: show `cal` output on hover; richer grid is optional.
* **Click:** anywhere on the center pill (date + bell) → `launcher.toggle("notification")` (`SUPER+SHIFT+a`).
* **Right-click (optional):** toggle DND/silence (`NotifService.toggleDnd()`).

## 4. Interaction Summary

| Action | Effect |
|---|---|
| `Timer` tick (1s) | update displayed time |
| Click center pill | open `Notification-Center` |
| Right-click (opt) | toggle silence/DND |
| `SUPER+SHIFT+a` | same as click (Hyprland bind) |

## 5. Service Contract

* **Time:** local `Timer` + `Date` — no service.
* **Notifications:** `NotifService.qml` (`Quickshell.Services.Notifications`) —
  properties `hasUnread: bool`, `unreadCount: int`, `dnd: bool`.

## 6. Error Handling

* `NotifService` unavailable → bell stays `` at `Theme.fg`, no badge, tooltip "Notifications unavailable".
* Locale missing weekday names → fallback to ISO `YYYY-MM-DD hh:mm:ss`.

## 7. Acceptance

* [ ] Renders `"Mon Aug 31, 21:14:52"` updating every second with no `Process` spawn.
* [ ] Bell shows correct states: idle / unread / silenced with badge/overlay.
* [ ] Click and `SUPER+SHIFT+a` both open `Notification-Center`.
* [ ] Hover shows calendar tooltip (at least `cal` output).
* [ ] Silenced state is visually distinct.
