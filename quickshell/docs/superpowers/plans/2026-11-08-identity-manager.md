# Identity Manager — Fingerprint Authentication Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fingerprint unlock for hyprlock plus a keyboard-driven Identity Manager launcher (`SUPER+I`) to enable/disable fingerprint authentication and manage enrolled fingerprints.

**Architecture:** NixOS enables fprintd but disables its PAM integration on every service (hyprlock uses fprintd natively over D-Bus). hyprlock gets `auth:fingerprint:enabled = true` plus a `source =` include from a user-state file that the Identity Manager rewrites to toggle the feature. A Quickshell singleton (`IdentityService`) wraps the fprintd CLIs and the state file; `IdentityManager.qml` renders the UI, is wired into `shell.qml` and Hyprland.

**Tech Stack:** NixOS 26.05 (pinned), hyprlock 0.9.5, fprintd 1.94.5, Quickshell 0.3.2 QML, bash test scripts, Qt Quick Test.

**Spec:** `quickshell/docs/superpowers/specs/2026-11-08-identity-manager-design.md`

## Global Constraints

- Repo root is the worktree root at `/home/asergi/.local/share/opencode/worktree/b53491/identity-manager` (branch `identity-manager`); all paths below are relative to it. QML root is `quickshell/`.
- The live `~/.config/quickshell` and `~/.config/hypr` symlinks point at the main checkout (`~/dotfiles`). Verify with `quickshell -p "$PWD/quickshell"`; do not rely on the live symlinks until the branch is merged. Nothing in this plan touches `~/dotfiles`, `/etc/nixos`, or `~/.config/sops`.
- **Execution model (user instruction):** every subagent dispatched for this feature (builders, reviewers, testers) must run model `openrouter/deepseek/deepseek-v4.1-flash` (provider openrouter). No other model.
- **Commits happen only after the user approves executing this plan** (repo rule: they approve every edit). Conventional Commits, short messages, never `--no-verify`; the pre-commit hooks (`tests/check-no-hardcoded-home.sh`, template check) must pass naturally.
- New flake files must be `git add`ed before any `nix eval` of the flake.
- No hard-coded colours/glyphs outside `quickshell/theme/Theme.qml` / `Icons.qml`; use `Theme.*`/`Icons.*`.
- One `Process` per subsystem in `quickshell/services/`; launchers never poll.
- State-file contract (both sides must keep it identical): path `~/.local/state/hyprlock-fingerprint.conf`; hyprlock include `source = ~/.local/state/hyprlock-fingerprint.conf` must stay the **last non-empty line** of `hypr/hyprlock.conf`; file absent/unparseable means enabled.
- Never disable `auth:pam:enabled` in hyprlock.conf (hyprlock asserts at least one auth method exists).
- Rebuilds (`nixos-rebuild switch`) are run by the user; this plan only dry-builds.

## Review Focus

- State file missing or unparseable: `authEnabled` must read as enabled and the service must seed the file exactly once, never overwriting an existing one; the lock screen must not show errors.
- No reader / fprintd absent: every Identity Manager surface degrades (banner, disabled actions), and hyprlock shows password only (warn-level logs are fine).
- Enrollment cancellation and claim conflicts: cancel then immediate re-enroll must not wedge; "Device was already claimed" renders with a retry path.
- PAM drift: any PAM service left with `fprintAuth = true` (e.g. a new nixpkgs service) must fail the build via the module assertion, and the test proves the assertion fires.
- Config ordering: moving the `source =` line off the end of `hyprlock.conf` silently re-enables fingerprint when the user disabled it — the static test in `nixos/tests/test-fingerprint.sh` pins the line's position.

---

### Task 1: Commit the approved design and this plan

**Files:**
- Create (already written): `quickshell/docs/superpowers/specs/2026-11-08-identity-manager-design.md`
- Create (this file): `quickshell/docs/superpowers/plans/2026-11-08-identity-manager.md`

**Interfaces:**
- Produces: the spec path that every later task cites: `quickshell/docs/superpowers/specs/2026-11-08-identity-manager-design.md`.

- [ ] **Step 1: Verify the working tree contains no stray changes**

Run: `git status --short`
Expected: only the two docs above (plus any legitimate earlier work).

- [ ] **Step 2: Commit**

```bash
git add quickshell/docs/superpowers/specs/2026-11-08-identity-manager-design.md \
        quickshell/docs/superpowers/plans/2026-11-08-identity-manager.md
git commit -m "docs(identity): add fingerprint identity manager design and plan"
```

---

### Task 2: NixOS fingerprint module with password-only PAM scoping

