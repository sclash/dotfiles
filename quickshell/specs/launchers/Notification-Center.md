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
* Per-arrival **display popup** (`NotificationToast`) is **disabled by default**. The center is a read-only history; it must not pop up on its own when a notification arrives.

### 3.2.1 Transient Toast (on by default)

* A small top-right toast is shown for every new notification by default, gated by `NotifService.toastEnabled` (default `true`). It auto-dismisses after `NotifService.toastTimeoutMs` (default `3000` ms, clamped1–10 s).
* **Suppressed while `NotifService.dnd === true`** — DND overrides the toast entirely; `urgency` does not bypass.
* When DND is lifted, `toastEnabled` remains `true` (DND only suppresses *now*, it does not auto-disable the toggle).
* Placement: top-right corner of the primary monitor, anchored `Screen.desktopAvailableWidth - width - Theme.spacingM`. Stack downward; **max 5 visible**.
* **Overflow:** when 5 toasts are already up, new ones enter a FIFO `toastQueue` (max 20). As soon as a visible toast expires (or is clicked/dismissed), the oldest queued toast is promoted — the "latest" toast is displayed only after a slot frees up. A promoted toast gets a **full fresh lifetime** (`toastTimeoutMs`) from the moment it is shown.
* Geometry: `width: 360`, `rounding: Theme.roundingItem`, black (`Theme.bgBar`) background, no border, `Theme.fg` text, `Theme.fgMuted` timestamp.
* Content: `appIcon` (24px) + `appName` (small, muted) on row 1; `summary` (bold) + `body` (1 line, elide) on row 2; right-aligned `Theme.fontSizeSmall` age (`now − received`). No actions, no dismiss button — auto-dismiss only.
* Lifecycle: timer per toast; cancelled on user click (single click = invoke primary action if present, else just close).
* **No daemon-level popup layer** — toasts are drawn by Quickshell in `components/launchers/NotificationToast.qml`; `swaync`/`mako` autostart stays disabled.

### 3.3 DND / Silence

* **Silence toggle:** `Silence` / `Unsilence` button at top (or `Ctrl+s`). When `NotifService.dnd === true`:
  * Bell in `Date` switches to silenced state (see `Date.md:3`).
  * New notifications still accumulate in `history` but do not badge the bell as unread (or badge dimmed).
  * Transient toasts (`3.2.1`) are **suppressed** regardless of `toastEnabled`.
  * **Sound is suppressed** regardless of `soundEnabled` — DND is unconditional.
* Toggle binds to `NotifService.dnd = !NotifService.dnd`. Persist via `JsonCache` or `gsettings` if desired (optional).

### 3.3.1 Sound toggle

* **Sound:** `Sound: on` / `Sound: off` button at top (or `Ctrl+m`). Default `true` (on).
* When `soundEnabled === true` a notification plays `NotifService.fallbackSound` (or the sender's `sound-file` hint) via `pw-play`, unless the sender sets `suppress-sound`.
* **When `dnd === true` sound is always off**, independent of `soundEnabled` — DND is the master switch.
* Toggle binds to `NotifService.soundEnabled = !NotifService.soundEnabled`.

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
| `Ctrl+t` | toggle transient toasts |
| `Ctrl+m` | toggle notification sound |
| `/` | filter by app/summary/body substring |
| `Enter` | invoke notification's primary action (if any), else dismiss |
| `Shift+J/K` or `PageDown/Up` | load older / newer page |

## 5. Service Contract — `NotifService.qml`

```qml
QtObject {
  property bool dnd
  property int unreadCount
  property list<Notification> history  // from Quickshell.Services.Notifications
  property bool toastEnabled: true   // transient top-right toast (on by default; suppressed while dnd)
  property int toastTimeoutMs: 3000  // auto-dismiss after this; clamped [1000, 10000]
  property bool soundEnabled: true   // play alert sound (on by default; suppressed while dnd)
  property int toastMaxVisible: 5    // max simultaneously visible toasts
  property int toastQueueMax: 20     // cap on queued (not yet visible) toasts
  property list<Notification> toasts  // currently visible toasts
  property list<Notification> toastQueue // waiting to be shown (FIFO)
  function clearHistory(): void
  function dismiss(id: int): void
  function invokeAction(id: int, actionId: string): void
  function spawnToast(n: Notification): void  // no-op when dnd || !toastEnabled; queues if full
  function promoteFromQueue(): void // backfill visible stack from toastQueue
  function reapExpiredToasts(): void // drop expired visible toasts, then promote
  function dismissToast(id: string): void
  function toggleToast(): void
  function toggleSound(): void
}
```

* Wrap `Quickshell.Services.Notifications` — `onNotificationReceived: history.prepend(n)`. No polling.

## 6. Acceptance

* [ ] Shows 3 most recent by default; can scroll/paginate to older.
* [ ] Per-card dismiss + clear-all both work; history empty state renders.
* [ ] Silence/DND toggle affects bell state, badge, and toasts.
* [ ] Exclusive: no `swaync`/`mako` popups remain (disable `swaync` autostart in `hyprland.lua` when this ships).
* [ ] NotificationCenter window does **not** auto-open on new notification — it stays hidden until the user invokes `SUPER+SHIFT+a` or clicks the bell.
* [ ] With `toastEnabled: true` (default) every new notification produces a top-right toast that auto-dismisses after `toastTimeoutMs` (default 3000).
* [ ] With `dnd: true` no toast appears regardless of `toastEnabled` (DND is unconditional, including `urgency === critical`).
* [ ] With `dnd: true` no sound plays regardless of `soundEnabled`.
* [ ] `soundEnabled` defaults to `true`; `Sound: on/off` toggle and `Ctrl+m` work.
* [ ] Toasts stack top-right, max 5 visible; overflow toasts are queued and promoted as slots free up (full fresh lifetime on promotion).
* [ ] Vim nav + `/` filter + `Esc` close work.
* [ ] Uses `LauncherBase` + `Theme.*` tokens.
