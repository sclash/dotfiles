# Identity-Manager — Refined Spec

> Command: `SUPER+I` · Files: `components/launchers/IdentityManager.qml` + `components/launchers/identity/*.qml` · Service: `IdentityService.qml` · Helper: `scripts/identity-passwd.py`

---

## 1. Purpose

Manage how the current user authenticates:

| Method | Where it works | Default | Can be disabled |
|---|---|---|---|
| **Password** | everywhere (lock screen, sudo, polkit, login, ssh) | always on | no — it can only be changed |
| **Face** (Howdy, IR camera) | lock screen only | enabled when an IR camera is present, otherwise **Not available** | yes |
| **Fingerprint** (fprintd) | lock screen only | enabled when a reader is present, otherwise **Not available** | yes |

Unlock itself is hyprlock: fingerprint through its native fprintd path (`auth:fingerprint:enabled`), face through the `hyprlock-face` PAM service (`auth:pam:module`). This launcher owns everything around them and the per-user files that switch them.

## 2. Window

* Self-contained overlay like `UsbManager.qml`: centered card, `width: 620`, `radius: Theme.roundingLauncher`, `color: Theme.bgLauncher`, border `Theme.borderActive` 1 px, `clip: true`; focus forced to the card on open. Title `IDENTITY MANAGER` plus `· <Method>` in a method view.
* Views: `main` ↔ `password` | `face` | `fingerprint`; slide transitions per `STYLE.md` §2.5 (main parks at −60, method views at +60, cross-fade, height animation). Each view is its own file in `components/launchers/identity/` with `reset()` and `handleKey(e)`; the shell routes every key to the active view.

## 3. Views

### 3.1 Main (`MethodsView.qml`)

* Three `MethodRow`s: `Icons.key` Password (`Change…`), `Icons.face` Face, `Icons.fingerprint` Fingerprint. Face/Fingerprint show `Enabled · N models|fingers`, `Disabled · N …` or `Not available` (dim).
* `j/k` move · `Enter`/`l` open · `t`/`Space` toggle (face/fingerprint, only when available) · `r` refresh · `Esc` close.

### 3.2 Password (`PasswordView.qml`)

* Three masked fields (`SecretField`): current, new, repeat. One eye toggle (click, or `Ctrl+S`) shows/hides all three; hidden again on reset. `Enter` moves to the next field and submits on the last; `Tab` moves too.
* Before anything is sent: `Parse.validatePasswordForm` — current and new must be non-empty, new and repeat must match (mandatory), then `Parse.passwordPolicy`: no leading or trailing whitespace, and deliberately no length or character limits. On a mismatch the repeat field is cleared and focused.
* Submit → `IdentityService.changePassword(current, new)`; **all fields are cleared immediately**, and again whenever the view is left or the launcher closes.
* Result line from `passwdResult`: `Password changed` (`Theme.fg`), `Current password is wrong`, `Rejected: <PAM reason>`, `Error: …` (`Theme.critical`).
* Without `identity-passwd` on PATH: `identity-passwd is not installed — run update`, fields disabled.
* `Esc` back (clears the form).

### 3.3 Face (`FaceView.qml`)