**Files:**
- Create: `nixos/tests/test-fingerprint.sh`
- Create: `nixos/hardware-devices/fingerprint.nix`
- Modify: `nixos/configuration.nix` (imports list, after `./hardware-devices/scanners.nix`)
- Modify: `AGENTS.md` (checks list under "Checks before proposing a commit")

**Interfaces:**
- Produces: `services.fprintd.enable = true` (fprintd daemon + CLIs on PATH); `security.pam.services.*.fprintAuth = false` for every service; a NixOS assertion that fails evaluation if any enabled PAM service has `fprintAuth` true. `nixos/tests/test-fingerprint.sh` is the test entry point other tasks append to.

- [ ] **Step 1: Write the failing test**

Create `nixos/tests/test-fingerprint.sh`:

```bash
#!/usr/bin/env bash
# Asserts the fingerprint/PAM scoping of nixos/hardware-devices/fingerprint.nix:
# fprintd is enabled, but no PAM service uses pam_fprintd; enabling it on any
# service fails evaluation (assertion). hyprlock uses the native fprintd
# integration instead (see hypr/hyprlock.conf, checked in Task 3).
set -uo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
STUB_DIR=$(mktemp -d)
trap 'rm -rf "$STUB_DIR"' EXIT
cp "$ROOT/nixos/tests/stub-machine.nix" "$STUB_DIR/hardware-configuration.nix"
printf '{ }\n' > "$STUB_DIR/machine.nix"

cat > "$STUB_DIR/check.nix" <<'NIX'
let
  root = builtins.getEnv "FPRINT_CHECK_ROOT";
  f = builtins.getFlake ("path:" + root + "/nixos");
  c = f.nixosConfigurations.default;
  lib = c.config.lib;
  svcs = c.config.security.pam.services;
  names = builtins.attrNames svcs;
  enabled = builtins.filter (n: svcs.${n}.enable && svcs.${n}.fprintAuth) names;
  texts = builtins.map (n: svcs.${n}.text) names;
  usesFprintd = builtins.filter (t: lib.hasInfix "pam_fprintd" t) texts;
  fingerprintFails = cfg:
    lib.filter (a: !a.assertion && lib.hasInfix "fingerprint" a.message) cfg.assertions;
  baseFailed = builtins.length (fingerprintFails c.config);
  violationMsgs = builtins.map (a: a.message)
    (fingerprintFails (c.extendModules { modules = [ { security.pam.services.sudo.fprintAuth = true; } ]; }).config);
in
{
  fprintdEnabled = c.config.services.fprintd.enable;
  enabledCount = builtins.length enabled;
  fprintdCount = builtins.length usesFprintd;
  baseFailed = baseFailed;
  violationCount = builtins.length violationMsgs;
  violationHasFingerprint = builtins.any (m: lib.hasInfix "fingerprint" m) violationMsgs;
}
NIX

result=$(FPRINT_CHECK_ROOT="$ROOT" DOTFILES_MACHINE_DIR="$STUB_DIR" \
  nix eval --impure --json --file "$STUB_DIR/check.nix")

failures=0
expect() { # jq-filter, description
  if [[ $(printf '%s' "$result" | jq -r "$1") == "true" ]]; then
    echo "OK   $2"
  else
    echo "FAIL $2 (result: $result)"
    failures=$((failures + 1))
  fi
}

expect '.fprintdEnabled'      "fprintd is enabled"
expect '.enabledCount == 0'   "no PAM service has fprintAuth enabled"
expect '.fprintdCount == 0'   "no PAM text contains pam_fprintd"
expect '.baseFailed == 0'     "no failing assertions in the base config"
expect '.violationCount >= 1' "enabling fprintAuth on sudo fails the assertion"
expect '.violationHasFingerprint' "the failing assertion names the fingerprint module"

if ((failures)); then
  echo "$failures fingerprint tests failed"
  exit 1
fi
echo "OK (fingerprint tests)"
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash nixos/tests/test-fingerprint.sh`
Expected: `FAIL fprintd is enabled` (module not written yet), exit 1.

- [ ] **Step 3: Write the module**

Create `nixos/hardware-devices/fingerprint.nix`:

