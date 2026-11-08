# Identity Manager — Fingerprint Authentication Design

**Date:** 2026-11-08 (rev 2 — mechanism corrected after source review; see §5)
**Status:** Draft — awaiting user approval
**Scope:** NixOS fingerprint configuration, Quickshell Identity Manager launcher + service, hyprlock config, Hyprland binding, theme/spec updates, tests and docs.

## 1. Intent

The laptop has a Synaptics fingerprint reader (HP EliteBook 845 G8; USB `06cb:00f0`, supported by libfprint 1.94.10) that is currently unused on Linux. Two things are wanted:

1. **Fingerprint unlock for hyprlock**, with the password always as fallback.
2. An **Identity Manager** launcher in Quickshell (`SUPER+I`) that can, for the current user: enable/disable fingerprint authentication, list enrolled fingerprints, enroll a new finger, and delete enrolled fingers.

The repo stays machine-agnostic: it enables the *capability* on every machine (a machine without a reader only runs an idle daemon and logs a warning), and everything per-machine — enrollment templates, the enable/disable switch — is runtime state that never enters git.

## 2. Goals

- `hyprlock` accepts a fingerprint and still accepts the password; if no reader, no daemon, or no enrolled prints exist, hyprlock behaves exactly as today (password only, logs only).
- An on/off switch, per user, with no root and no rebuild; it takes effect at the next lock screen. Off means: no fingerprint prompt at lock; password required.
- Identity Manager launcher: toggle, list, enroll (finger picker + live progress), delete (with confirm), filter, vim-style navigation, `Esc`, degraded states.
- `SUPER+I` binding; entries in the Key Hints launcher and the Control Center; a new normative launcher spec.
- Generic and fail-soft on every machine; no machine-specific values in the repo.
- Deterministic tests: parser unit tests (headless), a NixOS-side test that asserts the PAM scoping, existing repo checks stay green.

## 3. Non-goals

- Fingerprint for `sudo`, `su`, `sshd`, `polkit`, TTY `login`, or any PAM service. Rationale: an unattended reader turns into unintended approvals (CVE-2024-37408 "fingerprint hijacking") and up to 30 s waits; hyprlock's native path exists precisely so PAM integration is unnecessary.
- Fingerprint before session start (greetd autologin is unchanged).
- Other auth methods (u2f, smartcards, howdy).
- Storing biometric templates anywhere except `/var/lib/fprint` on the machine; no templates in git or sops.
- Per-service scoping UI, a "test my finger now" flow, or auto-enrollment.
- Machines needing a proprietary TOD driver — if one ever appears it goes in that machine's `/etc/nixos/machine.nix`, not here.

## 4. Constraints

- Repo rules: nothing machine-specific; every change in a worktree; declarative config only; the user runs `update` themselves; the `AGENTS.md` checks run before proposing commits.
- Built against **hyprlock 0.9.5** (the version in the pinned nixpkgs 26.05 input; verified on the running system). The unstable/master inputs ship 0.9.6 — not used by this design; see §11 for what changes if the user bumps it.
- **hyprlock unlocks fingerprints natively**: it talks to fprintd over the system D-Bus (`net.reactivated.Fprint`), with `CFingerprint` instantiated only when `auth:fingerprint:enabled` is on; its PAM stack (`auth:pam:module`, default `hyprlock`) is the password path only. Verified against hyprlock `v0.9.5` source (`src/auth/{Auth,Fingerprint,Pam}.cpp`).
- Quickshell 0.3.2 (`Process` has `exited(exitCode, exitStatus)`); fprintd 1.94.5 utilities (`fprintd-enroll/list/delete`, C implementations); no native D-Bus QML type — CLI through `Process`.
- No hard-coded colours or glyphs outside `theme/Theme.qml` / `theme/Icons.qml`; one `Process` per subsystem in `services/`; launchers never poll.
- The runtime switch is a hyprlock config override file, and its path is a contract between `hypr/hyprlock.conf` and the QML service: **`~/.local/state/hyprlock-fingerprint.conf`**.
- The `source =` line must stay **last** in `hyprlock.conf` so the override wins; `source` supports `~` expansion, and a missing file is logged as a config error (hence the service seeds the file — §6.2).
- Manual precondition on this laptop: the reader must be enabled in firmware (`Advanced → Built-in Device Options → Fingerprint Device`) and must enumerate as `06cb:00f0` before the last-mile testing can happen.

