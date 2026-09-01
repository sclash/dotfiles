# Notification-Center — Refined Spec

> Command: `SUPER+SHIFT+a` · File: `components/launchers/NotificationCenter.qml` · Service: `NotifService.qml` (`Quickshell.Services.Notifications`)

---

## 1. Purpose

Exclusive notification surface: replaces `swaync`/`mako` popups. Shows recent notifications, allows clear and silence. The `Date` bell reflects its state.

## 2. Window

* `LauncherBase.qml`: `width: 600`, `radius: Theme.roundingLauncher`, `maxHeight: 70vh` (scrollable list), `Esc` closes.
* **Placement:** center-screen card (not a side drawer) — consistent with other launchers per `SPECS.md:5.2`.

## 3. Behaviour

### 3.1 Display

* **Default view:** 3 most recent notifications, newest at top. Each card:
  * `appName` / `appIcon` (left), `summary` (bold), `body` (up to 3 lines, elide), `timestamp` (`Theme.fgMuted`, `fontSizeSmall`), optional `image` thumbnail.
  * `urgency` tint: `low` none, `normal` `Theme.fg`, `critical` left border `Theme.critical`.
  * Actions: notification-provided `actions` buttons ("Open", "Dismiss") if present; otherwise generic `Dismiss` per card.
* **Pagination:** `Show older…` button or `j/k` scroll loads up to `historyLimit` (default 50) from `NotifService.history`. Minimal v1 may render all retained notifications with a `ScrollView`.
* **Empty state:** `"No notifications"` at `Theme.fgMuted` with `Icons.notification` glyph.

### 3.2 Exclusivity

* This center is the **only** on-screen notification UI. The daemon `Quickshell.Services.Notifications` must **suppress** the default popup layer — notifications appear only here and as a bell badge.
* Optional transient toasts are allowed only if they auto-dismiss ≤3s **and** the notification is still recorded in the center; otherwise no toasts.

### 3.3 DND / Silence

* **Silence toggle:** `Silence` / `Unsilence` button at top (or `Ctrl+s`). When `NotifService.dnd === true`:
  * Bell in `Date` switches to silenced state (see `Date.md:3`).
  * New notifications still accumulate in `history` but do not badge the bell as unread (or badge dimmed).
* Toggle binds to `NotifService.dnd = !NotifService.dnd`. Persist via `JsonCache` or `gsettings` if desired (optional).

### 3.4 Clear

* **Clear all:** button at top, `Ctrl+k`, or `c` — calls `NotifService.clearHistory()` / dismisses each `Notification`.
* **Dismiss one:** per-card `Dismiss` or `d` when focused; `j/k` to focus, `Enter` to invoke primary action if any.

## 4. Interaction

| Key | Action |
|---|---|
| `Esc` | close launcher |
| `j/k`, `Up/Down` | move card focus |
| `d` | dismiss focused card |
| `c` / `Ctrl+k` | clear all |
| `Ctrl+s` | toggle silence/DND |
| `/` | filter by app/summary/body substring |
| `Enter` | invoke notification's primary action (if any), else dismiss |
| `Shift+J/K` or `PageDown/Up` | load older / newer page |

## 5. Service Contract — `NotifService.qml`

```qml
QtObject {
  property bool dnd
  property int unreadCount
  property list<Notification> history  // from Quickshell.Services.Notifications
  function clearHistory(): void
  function dismiss(id: int): void
  function invokeAction(id: int, actionId: string): void
}
```

* Wrap `Quickshell.Services.Notifications` — `onNotificationReceived: history.prepend(n)`. No polling.

## 6. Acceptance

* [ ] Shows 3 most recent by default; can scroll/paginate to older.
* [ ] Per-card dismiss + clear-all both work; history empty state renders.
* [ ] Silence/DND toggle affects bell state and badge behaviour.
* [ ] Exclusive: no `swaync`/`mako` popups remain (disable `swaync` autostart in `hyprland.lua` when this ships).
* [ ] Vim nav + `/` filter + `Esc` close work.
* [ ] Uses `LauncherBase` + `Theme.*` tokens.