```nix
# Fingerprint reader support and authentication semantics.
#
# Enables the fprintd daemon everywhere (idle on machines without a reader)
# and disables fprintd's PAM integration on every service. Fingerprint unlock
# is hyprlock's native fprintd integration (see hypr/hyprlock.conf, sourced
# from a per-user state file toggled by the Quickshell Identity Manager,
# SUPER+I). Enrollment happens per machine at runtime via the Identity
# Manager or fprintd-enroll; biometric templates live in /var/lib/fprint and
# are never in this repo.
{ config, lib, ... }:

let
  # fprintd's PAM module defaults to enabled on every service when the daemon
  # is on. Keeping it would add fingerprint prompts to sudo/su/sshd/polkit
  # (unattended approvals, CVE-2024-37408, plus pam_fprintd's 30 s fallback
  # delay). The assertion below fails the build if a nixpkgs update adds a
  # fingerprint-enabled service missing from this list.
  passwordOnly = [
    "chfn" "chpasswd" "chsh" "cups" "greetd"
    "groupadd" "groupdel" "groupmems" "groupmod"
    "hyprlock" "i3lock" "i3lock-color" "login" "other" "passwd" "polkit-1"
    "runuser" "runuser-l" "sshd" "su" "sudo"
    "swaylock" "systemd-run0" "systemd-user"
    "useradd" "userdel" "usermod"
    "vlock" "xlock" "xscreensaver"
  ];
in
{
  services.fprintd.enable = true;

  security.pam.services = lib.genAttrs passwordOnly (_: { fprintAuth = false; });

  assertions = [
    {
      assertion = lib.all (
        n: !(config.security.pam.services.${n}.enable && config.security.pam.services.${n}.fprintAuth)
      ) (lib.attrNames config.security.pam.services);
      message = ''
        fingerprint: a PAM service outside the password-only list enables fprintAuth.
        Update nixos/hardware-devices/fingerprint.nix (see its comments).
      '';
    }
  ];
}
```

- [ ] **Step 4: Import it**

In `nixos/configuration.nix`, in the `imports` list, add after `./hardware-devices/scanners.nix`:

```nix
    ./hardware-devices/fingerprint.nix
```

- [ ] **Step 5: Track the new flake file, then run the test to verify it passes**

```bash
git add nixos/hardware-devices/fingerprint.nix nixos/tests/test-fingerprint.sh
bash nixos/tests/test-fingerprint.sh
```

Expected: all `OK`, `OK (fingerprint tests)`.

- [ ] **Step 6: Add the test to the checks list**

In `AGENTS.md`, in the checks code block, add after `bash nixos/tests/test-sync-secrets.sh`:

```bash
bash nixos/tests/test-fingerprint.sh
```

- [ ] **Step 7: Commit**

```bash
git add nixos/hardware-devices/fingerprint.nix nixos/configuration.nix nixos/tests/test-fingerprint.sh AGENTS.md
git commit -m "feat(nixos): add fprintd with password-only PAM scoping"
```

---

### Task 3: hyprlock native fingerprint + config-order test

**Files:**
- Modify: `nixos/tests/test-fingerprint.sh` (append hyprlock.conf static checks)
- Modify: `hypr/hyprlock.conf` (append at end)

**Interfaces:**
- Consumes: the test script from Task 2.
- Produces: the state-file contract — `hypr/hyprlock.conf` ends with `source = ~/.local/state/hyprlock-fingerprint.conf`, and `auth:fingerprint:enabled` defaults to `true`.

- [ ] **Step 1: Extend the test with the static checks (failing first)**

In `nixos/tests/test-fingerprint.sh`, before the final failure summary (`if ((failures)); then`), add:

```bash
# hyprlock.conf: fingerprint enabled by default, override source last.
last_line=$(grep -v '^[[:space:]]*$' "$ROOT/hypr/hyprlock.conf" | tail -n 1)
if [[ "$last_line" == "source = ~/.local/state/hyprlock-fingerprint.conf" ]]; then
  echo "OK   hyprlock.conf ends with the state-file source line"
else
  echo "FAIL hyprlock.conf source line is not last (got: $last_line)"
  failures=$((failures + 1))
fi
if grep -A4 '^auth {' "$ROOT/hypr/hyprlock.conf" | grep -q 'enabled = true'; then
  echo "OK   hyprlock.conf enables fingerprint by default"
else
  echo "FAIL hyprlock.conf does not enable fingerprint"
  failures=$((failures + 1))
fi
```

- [ ] **Step 2: Run it to verify the new checks fail**

Run: `bash nixos/tests/test-fingerprint.sh`
Expected: the two new checks `FAIL`, exit 1.

- [ ] **Step 3: Edit hyprlock.conf**

Append to the end of `hypr/hyprlock.conf`:

```conf

# Fingerprint unlock — hyprlock talks to fprintd directly (no PAM module).
# The Quickshell Identity Manager (SUPER+I) maintains the override file
# below; this source line must stay last so the override wins. See
# quickshell/docs/superpowers/specs/2026-11-08-identity-manager-design.md.
auth {
    fingerprint {
        enabled = true
    }
}
source = ~/.local/state/hyprlock-fingerprint.conf
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash nixos/tests/test-fingerprint.sh`
Expected: all `OK`, `OK (fingerprint tests)`.

- [ ] **Step 5: Commit**