## 5. Approaches Considered

### 5.1 The enable/disable switch (rev 2 — corrected mechanism)

**A — native fingerprint + state-file config override (chosen).** hyprlock already supports fingerprint natively; enable it in `hypr/hyprlock.conf` and add a `source = ~/.local/state/hyprlock-fingerprint.conf` include as the last line. The Identity Manager writes that file with `enabled = false` (disabled) or `enabled = true` (enabled, default). hyprlock reads its config at every lock, so the switch takes effect at the next lock. No root, no rebuild, per user; enrollment/management keep working while disabled; fully fail-soft (see §6.2).

**B — wrapper script with `hyprlock -c <generated config>`.** Generate the config per lock and force it via `-c`. Rejected: every lock caller must change (`hyprland.lua` bind + session-start autostart; edits outside the session too), and it hides the real config from `hyprlock`'s normal discovery for no gain over `source`.

**C — `pam_fprintd` in the `hyprlock` PAM service.** The original sketch before source review; rejected after verification: in hyprlock 0.9.5 `CPam::init()` blocks on user input **before** `pam_authenticate()` runs, so a `pam_fprintd` rule can never produce a scan-at-lock prompt — it would only ever run after the user pressed Enter. (In 0.9.6 the PAM conversation starts immediately, but upstream's own source comment advises using `auth:fingerprint:enabled` instead, and 0.9.6 carries a relock regression, see §11.) It would also have required an experimental `pam_exec` guard rule to emulate the switch.

### 5.2 Fingerprint scope

**hyprlock only (chosen).** fprintd's NixOS integration defaults `fprintAuth` to *every* PAM service (~30 in 26.05: `sudo`, `su`, `sshd`, `polkit-1`, `passwd`, lockers, account tools…). The design explicitly disables the PAM integration everywhere — including `hyprlock` itself, since the native path covers it:
- Security: the fingerprint-hijacking class (CVE-2024-37408) applies to attention-free PAM prompts — exactly `sudo`/`su`/`polkit`/`sshd`.
- UX: `pam_fprintd`'s default 30 s wait before password fallback would hit every `sudo`.

Alternatives (TTY `login`; adding `sudo`/`su`) were offered and declined by the user.

### 5.3 Enrollment backend

**fprintd CLI over `Process` (chosen).** `fprintd-enroll` prints one `Enroll result: <status>` line per daemon signal and exits 0 only on `enroll-completed` (verified against the 1.94.5 source); `fprintd-list`/`fprintd-delete` print stable, parseable text. This matches repo precedent (`nmcli`, `bluetoothctl`, `udisksctl` via `Process`).

Alternative: enumerate/claim/enroll over D-Bus with `busctl` — rejected: chatty, and no gain over the CLI's stage lines and exit code.

## 6. Auth model (verified)

### 6.1 NixOS side

`nixos/hardware-devices/fingerprint.nix` (new module, imported by `configuration.nix`):

- `services.fprintd.enable = true;` — daemon D-Bus-activated (`net.reactivated.Fprint`); `fprintd` lands in `environment.systemPackages`, so the CLIs are on the session PATH.
- **Every** PAM service gets `fprintAuth = false` — the exact list rendered from the pinned nixpkgs evaluation:

  ```
  chfn chpasswd chsh cups greetd groupadd groupdel groupmems groupmod
  hyprlock i3lock i3lock-color login other passwd polkit-1 runuser
  runuser-l sshd su sudo swaylock systemd-run0 systemd-user
  useradd userdel usermod vlock xlock xscreensaver
  ```

  This is the whole PAM story: no `pam_fprintd` anywhere, no `rules`/`pam_exec` machinery (the experimental nixpkgs option is not needed). hyprlock's fingerprint comes from its native D-Bus integration instead.
- Assertion (build-time drift guard): no enabled PAM service may have `fprintAuth` true; otherwise evaluation fails with a pointer to this module. Protects against a future nixpkgs adding a new fingerprint-enabled service.

### 6.2 hyprlock native path

Appended to the repo's `hypr/hyprlock.conf` (order matters — `source` last):

```conf
# Fingerprint unlock. hyprlock talks to fprintd directly (no PAM module).
# The Quickshell Identity Manager (SUPER+I) maintains the override file
# below; this must stay the last line so the override wins.
auth {
    fingerprint {
        enabled = true
    }
}
source = ~/.local/state/hyprlock-fingerprint.conf
```

Verified behaviour in hyprlock 0.9.5 (`Fingerprint.cpp`):
- Instantiates only when `auth:fingerprint:enabled` is truthy; claims the default fprintd device for the current user and runs `VerifyStart("any")`.
- **Fail-soft:** if the daemon is absent, no device exists, the claim fails, or `VerifyStart` errors (e.g. no enrolled prints), it logs a warning and shows nothing; the password path is unaffected. `verify-match` unlocks directly (`enqueueUnlock`).
- Retries: `verify-no-match` retries up to 3 times (250 ms apart) then disables itself for that lock with a failure text; retry variants show prompts ("Please retry fingerprint scan" etc.).
- `auth:pam:enabled` must stay on: hyprlock asserts at least one auth method exists, so the state file only ever touches `fingerprint:enabled`.

The state file (written by the Identity Manager, per user, never in git):

```conf
# Managed by the Quickshell Identity Manager (SUPER+I). Delete to reset to
# the repo default (enabled).
auth {
    fingerprint {
        enabled = false
    }
}
```

- Absent or unparseable → treated as enabled (matches the repo default).
- The service **seeds** it on shell start when absent (content `enabled = true`): this both silences hyprlock's "source file doesn't exist" config error and makes the state explicit. Existing files are never touched.
- Takes effect at the **next lock screen** — hyprlock re-reads its config on every launch (SUPER+X, session-start lock), so in practice the switch is immediate for the next lock.

### 6.3 Per-machine runtime state

- Switch: `~/.local/state/hyprlock-fingerprint.conf` (see §6.2).
- Biometric templates: `/var/lib/fprint/<user>/`, managed by fprintd; enrollment happens on the machine, once (via the launcher or `fprintd-enroll`).

## 7. Identity Manager — service contract

`quickshell/services/IdentityService.qml` (new singleton; registered in `services/qmldir`):

```qml
property bool fprintdAvailable     // fprintd-enroll/list/delete on PATH
property bool devicePresent        // a reader is enumerated by the daemon
property bool authEnabled          // state file absent/unparseable → true
property var enrolled              // [{ name, label }]
property bool enrolling
property string enrollFinger       // name being enrolled
property string enrollStage        // latest raw status string
property string enrollMessage      // human text for enrollStage (derived)
property int enrollPasses          // count of enroll-stage-passed
property bool enrollDone           // last terminal result was enroll-completed
property string lastError
signal dataUpdated()

function refresh(): void
function setAuthEnabled(on: bool): void
function enroll(finger: string): void
function cancelEnroll(): void
function deleteFinger(finger: string): void
```

Commands (all through `Process`; `sh -c` only where a username or `$HOME` expansion is needed, following `UsbService` precedent):

| Action | Command |
|---|---|
| probe availability + state | `sh -c` printing `BIN=1/0`, then the state file's content or `ABSENT` |
| list | `sh -c 'fprintd-list "$(id -un)" 2>&1'` |
| enroll | `["fprintd-enroll", "-f", <finger>]` (stdout `SplitParser`; `onExited` for the result) |
| delete | `sh -c 'fprintd-delete "$(id -un)" -f "$FPRINT_FINGER" 2>&1'` with `environment: { FPRINT_FINGER: <finger> }` |
| set enabled | `sh -c` writing the state file with `FPRINT_ENABLED` substituted (`printf 'auth {\n    fingerprint {\n        enabled = %s\n    }\n}\n'`), `mkdir -p` first |
| seed (startup, absent only) | same write with `FPRINT_ENABLED=true` |

Parsing lives in `quickshell/services/identityParse.js` (pure functions, unit-tested headless like `screenCastParse.js`):

- `FINGERS` — the ten names: `left-thumb`, `left-index-finger`, `left-middle-finger`, `left-ring-finger`, `left-little-finger`, `right-thumb`, `right-index-finger`, `right-middle-finger`, `right-ring-finger`, `right-little-finger`.
- `parseEnrolled(text)` — collects `- #N: <finger>` lines (real `fprintd-list` 1.94.5 format); a "has no fingers enrolled" body yields `[]`.
- `listError(text)` — distinguishes: no device (`No devices available`), daemon unavailable (`Impossible to get devices`, `Failed to connect to session bus`, `Failed to get Fprintd manager`), listing failure (`ListEnrolledFingers failed`).
- `parseAuthEnabled(text)` — reads `enabled = true|false|1|0` from the state file; `ABSENT`/garbage → `true`.
- `enrollStageLabel(status)` — human text for each daemon status: `enroll-stage-passed` ("Stage passed — lift and place again"), `enroll-retry-scan`, `enroll-swipe-too-short`, `enroll-finger-not-centered`, `enroll-remove-and-retry`, `enroll-too-fast`, `enroll-completed`, `enroll-failed`, `enroll-duplicate`, `enroll-data-full`, `enroll-disconnected`, `enroll-unknown-error`.
- `fingerLabel(name)` — "right-index-finger" → "Right Index Finger".

No polling: `refresh()` runs on service start, on launcher open, after each mutation, and on demand (`r`). The startup seed runs once, immediately after the first probe.

## 8. Identity Manager — launcher

New normative spec `quickshell/specs/launchers/Identity-Manager.md` (same shape as `Usb-Manager.md`); implementation `quickshell/components/launchers/IdentityManager.qml`.

- **Chrome:** centered card **620 px** (new entry in `STYLE.md` §5.1), `Theme.roundingLauncher`, header `Identity Manager`, footer hints, `Esc` closes; `/` filter, vim `j/k`, `Home`/`End`.
- **Views:** `main` ↔ `enroll`, sliding per `STYLE.md` §2.5; `h`/`l`/`Esc` move back/forward at every level (SPECS.md general rule).
- **Main view, top → bottom:**
  1. Toggle row: `Icons.fingerprint` glyph + "Unlock with fingerprint" + status `Enabled` (`Theme.fg`) / `Disabled` (`Theme.fgDim`), with the note "applies to the next lock" in muted text. `Enter`, `Space`, or `t` toggles via `IdentityService.setAuthEnabled`.
  2. Divider + "Enrolled fingers" section: one row per finger — glyph + `fingerLabel(name)` + raw name right-aligned muted. `Enter` or `d` asks `Delete right-index-finger? y/n` in the footer (`Theme.critical`); `y` runs `deleteFinger`. Empty state: "No fingerprints enrolled".
  3. Actions row: `e` enroll (opens picker), `r` refresh.
- **Enroll view:** ten finger rows (pretty labels; already-enrolled marked). `Enter` starts `enroll(finger)`. While enrolling, the body becomes a progress panel: large `Icons.fingerprint` + latest stage message + pass count; `Esc` cancels (`cancelEnroll`). Completion shows "Enrolled" and refreshes the list; failure shows the label + `Enter retry · Esc back`.
- **Degraded states:** `fprintd` missing → banner "fprintd unavailable" (actions disabled, `Theme.warning`); no reader → "No fingerprint reader detected"; daemon/list errors surfaced inline at `Theme.critical`; claim conflicts ("Device was already claimed") surfaced with a retry hint. The toggle row stays usable even without fprintd (the state file is independent), but is visually muted when there is nothing to drive.
- **Keys summary (footer):** `j/k move · Enter act · e enroll · d delete · t toggle · / filter · Esc close`.

## 9. Wiring

- `hypr/hyprlock.conf`: append the block + `source = ~/.local/state/hyprlock-fingerprint.conf` as the final line (§6.2).
- `quickshell/shell.qml`: mount `IdentityManager { id: identityManager }`; add `identity` branches to `toggle`, `close`, `closeAllExcept`, `closeAll`.
- `hypr/hyprland.lua`: `hl.bind(mainMod .. " + I", hl.dsp.exec_cmd("quickshell ipc call launcher toggle identity"))` next to the other quickshell launcher binds (sync comment stays true).
- `quickshell/components/launchers/KeyLauncher.qml`: Shell section row `{ key: "SUPER+I", action: "Identity Manager", desc: "fingerprint" }`.
- `quickshell/components/launchers/ControlCenter.qml`: entry `{ label: "Identity", key: "SUPER+i", icon: Icons.fingerprint, target: "identity" }`.
- `quickshell/theme/Icons.qml`: `property string fingerprint: String.fromCodePoint(0xF0237)` (nf-md-fingerprint; MDI is above the BMP, so `String.fromCodePoint` per `STYLE.md`; render verified during implementation).
- `quickshell/specs/`: new `launchers/Identity-Manager.md`; update `launchers/Control-Center.md` (entries table + count), `launchers/Key-Launcher.md` (Shell source note), `SPECS.md` (§5.2 table + file layout), `STYLE.md` (§3 glyph list + §5.1 card widths).
- `nixos/configuration.nix`: import `./hardware-devices/fingerprint.nix`.
- `README.md`: short generic paragraph — fingerprint capability is enabled everywhere, enrollment is per machine, disable via the Identity Manager (`SUPER+I`).
- `AGENTS.md`: add `bash nixos/tests/test-fingerprint.sh` to the checks list.

## 10. Testing and verification

- **Unit (headless):** `quickshell/tests/tst_identity_parse.qml` — fixtures from real 1.94.5 output (` - #0: right-index-finger`, "has no fingers enrolled", "No devices available", "Impossible to get devices…"), state-file parsing (true/false/absent), stage-label mapping, finger labels. Picked up by `quickshell/tests/run.sh` automatically.
- **Nix config (new `nixos/tests/test-fingerprint.sh`):** stages a temp machine dir (`nixos/tests/stub-machine.nix` copied as `hardware-configuration.nix` + empty `machine.nix`), then with `DOTFILES_MACHINE_DIR` evaluates and asserts: no `security.pam.services.*.fprintAuth` is true (or enabled); no generated PAM text contains `pam_fprintd`; setting `sudo.fprintAuth = true` via `extendModules` makes evaluation fail (assertion fires). Plus a static check that `hypr/hyprlock.conf` ends with the `source = ~/.local/state/hyprlock-fingerprint.conf` line.
- **Existing checks:** the `AGENTS.md` list stays green; `nixos-rebuild dry-build` with the real machine dir; `quickshell -p "$PWD/quickshell"` clean; no hard-coded hex/glyph greps.
- **Manual E2E (after BIOS step, on real hardware):** `lsusb` shows `06cb:00f0`; enroll right index via the launcher; `SUPER+X` lock → fingerprint prompt → unlock; toggle off → lock shows password only (no prompt, no errors); toggle on → fingerprint returns; delete a finger; cancel mid-enrollment; second enroll while one is running surfaces the claim error.
- **Explicitly unverifiable until the reader enumerates:** the actual sensor scan, enrollment quality, whether the claim from a locked session succeeds on this fprintd build, and hyprlock's fingerprint UX. All of the Nix/launcher logic above is testable without it.

## 11. Known limits

- The reader currently does not appear on USB; the firmware toggle and the physical module are preconditions outside this repo.
- The `source` line must stay last in `hyprlock.conf`; a missing state file is a logged config error (mitigated by the service's one-time seed).
- `auth:pam:enabled` must stay on (hyprlock asserts at least one auth method); the state file never touches it.
- hyprlock 0.9.6 (in the unstable/master inputs, not in the pinned nixpkgs): changes PAM conversation timing and carries a known relock regression after a fingerprint unlock (issue #1074). Unrelated to this design, but visible if the user bumps the input; note it in the plan's verification steps.
- Claim/verify behavior from a locked session cannot be verified without the hardware.
- Cancelling an enrollment relies on the daemon releasing the device when the CLI disconnects; claim errors are surfaced with a retry path.
- Glyph `0xF0237` must be visually confirmed in JetBrainsMono Nerd Font at implementation time.
- Enrollment templates and the toggle are per machine and are not synced.

## Execution note (user instruction)

Any subagent dispatched for this feature — design reviewer, builders, testers — must run model **`openrouter/deepseek/deepseek-v4.1-flash`** (provider openrouter). No other model is authorized for this work.