* Toggle row `Unlock with face`, note `lock screen only · press Enter, then look at the camera`; `Enter`/`t`/`Space` on it flips the choice; inert when `Not available`.
* `Face models` list (`label`, date from `time`). Empty: `No face models yet — press a to add one`.
* `a`/`e` → label field (max 24 chars, commas dropped; empty = `Face N`), `Enter` → `IdentityService.addFace(label)`: an **inline** password field (`Enter your password to add a face model`, eye toggle, polkit's retry message) answers polkit, then `Look straight into the camera…`, then `Face model added` or Howdy's message. `Esc` in the field cancels (`Authorization cancelled`).
* `d`/`Enter` on a model → footer `Remove "<label>"?  y / n` (`Theme.critical`) → `removeFace(id)` (same inline password field).
* If Howdy saw only black frames: `The IR light looks off. Run once: sudo linux-enable-ir-emitter configure`.
* Unavailable: `Howdy is not installed — run update` or `No IR camera detected (<device_path>)`.

### 3.4 Fingerprint (`FingerprintView.qml`)

* Toggle row `Unlock with fingerprint` (`applies to the next lock`); inert when `Not available`.
* Enrolled fingers (`fingerLabel` + raw name), `/` filter, `d`/`Enter` delete with `y/n`, `e`/`a` enroll: picker of ten fingers → progress (`enrollMessage`, pass count) → `Enrolled` / failure with `Enter retry · Esc back`; `Esc` during progress cancels.
* Degraded: `fprintd unavailable` (`Theme.warning`), `No fingerprint reader detected`, inline `lastError` (`Theme.critical`).

## 4. Shared Behaviours

* `Esc` stack: confirm → label/filter/enroll sub-state → method view → close.
* No polling: views read `IdentityService`; `Connections { onDataUpdated }`; `refresh()` on open; `r` refreshes.
* Changes apply at the next lock screen.

## 5. Service Contract

All processes and state files live in `IdentityService.qml` — launchers never spawn `Process` (SPECS.md §2.3 rule 3).

```qml
// fingerprint
property bool fprintdAvailable; property bool devicePresent
property var enrolled                      // [{ name, label }]
property bool enrolling; property string enrollFinger; property string enrollStage
property string enrollMessage; property int enrollPasses; property bool enrollDone
property string lastError
readonly property string fingerprintState  // "enabled" | "disabled" | "unavailable"
// face
property bool howdyAvailable; property string irDevice; property bool irPresent
property var faceModels                    // [{ id, label, time }]
property bool faceBusy; property string faceAction
property string faceMessage; property bool faceMessageIsError; property bool faceNeedsEmitter
readonly property string faceState         // "enabled" | "disabled" | "unavailable"
// password
property bool passwordAvailable; property bool passwordBusy
property string passwordMessage; property bool passwordOk
// shared
property var choices                       // { fingerprint, face }: "on" | "off" | ""
readonly property var effective            // { fingerprint, face, pamModule }
signal dataUpdated()

function refresh(): void
function setChoice(method: string, on: bool): void   // "fingerprint" | "face"
function enroll(finger: string): void
function cancelEnroll(): void
function deleteFinger(finger: string): void
function addFace(label: string): void
function removeFace(id: int): void
function changePassword(current: string, next: string): void
function clearPasswordMessage(): void
```

Pure logic (unit-tested in `tests/tst_identity_parse.qml`) is in `services/identityParse.js`: `parseChoices`, `renderChoices`, `methodState`, `effectiveAuth`, `renderHyprlockAuth`, `parseHowdyDevicePath`, `parseHowdyModels`, `howdyMessage`, `passwdResult`, `validatePasswordForm`, `passwordPolicy`, plus the fprintd parsers.

## 6. Backend Notes

* **Choices** `~/.local/state/identity/choices` — `fingerprint=on|off`, `face=on|off`; written only by this service; a missing key means "hardware default" (enabled when present).
* **hyprlock override** `~/.local/state/hyprlock-auth.conf` — *derived*, rewritten on every refresh when it changes: `auth:fingerprint:enabled` (reader present and not `off`), `auth:pam:module` = `hyprlock-face` when the IR camera is present, face is not `off` and at least one face model exists, else `hyprlock`. It also draws the method icons under the password box (`Parse.lockIcons`): unsupported = hidden; supported but off (or face without a model) = `Theme.fgDim`; usable = `Theme.fg`; the one hyprlock tries first (fingerprint when usable, else face) = `Theme.fgBright`, plus a one-line hint (`Touch the sensor…` / `Press Enter to unlock with your face`). One icon is centered, two sit side by side (fingerprint left). `hypr/hyprlock.conf` sources it last.
* **Face** — Howdy 3 (`nixos/hardware-devices/face.nix`). The IR camera is Howdy's `device_path` (default `/dev/v4l/ir0`, created by a udev rule matching `*IR Camera*|*Infrared*`; a machine can override it in `/etc/nixos/machine.nix`); present = that path exists. Models are read from `/var/lib/howdy/models/<user>.dat` (world-readable JSON); add/remove run `pkexec howdy -U <user> -y add <label>` / `remove <id>`. Quickshell is the session's polkit agent (`services/PolkitService.qml`): while the Face view is open it claims `pkexec howdy` requests (`polkitParse.js` `routeInline`) and answers them inline; any other request, or this one after the launcher closes, goes to `components/launchers/PolkitPrompt.qml`. hyprlock starts PAM only when Enter is pressed, so face unlock is "Enter, then look". Howdy's PAM module is `sufficient` before `pam_unix`, so a failed or skipped face check always falls back to the password.
* **Password** — `identity-passwd` (`scripts/identity-passwd.py`, packaged in `nixos/programs/quickshell.nix`): reads the current and new password from stdin, drives `passwd` on a pty under `LC_ALL=C`, prints one line `OK | BAD_CURRENT | REJECTED <msg> | ERROR <msg>`. Passwords never go into argv, the environment or logs.
* **Fingerprint** — `fprintd-list`, `fprintd-enroll -f <finger>`, `fprintd-delete <user> -f <finger>`; PAM integration stays disabled system-wide (`nixos/hardware-devices/fingerprint.nix`).

## 7. Acceptance

* [ ] Main view lists the three methods with the right state; `Not available` without the hardware and the toggle does nothing.
* [ ] Face/fingerprint toggles persist across reopen and change `hyprlock-auth.conf`; the next lock follows them.
* [ ] Password: mismatch never reaches passwd; wrong current / rejected / success messages; fields cleared on submit and close.
* [ ] Face: add (polkit prompt, camera) and remove (`y/n`) a model; dark-emitter hint; lock → Enter → face unlocks; face off → password only.
* [ ] Fingerprint: enroll / cancel / delete / filter as before.
* [ ] `Theme.*`/`Icons.*` only; card is 620 px; vim keys and the `Esc` stack work.
* Tests: `bash quickshell/tests/run.sh`, `bash quickshell/tests/smoke-identity-views.sh`, `bash quickshell/tests/test-identity-passwd.sh`, `bash nixos/tests/test-face.sh`, `bash nixos/tests/test-fingerprint.sh`.