```bash
git add hypr/hyprlock.conf nixos/tests/test-fingerprint.sh
git commit -m "feat(hypr): fingerprint unlock in hyprlock via native fprintd"
```

---

### Task 4: identityParse.js + headless unit tests

**Files:**
- Create: `quickshell/tests/tst_identity_parse.qml`
- Create: `quickshell/services/identityParse.js`

**Interfaces:**
- Produces (pure functions, imported by `IdentityService.qml` and the test):
  - `FINGERS: string[]` — the ten fprintd finger names.
  - `parseEnrolled(text: string) -> string[]`
  - `listError(text: string) -> "" | "nodevice" | "daemon" | "listfail"`
  - `parseAuthEnabled(text: string) -> bool` (`"ABSENT"`/garbage → `true`)
  - `enrollStageLabel(status: string) -> string`
  - `fingerLabel(name: string) -> string`

- [ ] **Step 1: Write the failing test**

Create `quickshell/tests/tst_identity_parse.qml`:

```qml
import QtQuick
import QtTest
import "../services/identityParse.js" as Parse

// Pure-logic tests for the Identity Manager parsers
// (services/identityParse.js). Headless; no fprintd or reader needed.
TestCase {
    name: "IdentityParse"

    // --- parseEnrolled() ---
    // Formats are from fprintd 1.94.5 utils/list.c.
    function test_parses_enrolled_fingers() {
        const out = Parse.parseEnrolled(
            "found 1 devices\nDevice at /net/reactivated/Fprint/Device/0\n"
            + "Using device /net/reactivated/Fprint/Device/0\n"
            + "Fingerprints for user asergi on Synaptics Sensors (press):\n"
            + " - #0: right-index-finger\n - #1: left-thumb\n")
        compare(out.length, 2)
        compare(out[0], "right-index-finger")
        compare(out[1], "left-thumb")
    }

    function test_no_fingers_is_empty() {
        compare(Parse.parseEnrolled(
            "User asergi has no fingers enrolled for Synaptics Sensors.\n").length, 0)
    }

    function test_garbage_is_empty() {
        compare(Parse.parseEnrolled("").length, 0)
        compare(Parse.parseEnrolled("totally unrelated output").length, 0)
    }

    // --- listError() ---
    function test_no_device_error() {
        compare(Parse.listError("No devices available\n"), "nodevice")
    }
    function test_daemon_errors() {
        compare(Parse.listError("Impossible to get devices: GDBus.Error:org.freedesktop.DBus.Error.ServiceUnknown\n"), "daemon")
        compare(Parse.listError("Failed to connect to session bus: x\n"), "daemon")
        compare(Parse.listError("Failed to get Fprintd manager: x\n"), "daemon")
    }
    function test_list_failure() {
        compare(Parse.listError("ListEnrolledFingers failed: x\n"), "listfail")
    }
    function test_no_error_on_normal_output() {
        compare(Parse.listError("Fingerprints for user asergi on X (press):\n - #0: right-thumb\n"), "")
    }

    // --- parseAuthEnabled() ---
    function test_absent_means_enabled() {
        compare(Parse.parseAuthEnabled("ABSENT"), true)
        compare(Parse.parseAuthEnabled(""), true)
        compare(Parse.parseAuthEnabled("garbage"), true)
    }
    function test_reads_enabled_values() {
        compare(Parse.parseAuthEnabled("auth {\n    fingerprint {\n        enabled = false\n    }\n}\n"), false)
        compare(Parse.parseAuthEnabled("auth {\n    fingerprint {\n        enabled = true\n    }\n}\n"), true)
        compare(Parse.parseAuthEnabled("enabled = 0"), false)
        compare(Parse.parseAuthEnabled("enabled = 1"), true)
    }

    // --- enrollStageLabel() ---
    function test_stage_labels() {
        compare(Parse.enrollStageLabel("enroll-stage-passed"), "Stage passed - lift and place again")
        compare(Parse.enrollStageLabel("enroll-retry-scan"), "Please retry fingerprint scan")
        compare(Parse.enrollStageLabel("enroll-swipe-too-short"), "Swipe too short - try again")
        compare(Parse.enrollStageLabel("enroll-finger-not-centered"), "Finger not centered - try again")
        compare(Parse.enrollStageLabel("enroll-remove-and-retry"), "Remove your finger and try again")
        compare(Parse.enrollStageLabel("enroll-too-fast"), "Too fast - try again")
        compare(Parse.enrollStageLabel("enroll-completed"), "Enrolled")
        compare(Parse.enrollStageLabel("enroll-failed"), "Enrollment failed")
        compare(Parse.enrollStageLabel("enroll-duplicate"), "Finger already enrolled")
        compare(Parse.enrollStageLabel("enroll-data-full"), "Fingerprint storage full")
        compare(Parse.enrollStageLabel("enroll-disconnected"), "Device disconnected")
        compare(Parse.enrollStageLabel("enroll-unknown-error"), "Unknown error")
    }
    function test_unknown_stage_passthrough() {
        compare(Parse.enrollStageLabel("enroll-what"), "enroll-what")
    }

    // --- fingerLabel() / FINGERS ---
    function test_finger_labels() {
        compare(Parse.fingerLabel("right-index-finger"), "Right Index Finger")
        compare(Parse.fingerLabel("left-thumb"), "Left Thumb")
        compare(Parse.fingerLabel("weird"), "weird")
    }
    function test_fingers_list() {
        compare(Parse.FINGERS.length, 10)
        verify(Parse.FINGERS.indexOf("right-index-finger") !== -1)
        verify(Parse.FINGERS.indexOf("left-little-finger") !== -1)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash quickshell/tests/run.sh`
