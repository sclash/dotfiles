# Identity-Manager — Refined Spec

> Command: `SUPER+I` · File: `components/launchers/IdentityManager.qml` · Service: `IdentityService.qml`

---

## 1. Purpose

Manage fingerprint authentication for the current user: toggle fingerprint unlock for hyprlock, list enrolled fingerprints, enroll a new finger (with live progress), and delete enrolled fingers. Unlock itself is hyprlock's native fprintd integration (`auth:fingerprint:enabled` in `hypr/hyprlock.conf`); this launcher owns everything around it and the per-user override file that turns it on and off.

## 2. Window

* Self-contained overlay like `UsbManager.qml`: centered card, `width: 620`, `radius: Theme.roundingLauncher`, `color: Theme.bgLauncher`, border `Theme.borderActive` 1 px, `clip: true`; `Esc` closes; focus forced to the card on open.
* Views: `main` ↔ `enroll`; slide transitions per `STYLE.md` §2.5 (`x` parking ±60, cross-fade, height animation). `h`/`Esc` back, `l` forward.

## 3. Sections (top → bottom)

### 3.1 Toggle row (always first, always selectable)

* `Icons.fingerprint` glyph + "Unlock with fingerprint"; right-aligned state `Enabled` (`Theme.fg`) / `Disabled` (`Theme.fgDim`); muted note `"applies to the next lock"`.
* `Enter` / `Space` / `t` → `IdentityService.setAuthEnabled(!authEnabled)`.
* Never blocked by a missing fprintd (the state file is independent); visually muted when `!fprintdAvailable`.

### 3.2 Enrolled fingers

* Source: `IdentityService.enrolled` (from `fprintd-list`). Rows: `Icons.fingerprint` + `fingerLabel(name)` + raw name right-aligned (`Theme.fgMuted`).
* `Enter` or `d` → footer confirm `Delete right-index-finger? y/n` (`Theme.critical`); `y` → `IdentityService.deleteFinger(name)`; the list refreshes on `dataUpdated`.
* Empty state: `"No fingerprints enrolled"` (`Theme.fgMuted`).
* `/` filters rows by label/name (the toggle row is unaffected); `j/k`, arrows, `Home`/`End` move; `r` refreshes.

### 3.3 Enroll flow

* `e`/`a` opens the enroll view: ten rows from `Parse.FINGERS`/`fingerLabel`; already-enrolled ones marked `(enrolled)` (`Theme.fgMuted`).
* `Enter` → `IdentityService.enroll(name)`; the view becomes a progress panel: large `Icons.fingerprint` glyph + `enrollMessage` + pass count (`enrollPasses`) + `Esc cancel`.
* `Esc` during progress → `cancelEnroll()` back to the picker; a second `Esc` → main.
* Completion (`enrollDone`): `"Enrolled"` + list refreshed; `Enter`/`Esc` → main.
* Failure: `enrollMessage` + `Enter retry · Esc back`.

## 4. Shared Behaviours

* Footer hints: `j/k move · Enter act · e enroll · d delete · t toggle · / filter · Esc close` (per state; confirm text replaces the hints).
* `Esc` stack: filter → enroll view/progress → close.
* No polling: reads `IdentityService`; `Connections { onDataUpdated }`; `refresh()` on open.

## 5. Service Contract

All fprintd and state-file access goes through `IdentityService.qml` — the launcher never spawns `Process` (SPECS.md §2.3 rule 3).

```qml
// IdentityService.qml
property bool fprintdAvailable
property bool devicePresent
property bool authEnabled
property var enrolled              // [{ name, label }]
property bool enrolling
property string enrollFinger
property string enrollStage
property string enrollMessage       // derived label for enrollStage
property int enrollPasses
property bool enrollDone
property string lastError
signal dataUpdated()

function refresh(): void
function setAuthEnabled(on: bool): void
function enroll(finger: string): void
function cancelEnroll(): void
function deleteFinger(finger: string): void
```

## 6. Backend Notes

* CLI commands (all in `IdentityService.qml`): `fprintd-list "$(id -un)"`, `fprintd-enroll -f <finger>`, `fprintd-delete "$(id -un)" -f <finger>`; enroll progress comes from the CLI's `Enroll result: <status>` lines and its exit code.
* State file `~/.local/state/hyprlock-fingerprint.conf` — the launcher is its only writer; hyprlock reads it through the last `source =` line of `hypr/hyprlock.conf`. Absent/unparseable = enabled. The service seeds it once per session so hyprlock never logs a missing-source error.
* Unlock UX lives in hyprlock (`auth:fingerprint:enabled`); this launcher only flips it. The change applies at the next lock screen.
* Fingerprint PAM integration stays disabled system-wide (`nixos/hardware-devices/fingerprint.nix`) — no PAM module is involved in unlock. See `docs/superpowers/specs/2026-11-08-identity-manager-design.md`.

## 7. Empty / Degraded States

* `fprintdAvailable === false` → banner `"fprintd unavailable"` (`Theme.warning`); enroll/delete inert; the toggle still works.
* `devicePresent === false` → `"No fingerprint reader detected"` (`Theme.fgMuted`); enroll disabled.
* `lastError !== ""` → inline `Icons.warning + " " + lastError` (`Theme.critical`); claim conflicts (`"Device was already claimed"`) render with the retry path.
* 0 enrolled → §3.2 empty state.

## 8. Acceptance

* [ ] Toggle row flips the fingerprint state; the note "applies to the next lock" is visible; state survives reopen.
* [ ] Enrolled fingers list matches `fprintd-list`; empty state renders; delete asks `y/n` and refreshes.
* [ ] Enroll flow: picker lists 10 fingers; progress shows stage text + pass count; Esc cancels; completion refreshes the list; failure offers retry.
* [ ] Degraded states render for: fprintd missing, no reader, daemon errors, claim conflicts.
* [ ] Vim `j/k` + `/` filter + `Esc` stack work; card is 620 px; `Theme.*`/`Icons.*` only.