Expected: failure loading `identityParse.js` (module missing).

- [ ] **Step 3: Implement the parser**

Create `quickshell/services/identityParse.js` with the functions from the Interfaces block. Implementation notes:
- `parseEnrolled`: collect matches of `/^\s*-\s*#\d+:\s*(\S+)\s*$/m` in `text`; keep names contained in `FINGERS` (tolerates daemon wording changes).
- `listError`: case-insensitive substring checks; order: `nodevice` ("no devices available"), `daemon` ("impossible to get devices", "failed to connect to session bus", "failed to get fprintd manager"), `listfail` ("listenrolledfingers failed"), else `""`.
- `parseAuthEnabled`: regex `enabled\s*=\s*(true|false|1|0)` (last match wins); no match → `true`.
- `enrollStageLabel`: exact mapping from the test; unknown → the raw status.
- `fingerLabel`: split on `-`, capitalize words, join with spaces; unknown input passes through.
- Use `function`/`const` (ES module style, mirrors `screenCastParse.js`).

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash quickshell/tests/run.sh`
Expected: PASS (all suites, including the pre-existing ones).

- [ ] **Step 5: Commit**

```bash
git add quickshell/services/identityParse.js quickshell/tests/tst_identity_parse.qml
git commit -m "feat(identity): add fprintd output parsers with unit tests"
```

---

### Task 5: IdentityService singleton

**Files:**
- Create: `quickshell/services/IdentityService.qml`
- Modify: `quickshell/services/qmldir` (append singleton line)

**Interfaces:**
- Consumes: `identityParse.js` (Task 4).
- Produces (used by the launcher and shell wiring):
  - Properties: `fprintdAvailable`, `devicePresent`, `authEnabled`, `enrolled` (`[{ name, label }]`), `enrolling`, `enrollFinger`, `enrollStage`, `enrollMessage` (derived via `Parse.enrollStageLabel(enrollStage)`), `enrollPasses`, `enrollDone`, `lastError`; signal `dataUpdated()`.
  - Functions: `refresh()`, `setAuthEnabled(on)`, `enroll(finger)`, `cancelEnroll()`, `deleteFinger(finger)`.
  - Probe output contract: first line `BIN=0|1`, then the state-file content or `ABSENT`.

- [ ] **Step 1: Implement the service**

Create `quickshell/services/IdentityService.qml` (`pragma Singleton`, `QtObject`), modeled on `UsbService.qml` (queue-free; single-flight guards). Import the parser the way `ScreenCastService.qml` imports `screenCastParse.js` (grep it; same directory import). Processes:

| Process | Command | Handling |
|---|---|---|
| `probeProc` | `sh -c 'if command -v fprintd-enroll >/dev/null 2>&1 && command -v fprintd-list >/dev/null 2>&1 && command -v fprintd-delete >/dev/null 2>&1; then echo BIN=1; else echo BIN=0; fi; if [ -f "$HOME/.local/state/hyprlock-fingerprint.conf" ]; then cat "$HOME/.local/state/hyprlock-fingerprint.conf"; else echo ABSENT; fi'` | split first line; `authEnabled = Parse.parseAuthEnabled(rest)`; if `BIN=1` run `listProc`; if rest is `ABSENT` and not yet seeded, run `writeProc` with `FPRINT_ENABLED=true` (seed, once) |
| `listProc` | `sh -c 'fprintd-list "$(id -un)" 2>&1'` | `lastError = Parse.listError(text)` ("" on success); `devicePresent = lastError !== "nodevice" && lastError !== "daemon"`; `enrolled = Parse.parseEnrolled(text).map(n => ({ name: n, label: Parse.fingerLabel(n) }))`; `dataUpdated()` |
| `enrollProc` | `["fprintd-enroll", "-f", <finger>]`, stdout `SplitParser` | per line: match `/^Enroll result: (.+)$/` → `enrollStage = status`; `enroll-stage-passed` → `enrollPasses++`; `onExited(code)` → `enrollDone = (code === 0)`, `enrolling = false`, `refresh()` |
| `deleteProc` | `sh -c 'fprintd-delete "$(id -un)" -f "$FPRINT_FINGER" 2>&1'`, `environment: { FPRINT_FINGER: <finger> }` | on finish: if text contains "Failed to delete" → `lastError = text.trim()`; `refresh()` |
| `writeProc` | `sh -c 'mkdir -p "$HOME/.local/state" && printf '\''auth {\n    fingerprint {\n        enabled = %s\n    }\n}\n'\'' "$FPRINT_ENABLED" > "$HOME/.local/state/hyprlock-fingerprint.conf"'`, `environment: { FPRINT_ENABLED: "true"\|"false" }` | on finish: re-run `probeProc` |

Functions: `refresh()` → `probeProc.running = true`; `setAuthEnabled(on)` → `writeProc` with `on ? "true" : "false"`; `enroll(finger)` → set `enrolling=true`, `enrollFinger=finger`, `enrollPasses=0`, `enrollDone=false`, `enrollStage=""`, run `enrollProc`; `cancelEnroll()` → `enrollProc.running = false`, `enrolling=false`, `refresh()`; `deleteFinger(finger)` → guard `!enrolling`, set env, run `deleteProc`. `Component.onCompleted: refresh()`.

- [ ] **Step 2: Register the singleton**

Append to `quickshell/services/qmldir`:

```
singleton IdentityService 1.0 IdentityService.qml
```

- [ ] **Step 3: Verify QML parses cleanly**

Run: `quickshell -p "$PWD/quickshell"`
Expected: exit 0, no `file:line` errors.

- [ ] **Step 4: Commit**

```bash
git add quickshell/services/IdentityService.qml quickshell/services/qmldir
git commit -m "feat(identity): add IdentityService over fprintd CLIs and state file"
```

---

### Task 6: Normative spec and bookkeeping docs

**Files:**
- Create: `quickshell/specs/launchers/Identity-Manager.md`
- Modify: `quickshell/specs/launchers/Control-Center.md` (entries table: insert as #6 after Screen Cast, renumber, counts)
- Modify: `quickshell/specs/launchers/Key-Launcher.md` (Shell note: add `SUPER+I` if the note enumerates launcher keys)
- Modify: `quickshell/specs/SPECS.md` (§3.1 file layout: add `IdentityManager.qml` + `IdentityService.qml`; §5.2 table: `| Identity Manager | SUPER+I | launchers/Identity-Manager.md |`)
- Modify: `quickshell/specs/STYLE.md` (§3 Icons list: add fingerprint glyph; §5.1 card widths: add `IdentityManager 620`)
- Modify: `README.md` (short generic paragraph)

**Interfaces:**
- Consumes: the design doc §7–§8 (service contract, launcher behavior).
- Produces: the normative spec that Task 7 implements.

- [ ] **Step 1: Write `quickshell/specs/launchers/Identity-Manager.md`**

Mirror the structure of `launchers/Usb-Manager.md`: header line (`> Command: SUPER+I · File: components/launchers/IdentityManager.qml · Service: IdentityService.qml`), Purpose, Window (620 px card), Sections (Toggle · Enrolled fingers · Enroll flow), Shared behaviours/keys, Service contract block, Backend notes (fprintd CLI commands, state-file contract, native hyprlock linkage), Empty/Degraded states, Acceptance. Content comes from design §7–§8 and these pinned acceptance items:

```markdown
## Acceptance
* [ ] Toggle row flips the fingerprint state; the note “applies to the next lock” is visible; state survives reopen.
* [ ] Enrolled fingers list matches `fprintd-list`; empty state renders; delete asks `y/n` and refreshes.
* [ ] Enroll flow: picker lists 10 fingers; progress shows stage text + pass count; Esc cancels; completion refreshes the list; failure offers retry.
* [ ] Degraded states render for: fprintd missing, no reader, daemon errors, claim conflicts.
* [ ] Vim `j/k` + `/` filter + `Esc` stack work; card is 620 px; `Theme.*`/`Icons.*` only.
```

- [ ] **Step 2: Update Control-Center.md**

Insert into the entries table (normative order):

```markdown
| 6 | Identity | `SUPER+i` | `Icons.fingerprint` | `launcher.toggle("identity")` |
```

Renumber following rows (7–14) and update the acceptance count to "all 14 launchers".

- [ ] **Step 3: Update Key-Launcher.md, SPECS.md, STYLE.md**

- `Key-Launcher.md`: if the Shell source note lists keys (it mentions the screencast bind), add the `SUPER+I` identity bind in the same style.
- `SPECS.md` §3.1: add `IdentityManager.qml` to `components/launchers/` and `IdentityService.qml` to `services/`; §5.2: add the Identity Manager row.
- `STYLE.md` §3: add `property string fingerprint: String.fromCodePoint(0xF0237) // nf-md-fingerprint` to the glyph list; §5.1: append `IdentityManager 620` to the card-width line.

- [ ] **Step 4: README paragraph**

Add to the NixOS section:

```markdown
**Fingerprint (optional).** `services.fprintd` is enabled on every machine, so any machine with a reader can unlock hyprlock with a fingerprint once prints are enrolled. Manage it from the Identity Manager (`SUPER+I`): enable/disable, enroll, delete. Enrollment is per machine (templates live in `/var/lib/fprint`) and is never in this repo. On machines without a reader everything logs and falls back to the password.
```

- [ ] **Step 5: Run repo checks**

Run: `bash tests/check-no-hardcoded-home.sh && bash tests/test-user.sh && bash tests/test-guard.sh`
Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add quickshell/specs/launchers/Identity-Manager.md quickshell/specs/launchers/Control-Center.md \
        quickshell/specs/launchers/Key-Launcher.md quickshell/specs/SPECS.md quickshell/specs/STYLE.md README.md
git commit -m "docs(identity): add Identity Manager spec and bookkeeping"
```

---

### Task 7: IdentityManager launcher + glyph + Key Hints and Control Center entries

**Files:**
- Create: `quickshell/components/launchers/IdentityManager.qml`
- Modify: `quickshell/theme/Icons.qml` (add fingerprint glyph)
- Modify: `quickshell/components/launchers/KeyLauncher.qml` (Shell section row)
- Modify: `quickshell/components/launchers/ControlCenter.qml` (entries + dispatch target)

**Interfaces:**
- Consumes: `IdentityService` (Task 5) and the spec (Task 6).
- Produces: `IdentityManager { id: identityManager }` with `property bool isOpen` and `open()/close()/toggle()` for the shell wiring (Task 8); IPC target name `identity`.

- [ ] **Step 1: Add the glyph**

In `quickshell/theme/Icons.qml`:

```qml
property string fingerprint: String.fromCodePoint(0xF0237) // nf-md-fingerprint
```

Verify it renders: `quickshell -p "$PWD/quickshell"` still exits 0, and spot-check during the manual sweep that a fingerprint glyph (not a box) shows in the launcher.

- [ ] **Step 2: Implement `IdentityManager.qml`**

Follow `UsbManager.qml` for chrome (self-contained `WlrLayershell` overlay, centered 620 px card, footer hints, y/n confirm pattern) and `STYLE.md` §2.5 for the main↔enroll slide transition. Required behavior (spec is normative):
- Main view: toggle row (glyph + "Unlock with fingerprint" + Enabled/Disabled + "applies to the next lock"), enrolled-finger rows, `/` filter over finger rows, `j/k`/arrows/`Home`/`End`, `Enter` (toggle row → `setAuthEnabled`; finger row → delete confirm `y/n`), `t` toggle, `d` delete, `e`/`a` open enroll view, `r` refresh, `Esc` stack (filter → close). All actions guard on `IdentityService.fprintdAvailable` where appropriate.
- Enroll view: 10 finger rows from `Parse.FINGERS`/`fingerLabel` (enrolled ones marked), `Enter` → `IdentityService.enroll(name)`; progress panel with `enrollMessage = Parse.enrollStageLabel(enrollStage)`, pass count, `Esc` → `cancelEnroll()` back to picker; completion → "Enrolled" and main list refreshed; failure → message + `Enter retry · Esc back`.
- Degraded: banners for `!fprintdAvailable` ("fprintd unavailable"), `!devicePresent` ("No fingerprint reader detected"), `lastError` inline at `Theme.critical`; claim errors include a retry hint.
- No polling; reads via `IdentityService` + `Connections { onDataUpdated }`.

- [ ] **Step 3: Key Hints entry**

In `KeyLauncher.qml`, Shell section, after the `SUPER+K` Screen Cast row:

```qml
{ key: "SUPER+I", action: "Identity Manager", desc: "fingerprint" },
```

- [ ] **Step 4: Control Center entry**

In `ControlCenter.qml` entries, after the Screen Cast entry:

```qml
{ label: "Identity", key: "SUPER+i", icon: Icons.fingerprint, target: "identity" },
```

(`target: "identity"` dispatches through the existing `requestToggle` → IPC handler; Task 8 adds the handler branch.)

- [ ] **Step 5: Verify and commit**

Run: `quickshell -p "$PWD/quickshell"` (exit 0) and

```bash
grep -R "#[0-9a-fA-F]" --include="*.qml" quickshell/components quickshell/theme | grep -v "theme/Theme.qml"
```

(no new hits)

```bash
git add quickshell/components/launchers/IdentityManager.qml quickshell/theme/Icons.qml \
        quickshell/components/launchers/KeyLauncher.qml quickshell/components/launchers/ControlCenter.qml
git commit -m "feat(identity): add Identity Manager launcher, glyph, key hints and control center entry"
```

---

### Task 8: Shell wiring and the SUPER+I binding

**Files:**
- Modify: `quickshell/shell.qml` (mount + IPC branches)
- Modify: `hypr/hyprland.lua` (bind)

**Interfaces:**
- Consumes: `IdentityManager` (Task 7) and the `launcher` IpcHandler existing contract (target name `identity`).
- Produces: `quickshell ipc call launcher toggle identity` fully working.

- [ ] **Step 1: Mount and wire the launcher in shell.qml**

Add after `TrayManager { id: trayManager }`:

```qml
    IdentityManager { id: identityManager }
```

In `closeAllExcept`: `if (except !== "identity") identityManager.close()`. In `toggle`: `else if (name === "identity") { if (identityManager.isOpen) identityManager.close(); else { closeAllExcept("identity"); identityManager.open() } }`. In `closeAll` and `close(name)`: add the identity branch.

- [ ] **Step 2: Add the Hyprland bind**

In `hypr/hyprland.lua`, in the bottom quickshell block after the `SUPER+P` power bind:

```lua
hl.bind(mainMod .. " + I", hl.dsp.exec_cmd("quickshell ipc call launcher toggle identity"))
```

- [ ] **Step 3: Verify**

```bash
quickshell -p "$PWD/quickshell"
grep -n 'toggle identity' hypr/hyprland.lua
```

Expected: exit 0; the bind line found. (Live IPC test requires the merged config + a running shell; covered in the sweep.)

- [ ] **Step 4: Commit**

```bash
git add quickshell/shell.qml hypr/hyprland.lua
git commit -m "feat(identity): wire SUPER+I launcher through shell IPC"
```

---

### Task 9: Verification sweep

**Files:** none (verification only).

- [ ] **Step 1: Repo checks (from the worktree root)**

```bash
bash nixos/tests/test-fingerprint.sh
bash nixos/tests/test-bootstrap.sh
bash nixos/tests/test-sync-secrets.sh
bash tests/check-no-hardcoded-home.sh
bash tests/test-user.sh
bash tests/test-guard.sh
bash quickshell/tests/run.sh
```

Expected: all pass.

- [ ] **Step 2: Flake check and dry-build against the real machine layer**

```bash
nix flake check ./nixos --no-write-lock-file
DOTFILES_MACHINE_DIR=/etc/nixos nixos-rebuild dry-build --flake ./nixos#default --impure
```

Expected: clean eval/build. If the executor cannot run these, hand them to the user with the exact commands.

- [ ] **Step 3: QML hygiene greps**

```bash
quickshell -p "$PWD/quickshell"
grep -R "#[0-9a-fA-F]" --include="*.qml" quickshell/components quickshell/theme | grep -v "theme/Theme.qml"
```

Expected: clean / no hits.

- [ ] **Step 4: Hand the user the manual checklist (hardware-dependent)**

State plainly what was and wasn't verified, then have the user run, after merging and `update`:

1. BIOS: `Advanced → Built-in Device Options → Fingerprint Device` enabled; `lsusb | grep -i 06cb` shows `06cb:00f0`.
2. `SUPER+I` → enroll right index (progress stages, completion).
3. `SUPER+X` → fingerprint prompt shows; unlock works; password also works.
4. Toggle off → next lock shows password only (no prompt); toggle on → prompt returns.
5. Delete a finger; enroll two fingers; `Esc` mid-enroll, then re-enroll immediately (claim-conflict path).
6. If the reader never enumerates: the launcher's "No fingerprint reader detected" state is the expected (correct) result.

---

## Self-review notes

- Spec coverage: every design §2 goal maps to tasks (unlock → 2/3; toggle → 3/5/7; list/enroll/delete → 4/5/7; SUPER+I + hints + control center → 6/7/8; generic + degraded → 2/5/7; tests → 2/3/4/9).
- Interfaces: `identityParse.js` names and `IdentityService` members are used verbatim in Tasks 4–8; card width 620 and the state-file path are identical across tasks 3/6/7.
- Review Focus items each have an owning test: state file → Task 4 unit tests + Task 5 seed logic; no-reader degrade → Task 4 `listError` + Task 7 banners; cancel/claim → Task 7 + manual step 5; PAM drift → Task 2 assertion test; config ordering → Task 3 static check.
