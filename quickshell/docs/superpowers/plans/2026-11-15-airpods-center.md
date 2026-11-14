# AirPods Center Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add native AirPods 5 support to the Quickshell shell: per-pod/case battery, listening modes, Adaptive level, Conversation Awareness, One-Bud ANC and ear detection, with a bar badge and a `SUPER+ALT+A` launcher.

**Architecture:** A pinned build of the omarchy-pods librepods daemon (GPL-3.0) speaks Apple AAP and publishes `~/.local/state/librepods/status.json`. A new `AirPodsService` watches that file and calls `librepods-ctl`; it starts/stops a `librepods.service` user unit while the AirPods are connected or the panel is open. A dedicated `AirPodsCenter` launcher and a bar badge read the service. Pure JS modules own the status parser, the lifecycle decision and the `bluetoothctl info` UUID parsing, so all logic is unit-tested offscreen.

**Tech Stack:** NixOS/home-manager, Qt 6.11, Quickshell 0.3.x QML, Qt Quick Test, bash smoke tests, a GPL-3.0 C++ daemon from the omarchy-pods fork.

**Spec:** `quickshell/docs/superpowers/specs/2026-11-15-airpods-center-design.md`

## Global Constraints

- Repo root is the worktree `/home/asergi/.local/share/opencode/worktree/b53491/airpods-center` (branch `airpods-center`). All paths below are relative to it; the QML root is `quickshell/`.
- Never touch `~/dotfiles`, `/etc/nixos` or `~/.config/sops`. No `nixos-rebuild switch` and no `nix-env`; `nix build`, `nix eval` and `nixos-rebuild dry-build` are allowed.
- `git add` every new file before any `nix eval`/`nix build` of the flake: a flake only sees tracked files.
- No hard-coded colours or glyphs outside `quickshell/theme/Theme.qml` and `Icons.qml`. Use `Theme.*` and `Icons.*`. State is shown by borders/text, not colour alone where the spec says so.
- One `Process` per subsystem inside `quickshell/services/`; views and launchers never start processes or poll. The daemon is started only through `systemctl --user` from `AirPodsService`.
- Launcher: centred card 620 px, `Theme.roundingLauncher`, `Esc` closes, `j/k` moves, `/` filters, `Enter` acts.
- The daemon is GPL-3.0 and stays a separate program. The UI's `airPodsParse.js` is adapted from the MIT omarchy-pods `Model.js` with a header attribution; the Omarchy `Panel.qml` and Apple's AirPods outlines are not copied.
- Pairing keys live only in `~/.config/AirPodsTrayApp/AirPodsTrayApp.conf`, mode 0600. Never print, log, test-output or commit them. They are not user-provided credentials, so no SOPS template change.
- The live AirPods are the test device. A live test is allowed (the user approved one on 2026-11-15), but it must stop the daemon, remove temporary state and report the codec change. Do not run it while a call or a capture stream is active unless the user says so.
- Keybind is `SUPER+ALT+A`: `SUPER+SHIFT+A` is already Notifications in both `hyprland.lua` and `ControlCenter.qml`, and the only `SUPER+ALT` binds are the `h/j/k/l` window swaps.
- Commits use Conventional Commits and no `--no-verify`. Do not commit until the user approves executing this plan. If the execution method is subagent-driven, the repo's `AGENTS.md` requires asking the user for a model and provider per agent first.

## Review Focus

1. **Malformed/empty/too-new `status.json`**: the panel must show one readable line, keep `daemonActive` true, and never crash or start a second daemon. Tested in Task 2 and Task 5.
2. **AirPods disconnect/reconnect while the panel is open**: battery returns, the daemon stops/starts, no duplicate daemons and no start loop after a failure. Tested in Task 3 and Task 5; exercised live in Task 10.
3. **`librepods-ctl` missing or failing**: battery and status still render; the ctl error is visible; a mode key does not silently no-op. Tested in Task 5 and Task 6.
4. **Unknown/future model**: battery still shows; the panel falls back to the daemon's capability flags; no phantom Adaptive/CA/One-Bud rows. Tested in Task 2 and Task 6.
5. **Slow/failing `bluetoothctl info`**: the existing Bluetooth list, scan and pairing still work; `isAirPods` is false; no new timer or polling storm. Tested in Task 4 and Task 10.

## File Map

| File | Status | Responsibility |
|---|---|---|
| `nixos/programs/librepods.nix` | new | Pinned omarchy-pods daemon derivation, AirPods 5 patch |
| `nixos/patches/librepods-airpods5.patch` | new | `AirPodsModel::AirPods5`, six model numbers, BLE `0x3020`, H2/One-Bud capabilities |
| `nixos/programs/quickshell.nix` | modify | Import and package `librepods`; `librepods.service` user unit; `home.packages` |
| `quickshell/services/airPodsParse.js` | new | Pure status parser, capability gating, verbs/labels |
| `quickshell/services/airPodsLifecycle.js` | new | Pure `shouldRun`/`nextAction` decision |
| `quickshell/services/bluetoothParse.js` | new | Pure `bluetoothctl info` block/UUID parser |
| `quickshell/services/AirPodsService.qml` | new | Status, ctl verbs, daemon lifecycle, optimistic settle |
| `quickshell/services/BluetoothService.qml` | modify | Add `uuids`/`isAirPods` from the existing poll |
| `quickshell/services/qmldir` | modify | `singleton AirPodsService` |
| `quickshell/components/launchers/airpods/AirPodsView.qml` | new | Card content, sections, key routing, filter, degraded states |
| `quickshell/components/launchers/AirPodsCenter.qml` | new | `WlrLayershell` overlay, open/close, service lifecycle hooks |
| `quickshell/components/bar/AirPodsIcon.qml` | new | Bar badge + tooltip |
| `quickshell/components/bar/Bar.qml` | modify | Insert the badge after Audio |
| `quickshell/theme/Icons.qml` | modify | `Icons.airpods` (nf-md-earbuds U+F184F) |
| `quickshell/shell.qml` | modify | `AirPodsCenter`, IPC toggle/close/closeAll |
| `quickshell/components/launchers/ControlCenter.qml` | modify | AirPods entry with `SUPER+ALT+A` |
| `hypr/hyprland.lua` | modify | `SUPER+ALT+A` bind |
| `quickshell/tests/tst_airpods_parse.qml` | new | Parser unit tests |
| `quickshell/tests/tst_airpods_lifecycle.qml` | new | Lifecycle decision tests |
| `quickshell/tests/tst_bluetooth_parse.qml` | new | `bluetoothctl info` parser tests |
| `quickshell/tests/smoke/airpods.qml` | new | Offscreen service/view/badge smoke shell |
| `quickshell/tests/smoke-airpods.sh` | new | Temporary config root, fixture, stub `librepods-ctl`, runs the smoke |
| `quickshell/specs/launchers/AirPods-Center.md` | new | Normative launcher spec |
| `quickshell/specs/bar/AirPods.md` | new | Normative bar badge spec |
| `quickshell/specs/SPECS.md` | modify | Dependency, inventory, bar order, build order |
| `quickshell/AGENTS.md` | modify | Read-order rows for the two new specs |

---

## Task 0: Commit the approved design and this plan

- [ ] **Step 1: Stage and commit the docs**

```bash
git add quickshell/docs/superpowers/specs/2026-11-15-airpods-center-design.md \
        quickshell/docs/superpowers/plans/2026-11-15-airpods-center.md
git commit -m "docs: add AirPods Center design and plan"
```

---

## Task 1: Package the daemon, patch AirPods 5, add the user unit

**Files:**
- Create: `nixos/programs/librepods.nix`
- Create: `nixos/patches/librepods-airpods5.patch`
- Modify: `nixos/programs/quickshell.nix` (`let` block, `home.packages`, `systemd.user.services`)

**Interfaces:**
- Produces: `librepods` derivation with `bin/librepods` and `bin/librepods-ctl`; user unit `librepods.service` with `ExecStart = "${librepods}/bin/librepods --headless"`, not enabled at login.
- Consumes: nothing from earlier tasks.

- [ ] **Step 1: Write `librepods.nix` without a patch, and build it**

```nix
{ lib, stdenv, fetchFromGitHub, cmake, pkg-config, qt6, libpulseaudio, openssl }:

stdenv.mkDerivation (finalAttrs: {
  pname = "librepods";
  version = "unstable-2026-09-14";

  src = fetchFromGitHub {
    owner = "thisisgm";
    repo = "omarchy-pods";
    rev = "f35dbc451b386d5ecebf50436ee4a49def059735";
    hash = "sha256-Wjg+Iq16abzIQnv0RbnvyHxJYqKYJBMeoSNmLrgMLDc=";
  };

  sourceRoot = "source/daemon";

  nativeBuildInputs = [ cmake pkg-config qt6.wrapQtAppsHook ];
  buildInputs = [ libpulseaudio openssl qt6.qtbase qt6.qtconnectivity qt6.qtdeclarative qt6.qtquick3d qt6.qttools ];
  cmakeFlags = [ "-DBUILD_TESTING=OFF" ];

  meta = {
    description = "AirPods daemon from omarchy-pods (librepods fork)";
    homepage = "https://github.com/thisisgm/omarchy-pods";
    license = lib.licenses.gpl3Only;
    mainProgram = "librepods";
    platforms = lib.platforms.linux;
  };
})
```

Build it:

```bash
nix build --impure --no-link --print-out-paths --expr '
let pkgs = (builtins.getFlake "nixpkgs").legacyPackages.x86_64-linux;
in pkgs.callPackage ./nixos/programs/librepods.nix {}'
```

Expected: a store path; `bin/librepods` and `bin/librepods-ctl` exist.

- [ ] **Step 2: Confirm the pre-patch binary has no AirPods 5 name**

```bash
out=$(nix build --impure --no-link --print-out-paths --expr '
let pkgs = (builtins.getFlake "nixpkgs").legacyPackages.x86_64-linux;
in pkgs.callPackage ./nixos/programs/librepods.nix {}')
strings "$out/bin/.librepods-wrapped" | grep -F "AirPods 5"
```

Expected: `grep` exits 1, no output. This is the failing test for the patch.

- [ ] **Step 3: Create `nixos/patches/librepods-airpods5.patch`**

The patch applies from `source/daemon` (paths `a/enums.h`, `a/ble/blemanager.cpp`). It makes exactly these changes:

1. `enums.h`, `enum class AirPodsModel`: append `AirPods5` after `AirPodsMax2`, keeping the "Appended, never inserted" comment.
2. `enums.h`, `parseModelNumber`: add `A3531`, `A3532`, `A3533` (base AirPods 5) and `A3439`, `A3440`, `A3441` (wireless charging case) → `AirPods5`, with a comment naming both variants.
3. `enums.h`, `getModelIcon`: add `case AirPodsModel::AirPods5:` to the `AirPods4`/`AirPods4ANC` group (`pod3.png`, `pod4_case.png`).
4. `enums.h`, `modelDisplayName`: add `case AirPodsModel::AirPods5: return QStringLiteral("AirPods 5");`.
5. `enums.h`, `supportsNoiseControl`: add `case AirPodsModel::AirPods5:` to the true cases.
6. `enums.h`, `hasH2ListeningFeatures`: add `case AirPodsModel::AirPods5:` to the true cases.
7. `enums.h`, `supportsOneBudANC`: add `case AirPodsModel::AirPods5:` to the true cases.
8. `ble/blemanager.cpp`, `modelMap`: add `{0x3020, AirPodsModel::AirPods5},` after the `0x2720` Pro 3 entry (add the missing comma to that entry).

Generate the diff from a throwaway copy of the pinned source, then copy it to the patch path:

```bash
src=/nix/store/8wcwrw92hip5cid89m4a4v8f1rh6d024-source/daemon
tmp=$(mktemp -d); cp -r "$src" "$tmp/a"; cp -r "$src" "$tmp/b"
# edit "$tmp/b/..." with the eight changes above
(cd "$tmp" && diff -u -r a b > /home/asergi/.local/share/opencode/worktree/b53491/airpods-center/nixos/patches/librepods-airpods5.patch)
```

- [ ] **Step 4: Add the patch to `librepods.nix` and rebuild**

Add `patches = [ ../patches/librepods-airpods5.patch ];` and re-run the build.

Then:

```bash
out=$(nix build --impure --no-link --print-out-paths --expr '
let pkgs = (builtins.getFlake "nixpkgs").legacyPackages.x86_64-linux;
in pkgs.callPackage ./nixos/programs/librepods.nix {}')
strings "$out/bin/.librepods-wrapped" | grep -F "AirPods 5"
```

Expected: the string is printed and `grep` exits 0.

- [ ] **Step 5: Add the package, `home.packages` entry and user unit to `quickshell.nix`**

At the top `let` block:

```nix
librepods = pkgs.callPackage ./librepods.nix { };
```

In `home.packages`:

```nix
librepods             # AirPods AAP daemon + librepods-ctl for AirPodsService
```

Add the unit after the existing `gnome-network-displays-daemon` service:

```nix
  # AirPods daemon. Started and stopped on demand by AirPodsService; not
  # enabled at login, so it costs nothing while the AirPods are away.
  systemd.user.services.librepods = {
    Unit = {
      Description = "librepods AirPods daemon";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      Type = "simple";
      ExecStart = "${librepods}/bin/librepods --headless";
      Restart = "on-failure";
      RestartSec = 5;
      UMask = "0077";
      StateDirectory = "librepods";
      StateDirectoryMode = "0700";
      ConfigurationDirectory = "AirPodsTrayApp";
      ConfigurationDirectoryMode = "0700";
      ProtectSystem = "strict";
      ProtectHome = "read-only";
      ReadWritePaths = [ "%t" ];
      PrivateTmp = true;
      NoNewPrivileges = true;
      CapabilityBoundingSet = [ "" ];
      RestrictSUIDSGID = true;
      RestrictNamespaces = true;
      LockPersonality = true;
      SystemCallArchitectures = "native";
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectKernelLogs = true;
      ProtectControlGroups = true;
      ProtectClock = true;
      ProtectHostname = true;
      RestrictAddressFamilies = [ "AF_UNIX" "AF_BLUETOOTH" "AF_NETLINK" ];
      Environment = [
        "PATH=${librepods}/bin:${pkgs.bluez}/bin:${pkgs.coreutils}/bin"
        "QT_LOGGING_RULES=openpods.debug=false"
      ];
    };
  };
```

- [ ] **Step 6: Verify the module evaluates**

```bash
git add nixos/programs/librepods.nix nixos/patches/librepods-airpods5.patch nixos/programs/quickshell.nix
nix flake check ./nixos --no-write-lock-file
```

Expected: evaluation succeeds. The full `dry-build` runs in Task 10.

- [ ] **Step 7: Commit**

```bash
git add nixos/programs/librepods.nix nixos/patches/librepods-airpods5.patch nixos/programs/quickshell.nix
git commit -m "feat(nix): package librepods with AirPods 5 support"
```

---

## Task 2: Status parser and unit tests

**Files:**
- Create: `quickshell/services/airPodsParse.js`
- Create: `quickshell/tests/tst_airpods_parse.qml`

**Interfaces:**
- Produces (all top-level functions in a `.pragma library` file):

```js
const NOISE_OFF = 0, NOISE_ANC = 1, NOISE_TRANSPARENCY = 2, NOISE_ADAPTIVE = 3
const LID_OPEN = 0, LID_CLOSED = 1, LID_UNKNOWN = 2
const EAR_PAUSE_ONE_OUT = 0, EAR_PAUSE_BOTH_OUT = 1, EAR_DISABLED = 2
const LEVEL_UNKNOWN = -1, SUPPORTED_SCHEMA = 1

function defaultPod() -> { level, charging, inEar }
function defaultStatus() -> Status
function parseStatus(raw: string) -> Status
function availableModes(hasNoiseControl: bool, hasOff: bool, hasAdaptive: bool) -> int[]
function noiseModeName(mode: int) -> string
function noiseModeVerb(mode: int) -> string
function earDetectionVerb(behavior: int) -> string
function earDetectionName(behavior: int) -> string
function levelText(level: int) -> string
function levelFraction(level: int) -> number
function lidText(lidState: int) -> string
function podMeta(pod) -> string
function elideError(text: string) -> string
```

`Status` fields: `ok`, `lastError`, `schemaVersion`, `schemaTooNew`, `connected`, `deviceName`, `modelName`, `modelNumber`, `isProSeries`, `isHeadset`, `supportsNoiseOff`, `supportsNoiseControl`, `supportsAdaptive`, `supportsConversationalAwareness`, `supportsOneBudANC`, `noiseMode`, `adaptiveNoiseLevel`, `oneBudANC`, `conversationalAwareness`, `earDetectionBehavior`, `lidState`, `left`, `right`, `caseBattery`, `headsetBattery`.

- [ ] **Step 1: Write the failing tests**

Create `quickshell/tests/tst_airpods_parse.qml` with this fixture:

```qml
readonly property string fixture: '{"schema_version":1,"connected":true,"device_name":"Test AirPods","model_name":"AirPods 5","model_number":"A3439","is_pro_series":false,"is_headset":false,"supports_noise_off":true,"supports_noise_control":true,"supports_adaptive":true,"supports_conversational_awareness":true,"supports_one_bud_anc":true,"noise_mode":1,"adaptive_noise_level":60,"one_bud_anc_mode":true,"conversational_awareness":true,"ear_detection_behavior":0,"lid_state":0,"left":{"available":true,"charging":false,"in_ear":true,"level":93},"right":{"available":true,"charging":true,"in_ear":false,"level":97},"case":{"available":true,"charging":false,"level":82},"headset":{"available":false,"charging":false,"level":0}}'
```

Test cases and assertions:

| Test | Assertion |
|---|---|
| `test_empty_file` | `ok === false`, `lastError` non-empty |
| `test_non_json` | `ok === false`, `lastError` non-empty |
| `test_missing_schema` | `ok === false`, `lastError` mentions `schema_version` |
| `test_newer_schema` | `ok === false`, `schemaTooNew === true`, `lastError` mentions the version |
| `test_disconnected` | `ok === true`, `connected === false`, `left.level === -1` |
| `test_airpods5_fixture` | `modelName === "AirPods 5"`, `modelNumber === "A3439"`, `noiseMode === 1`, `left.level === 93`, `left.inEar === true`, `right.level === 97`, `right.charging === true`, `caseBattery.level === 82`, `adaptiveNoiseLevel === 60`, `conversationalAwareness === true`, `oneBudANC === true`, `lidState === 0` |
| `test_headset_fixture` | a fixture with `is_headset:true` and a `headset` object yields `isHeadset === true`, `headsetBattery.level`, and `caseBattery.level === -1` |
| `test_available_false_pod` | a pod with `available:false` yields `level === -1`, `charging === false`, `inEar === false` |
| `test_capability_fallbacks` | a fixture without `supports_*` and with `is_pro_series:true` yields `supportsNoiseControl === true`, `supportsNoiseOff === true`, `supportsAdaptive === true`, `supportsConversationalAwareness === true`, `supportsOneBudANC === true` |
| `test_available_modes` | `[0,2,3,1]` for all; `[2,1]` without Off/Adaptive; `[]` without noise control |
| `test_verbs` | `noiseModeVerb(1) === "noise:anc"`, `earDetectionVerb(1) === "ear:both"`, unknown mode → `""` |
| `test_labels` | `noiseModeName(2) === "Transparency"`, `earDetectionName(2) === "Never pause"`, `levelText(-1) === "--"`, `levelFraction(-1) === 0`, `lidText(0) === "Open"`, `podMeta({charging:true}) === "Charging"` |
| `test_elide_error` | a 200-char string is 137 chars + `…` |
| `test_default_status` | every field exists and the pods are `LEVEL_UNKNOWN` |

Run:

```bash
bash quickshell/tests/run.sh
```

Expected: FAIL — `AirPodsParse` cannot import `airPodsParse.js`.

- [ ] **Step 2: Implement `airPodsParse.js`**

Adapt the pure functions from the MIT `Model.js` at the pinned commit (`https://raw.githubusercontent.com/thisisgm/omarchy-pods/f35dbc451b386d5ecebf50436ee4a49def059735/Model.js`). Keep the header:

```js
// Adapted from omarchy-pods Model.js (MIT), commit f35dbc4.
```

Follow the Interfaces block exactly. The parser rules:

- `parseStatus` returns `defaultStatus()` with a readable `lastError` on empty, non-JSON, missing `schema_version`, or `schema_version > 1` (set `schemaTooNew`).
- Pods use `available !== true → LEVEL_UNKNOWN` and reset charging/inEar.
- Case/headset are `{ level, charging }`; a missing object becomes unknown.
- Capability keys fall back to the old behavior when absent: `supportsNoiseControl` true, `supportsNoiseOff` true, `supportsAdaptive`/`supportsConversationalAwareness`/`supportsOneBudANC` from `isProSeries`.
- `availableModes` returns Off (when allowed), Transparency, Adaptive (when allowed), ANC.
- `levelFraction` clamps to 0..1; `levelText` returns `--` for unknown.

- [ ] **Step 3: Run the tests to verify they pass**

```bash
bash quickshell/tests/run.sh
```

Expected: all tests pass, including `AirPodsParse`.

- [ ] **Step 4: Commit**

```bash
git add quickshell/services/airPodsParse.js quickshell/tests/tst_airpods_parse.qml
git commit -m "feat(quickshell): parse librepods AirPods status"
```

---

## Task 3: Daemon lifecycle decision and tests

**Files:**
- Create: `quickshell/services/airPodsLifecycle.js`
- Create: `quickshell/tests/tst_airpods_lifecycle.qml`

**Interfaces:**
- Produces:

```js
function shouldRun(connectedAirPods: bool, panelOpen: bool, statusConnected: bool) -> bool
function nextAction(want: bool, active: bool) -> "start" | "stop" | "none"
```

- [ ] **Step 1: Write the failing tests**

```qml
import QtQuick
import QtTest
import "../services/airPodsLifecycle.js" as Lifecycle

TestCase {
    name: "AirPodsLifecycle"
    function test_runs_when_airpods_connected() { compare(Lifecycle.shouldRun(true, false, false), true) }
    function test_runs_when_panel_open() { compare(Lifecycle.shouldRun(false, true, false), true) }
    function test_runs_when_status_still_connected() { compare(Lifecycle.shouldRun(false, false, true), true) }
    function test_idle_when_nothing_wants_it() { compare(Lifecycle.shouldRun(false, false, false), false) }
    function test_start_when_wanted_and_inactive() { compare(Lifecycle.nextAction(true, false), "start") }
    function test_stop_when_unwanted_and_active() { compare(Lifecycle.nextAction(false, true), "stop") }
    function test_none_when_in_sync() { compare(Lifecycle.nextAction(true, true), "none"); compare(Lifecycle.nextAction(false, false), "none") }
}
```

Run:

```bash
bash quickshell/tests/run.sh
```

Expected: FAIL — file missing.

- [ ] **Step 2: Implement `airPodsLifecycle.js`**

```js
.pragma library

function shouldRun(connectedAirPods, panelOpen, statusConnected) {
    return connectedAirPods === true || panelOpen === true || statusConnected === true
}

function nextAction(want, active) {
    if (want === true && active !== true) return "start"
    if (want !== true && active === true) return "stop"
    return "none"
}
```

- [ ] **Step 3: Run the tests**

```bash
bash quickshell/tests/run.sh
```

Expected: all pass.

- [ ] **Step 4: Commit**

```bash
git add quickshell/services/airPodsLifecycle.js quickshell/tests/tst_airpods_lifecycle.qml
git commit -m "feat(quickshell): decide when the AirPods daemon runs"
```

---

## Task 4: BluetoothService `isAirPods`

**Files:**
- Create: `quickshell/services/bluetoothParse.js`
- Create: `quickshell/tests/tst_bluetooth_parse.qml`
- Modify: `quickshell/services/BluetoothService.qml` (`pollProc.command` and the device mapping)

**Interfaces:**
- Produces:

```js
const AIRPODS_UUID = "74ec2172-0bad-4d01-8f77-997b2be0722a"
function parseInfo(text: string) -> { [address: string]: { uuids: string[], isAirPods: bool } }
function isAirPods(uuids: string[]) -> bool
```

- [ ] **Step 1: Write the failing tests**

Use this fixture:

```qml
readonly property string info: "===INFO:88:10:32:1B:01:34\nDevice 88:10:32:1B:01:34 (public)\nUUID: Service Discovery Serve.. (00001000-0000-1000-8000-00805f9b34fb)\nUUID: Vendor specific           (74ec2172-0bad-4d01-8f77-997b2be0722a)\n===INFO:AA:BB:CC:DD:EE:FF\nDevice AA:BB:CC:DD:EE:FF (public)\nUUID: Audio Sink                (0000110b-0000-1000-8000-00805f9b34fb)\n"
```

Test cases:

| Test | Assertion |
|---|---|
| `test_parse_blocks` | map has `88:10:32:1B:01:34` and `AA:BB:CC:DD:EE:FF` (uppercase keys) |
| `test_airpods_uuid` | the first block has `isAirPods === true` and its `uuids` contains `74ec2172-...` |
| `test_non_airpods` | the second block has `isAirPods === false` |
| `test_empty` | `parseInfo("")` is `{}` |
| `test_is_airpods_helper` | `isAirPods([AIRPODS_UUID]) === true`, `isAirPods([]) === false` |

Run:

```bash
bash quickshell/tests/run.sh
```

Expected: FAIL — file missing.

- [ ] **Step 2: Implement `bluetoothParse.js`**

Parse `===INFO:<address>` blocks, extract every `UUID: ... (<uuid>)` line, lowercase the UUIDs, and set `isAirPods` when the AAP UUID is present. Keys are uppercase addresses.

- [ ] **Step 3: Add the info section to `BluetoothService.pollProc`**

Replace the current command with:

```qml
command: ["sh", "-c", "bluetoothctl show 2>/dev/null; echo '---SECTION:CONNECTED---'; bluetoothctl devices Connected 2>/dev/null; echo '---SECTION:PAIRED---'; bluetoothctl devices Paired 2>/dev/null; echo '---SECTION:ALL---'; bluetoothctl devices 2>/dev/null; echo '---SECTION:INFO---'; bluetoothctl devices Connected 2>/dev/null | while read -r _ a rest; do echo \"===INFO:$a\"; bluetoothctl info \"$a\" 2>/dev/null; done"]
```

In the `StdioCollector`:

```qml
const infoSec = (txt.split("---SECTION:INFO---")[1] || "")
const info = BluetoothParse.parseInfo(infoSec)
```

Add to each device in `devs`:

```qml
uuids: info[a] ? info[a].uuids : [],
isAirPods: info[a] ? info[a].isAirPods : false
```

Add `import "bluetoothParse.js" as BluetoothParse` at the top of `BluetoothService.qml` (the service already has `import Quickshell.Io`; a plain JS import belongs next to it).

- [ ] **Step 4: Run the tests**

```bash
bash quickshell/tests/run.sh
```

Expected: all pass.

- [ ] **Step 5: Verify the live Bluetooth list still parses**

```bash
bluetoothctl info 2>/dev/null | head -5
```

Then run the shell in Task 10; the existing Bluetooth Center must still show the device and `BluetoothService.devices[0].isAirPods` must be true for the connected AirPods.

- [ ] **Step 6: Commit**

```bash
git add quickshell/services/bluetoothParse.js quickshell/tests/tst_bluetooth_parse.qml quickshell/services/BluetoothService.qml
git commit -m "feat(quickshell): flag AirPods from the BlueZ AAP UUID"
```

---

## Task 5: AirPodsService and offscreen service smoke

**Files:**
- Create: `quickshell/services/AirPodsService.qml`
- Modify: `quickshell/services/qmldir`
- Create: `quickshell/tests/smoke/airpods.qml`
- Create: `quickshell/tests/smoke-airpods.sh`

**Interfaces:**
- Consumes: `airPodsParse.js`, `airPodsLifecycle.js`, `BluetoothService.isAirPods`.
- Produces (singleton):

```qml
property bool daemonReachable
property bool daemonStarting
property bool daemonActive
property string lifecycleError
property bool connected
property string deviceName
property string modelName
property string modelNumber
property bool isProSeries
property bool isHeadset
property bool supportsNoiseOff
property bool supportsNoiseControl
property bool supportsAdaptive
property bool supportsConversationalAwareness
property bool supportsOneBudANC
property int noiseMode
property int adaptiveNoiseLevel
property bool oneBudANC
property bool conversationalAwareness
property int earDetectionBehavior
property int lidState
property var leftPod
property var rightPod
property var caseBattery
property var headsetBattery
property string lastError
property string actionStatus
readonly property bool hasAirPods: connected
readonly property bool hasBattery: /* true when a level is known */
readonly property bool busy: ctlProcess.running

function availableModes() -> int[]
function refresh() -> void
function setNoiseMode(mode: int) -> void
function setAdaptiveNoiseLevel(level: int) -> void
function setConversationalAwareness(enabled: bool) -> void
function setOneBudANC(enabled: bool) -> void
function setEarDetectionBehavior(behavior: int) -> void
function cycleNoiseMode() -> void
function cycleEarDetection() -> void
function notePanelOpen() -> void
function notePanelClosed() -> void
function reconcile() -> void
```

Test hooks (environment, tests only): `AIRPODS_STATE` (status file path), `AIRPODS_CTL` (ctl binary), `AIRPODS_NO_LIFECYCLE=1` (skip `systemctl`).

- [ ] **Step 1: Write the failing smoke harness**

Create `quickshell/tests/smoke-airpods.sh` following `tests/smoke-vpn-views.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
root="$tmp/qs"
mkdir -p "$root"
cp -r "$here/../components" "$here/../services" "$here/../theme" "$root/"
cp "$here/smoke/airpods.qml" "$root/shell.qml"

mkdir -p "$tmp/state/librepods" "$tmp/bin"
cat > "$tmp/state/librepods/status.json" <<'JSON'
{"schema_version":1,"connected":true,"device_name":"Test AirPods","model_name":"AirPods 5","model_number":"A3439","is_pro_series":false,"is_headset":false,"supports_noise_off":true,"supports_noise_control":true,"supports_adaptive":true,"supports_conversational_awareness":true,"supports_one_bud_anc":true,"noise_mode":3,"adaptive_noise_level":60,"one_bud_anc_mode":true,"conversational_awareness":true,"ear_detection_behavior":0,"lid_state":0,"left":{"available":true,"charging":false,"in_ear":true,"level":93},"right":{"available":true,"charging":true,"in_ear":false,"level":97},"case":{"available":true,"charging":false,"level":82},"headset":{"available":false,"charging":false,"level":0}}
JSON
cat > "$tmp/bin/librepods-ctl" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >> "$AIRPODS_CTL_LOG"
case "$*" in
  ear:both|ear:off) echo "stub failure" >&2; exit 1 ;;
esac
exit 0
STUB
chmod +x "$tmp/bin/librepods-ctl"
: > "$tmp/ctl.log"

HOME="$tmp" XDG_STATE_HOME="$tmp/state" PATH="$tmp/bin:$PATH" \
  AIRPODS_STATE="$tmp/state/librepods/status.json" \
  AIRPODS_CTL="$tmp/bin/librepods-ctl" AIRPODS_CTL_LOG="$tmp/ctl.log" \
  AIRPODS_NO_LIFECYCLE=1 QT_QPA_PLATFORM=offscreen timeout 90 \
  quickshell -p "$root/shell.qml" > "$tmp/log" 2>&1

grep -oE 'SMOKE (OK|FAIL|DONE).*' "$tmp/log"
if ! grep -q 'SMOKE DONE failures=0' "$tmp/log"; then
  grep -iE 'error|warn|unavailable|cannot|failed' "$tmp/log" | head -20
  exit 1
fi
for verb in noise:anc adaptive:65 ca:on onebud:on ear:both; do
  grep -qxF "$verb" "$tmp/ctl.log" || { echo "FAIL missing verb $verb"; exit 1; }
done
echo "OK (AirPods smoke tests)"
```

Create `quickshell/tests/smoke/airpods.qml` following `tests/smoke/vpn-views.qml`: a `ShellRoot` with `check()`, a `steps` array driven by a 1 s `Timer`, and `SMOKE DONE failures=N` + `Qt.quit()`. First steps:

```qml
check("service: fixture loaded", AirPodsService.daemonActive && AirPodsService.connected)
check("service: model", AirPodsService.modelName === "AirPods 5" && AirPodsService.modelNumber === "A3439")
check("service: battery", AirPodsService.leftPod.level === 93 && AirPodsService.rightPod.level === 97 && AirPodsService.caseBattery.level === 82)
check("service: in-ear/charging", AirPodsService.leftPod.inEar && AirPodsService.rightPod.charging)
check("service: modes", AirPodsService.availableModes().length === 4)
AirPodsService.setAdaptiveNoiseLevel(65)
AirPodsService.setConversationalAwareness(true)
AirPodsService.setOneBudANC(true)
AirPodsService.setEarDetectionBehavior(1)
```

Add a final step after the ctl queue drains. The stub fails the last ear verb, so no later success clears the error:

```qml
check("service: ctl failure surfaces", AirPodsService.lastError.indexOf("stub failure") !== -1)
```

Run:

```bash
bash quickshell/tests/smoke-airpods.sh
```

Expected: FAIL — `AirPodsService` is not defined.

- [ ] **Step 2: Implement `AirPodsService.qml` and register it**

Add to `services/qmldir`:

```qml
singleton AirPodsService 1.0 AirPodsService.qml
```

Implementation requirements:

- `statePath`: `Quickshell.env("AIRPODS_STATE")` or `(Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/librepods/status.json"`.
- `ctlPath`: `Quickshell.env("AIRPODS_CTL") || "librepods-ctl"`.
- `hasBattery`: for a headset, `headsetBattery.level !== -1`; otherwise any of `leftPod`, `rightPod` or `caseBattery` has a level other than `-1`.
- `FileView { path: statePath; watchChanges: true; printErrors: false; onFileChanged: reload(); onLoaded: applyLine(text()); onLoadFailed: stateGone() }`.
- `applyLine` uses `Parse.parseStatus`; sets `daemonActive = true` even when parsing fails; `daemonStarting = false`; clears `lifecycleError` on a successful parse; copies every field; calls `reconcile()`.
- `stateGone`: `daemonActive = false`, `daemonStarting = false`, `connected = false`, `lastError = ""`, `reconcile()`.
- Optimistic send with `_pendingField`/`_pendingValue`/`_queued`, a 4 s settle timer, and a single `Process` for `librepods-ctl`; a second verb replaces the queued one. On a non-zero exit or stderr, set `lastError` from `Parse.elideError`; otherwise `actionStatus` names the verb and clear `lastError`.
- `setNoiseMode` guards `availableModes().indexOf(mode) < 0`; `setAdaptiveNoiseLevel` clamps 0..100; `setEarDetectionBehavior` uses `Parse.earDetectionVerb`.
- Lifecycle: `wantDaemon = panelOpen || connected || BluetoothService.devices.some(d => d.connected && d.isAirPods)`. `reconcile()` returns when `AIRPODS_NO_LIFECYCLE=1`, when `daemonStarting`, or when `lifecycleBusy` (queue the action). `nextAction = Lifecycle.nextAction(wantDaemon, daemonActive)`; run `systemctl --user <action> librepods.service` in a single `Process`. `notePanelOpen` resets `startFailed`, sets `panelOpen = true`, calls `reconcile()` and `refresh()`; `notePanelClosed` sets `panelOpen = false` and calls `reconcile()`.
- On a start failure, set `lifecycleError` and `startFailed = true`; do not retry on the 5 s Bluetooth poll. The next `notePanelOpen` or a `wantDaemon` false→true transition clears it.
- A start arms an 8 s timer; if `status.json` still does not exist, set `daemonStarting = false` and `lifecycleError = "librepods did not start — journalctl --user -u librepods"`.
- `Connections { target: BluetoothService; function onDataUpdated() { root.reconcile() } }` and `Component.onCompleted: { reconcile(); refresh() }`.

- [ ] **Step 3: Run the smoke to verify it passes**

```bash
bash quickshell/tests/smoke-airpods.sh
```

Expected: `SMOKE DONE failures=0` and `OK (AirPods smoke tests)`.

- [ ] **Step 4: Commit**

```bash
git add quickshell/services/AirPodsService.qml quickshell/services/qmldir \
        quickshell/tests/smoke/airpods.qml quickshell/tests/smoke-airpods.sh
git commit -m "feat(quickshell): add AirPodsService with on-demand daemon"
```

---

## Task 6: AirPods launcher, view and icon

**Files:**
- Create: `quickshell/components/launchers/airpods/AirPodsView.qml`
- Create: `quickshell/components/launchers/AirPodsCenter.qml`
- Modify: `quickshell/theme/Icons.qml`
- Modify: `quickshell/tests/smoke/airpods.qml`

**Interfaces:**
- `AirPodsView`: `property var navItems`, `property int selIndex`, `property bool filterActive`, `property string filterText`, `function handleKey(e) -> bool`, `function updateModels()`, `function moveSel(delta)`, `function activate()`, `function adjustSel(delta)`, `function clearFilter()`, `signal closeRequested()`.
- `AirPodsCenter`: `WlrLayershell` with `property bool isOpen`, `function open()`, `function close()`, `function toggle()`, and `AirPodsView` as its content.
- `Icons.airpods` = `String.fromCodePoint(0xF184F)` (nf-md-earbuds, verified present in the installed JetBrainsMono Nerd Font 3.4.0).

- [ ] **Step 1: Add failing view checks to the smoke shell**

Add a step that creates `AirPodsView` (by path `components/launchers/airpods/AirPodsView.qml`, like the VPN smoke creates views) and checks:

```qml
check("view: loads", view !== null)
check("view: nav order", view.navItems.map(i => i.kind).join(",") === "mode,mode,mode,mode,adaptive,ca,onebud,ear,refresh")
check("view: mode labels", view.navItems.filter(i => i.kind === "mode").map(i => i.label).join(",") === "Off,Transparency,Adaptive,Noise Cancellation")
view.handleKey({ key: Qt.Key_J, text: "j", modifiers: 0, accepted: false })
check("view: j moves the cursor", view.selIndex === 1)
view.handleKey({ key: Qt.Key_N, text: "n", modifiers: 0, accepted: false })
view.handleKey({ key: Qt.Key_B, text: "b", modifiers: 0, accepted: false })
view.handleKey({ key: Qt.Key_E, text: "e", modifiers: 0, accepted: false })
view.handleKey({ key: Qt.Key_Slash, text: "/", modifiers: 0, accepted: false })
check("view: filter opens", view.filterActive)
let closed = false; view.closeRequested.connect(() => closed = true)
view.handleKey({ key: Qt.Key_Escape, text: "", modifiers: 0, accepted: false })
check("view: Esc clears the filter", !view.filterActive && !closed)
view.handleKey({ key: Qt.Key_Escape, text: "", modifiers: 0, accepted: false })
check("view: second Esc closes", closed)
```

Run `bash quickshell/tests/smoke-airpods.sh`: FAIL — view missing.

- [ ] **Step 2: Add the icon and implement the view/overlay**

`Icons.qml`:

```qml
// AirPods — nf-md-earbuds (U+F184F)
property string airpods: String.fromCodePoint(0xF184F)
```

`AirPodsView.qml` (in `components/launchers/airpods/`):

- Imports: `QtQuick`, `QtQuick.Controls`, `QtQuick.Layouts`, `../../theme`, `../../services`, `../../services/airPodsParse.js` as `Parse`.
- Card content: header `AIRPODS`, separator, device name + model; battery section; listening section; features section; footer hints.
- Battery rows: left, right, case (or headset), `Parse.levelText`, a slim meter filled by `Parse.levelFraction`, `Parse.podMeta`, `Parse.lidText`. Unknown case/lid renders `--` and no lid.
- Listening rows: `AirPodsService.availableModes()`; active row `Icons.check` at `Theme.success`; Adaptive level row only when `supportsAdaptive && noiseMode === NOISE_ADAPTIVE`.
- Feature rows: CA if supported, One-Bud if supported, Ear detection always when connected, Refresh.
- `navItems` order exactly as the smoke check; the filter hides settings rows whose label does not match, never the battery rows. `Connections` on `AirPodsService.noiseModeChanged` and the capability properties call `updateModels()`, so the Adaptive row appears/disappears when the mode changes.
- `handleKey`: `j/k`/arrows → `moveSel`; `Enter`/`Space` → `activate`; `h/l` → `adjustSel` (±5 adaptive); `o/t/a/n` → `setNoiseMode` if available; `c`/`b`/`e`/`r`; `/` → filter; `Esc` clears filter else emits `closeRequested`.
- Degraded states: daemon down + `lifecycleError` hint; `!connected`; unknown model (`Model not recognised` or `Model <number>`); schema too new; parse error; ctl error at `Theme.critical`.
- Use `Theme.*` and `Icons.*` only; no hard-coded hex/glyph.

`AirPodsCenter.qml`:

- `WlrLayershell` overlay like `AudioCenter.qml`: full-screen dim, 620 px card, `Theme.bgLauncher`, `Theme.roundingLauncher`, `Esc`/`Q` close, `Keys.onPressed` forwards to `view.handleKey(e)` and closes on `closeRequested`.
- Imports `"airpods"` and instantiates `AirPodsView` as the card content.
- `open()` sets `isOpen = true`, calls `AirPodsService.notePanelOpen()`, focuses the view; `close()` sets `isOpen = false`, calls `AirPodsService.notePanelClosed()`; `toggle()` chooses.
- `onIsOpenChanged` when opened: `AirPodsService.refresh()`.

- [ ] **Step 3: Run the smoke to verify it passes**

```bash
bash quickshell/tests/smoke-airpods.sh
```

Expected: `SMOKE DONE failures=0`, including the view checks and the ctl verbs.

- [ ] **Step 4: Commit**

```bash
git add quickshell/components/launchers/airpods/AirPodsView.qml \
        quickshell/components/launchers/AirPodsCenter.qml \
        quickshell/theme/Icons.qml quickshell/tests/smoke/airpods.qml
git commit -m "feat(quickshell): add the AirPods launcher"
```

---

## Task 7: Bar badge

**Files:**
- Create: `quickshell/components/bar/AirPodsIcon.qml`
- Modify: `quickshell/components/bar/Bar.qml`
- Modify: `quickshell/tests/smoke/airpods.qml`

**Interfaces:**
- `AirPodsIcon`: `visible` bound to `AirPodsService.hasBattery`; `readonly property int lowestLevel`; `readonly property string batteryText`; `signal clicked()`.
- Bar placement: after the Audio slot, before Wi-Fi.

- [ ] **Step 1: Add failing badge checks to the smoke shell**

Add a step that creates `AirPodsIcon` and checks:

```qml
check("badge: visible with battery", badge.visible)
check("badge: lowest level is the case", badge.lowestLevel === 82)
check("badge: text carries the percentage", badge.batteryText.indexOf("82%") !== -1)
```

Run `bash quickshell/tests/smoke-airpods.sh`: FAIL — badge missing.

- [ ] **Step 2: Implement `AirPodsIcon.qml` and insert it in `Bar.qml`**

Follow `BatteryIcon.qml`/the VPN chip: a `Rectangle` with `height: Theme.barIconSlot`, `Layout.preferredWidth: row.implicitWidth + 14`, hover background, a `RowLayout` with `Icons.airpods` and `batteryText`, and a `MouseArea` emitting `clicked()`.

- `lowestLevel` = the minimum of the available left/right/case/headset levels; `-1` when none.
- `batteryText` = `lowestLevel >= 0 ? lowestLevel + "%" : ""`.
- Color: `Theme.warning` at ≤20 %, `Theme.accent` if any component is charging, else `Theme.fg`.
- `BarToolTip` visible on hover: device/model, `L/R/C` levels, mode, CA/One-Bud/Ear. Keep it within 3 lines.
- Hide when `!AirPodsService.hasBattery`; no empty slot.
- In `Bar.qml`, insert after the Audio `Rectangle`/`AudioIcon` block:

```qml
AirPodsIcon {
    onClicked: root.launcherToggleRequested("airpods")
}
```

- [ ] **Step 3: Run the smoke to verify it passes**

```bash
bash quickshell/tests/smoke-airpods.sh
```

Expected: `SMOKE DONE failures=0`, including badge checks.

- [ ] **Step 4: Commit**

```bash
git add quickshell/components/bar/AirPodsIcon.qml quickshell/components/bar/Bar.qml quickshell/tests/smoke/airpods.qml
git commit -m "feat(quickshell): show AirPods battery in the bar"
```

---

## Task 8: Shell, Control Center and keybind wiring

**Files:**
- Modify: `quickshell/shell.qml`
- Modify: `quickshell/components/launchers/ControlCenter.qml`
- Modify: `hypr/hyprland.lua`

- [ ] **Step 1: Wire the launcher into `shell.qml`**

- Add `AirPodsCenter { id: airPodsCenter }` next to `AudioCenter`.
- Add `if (except !== "airpods") airPodsCenter.close()` to `closeAllExcept`.
- Add the `airpods` branch to `toggle`, `closeAll` and `close`: same toggle/open/close pattern as `audio`.

- [ ] **Step 2: Add the Control Center entry**

After the Audio entry:

```qml
{ label: "AirPods", key: "SUPER+ALT+A", icon: Icons.airpods, target: "airpods" },
```

- [ ] **Step 3: Add the Hyprland bind**

After the `SUPER+A` audio bind at line ~662:

```lua
hl.bind(mainMod .. " + ALT + A", hl.dsp.exec_cmd("quickshell ipc call launcher toggle airpods"))
```

- [ ] **Step 4: Verify the wiring**

```bash
grep -n "toggle airpods" hypr/hyprland.lua
grep -n "airpodsCenter" quickshell/shell.qml
grep -n "SUPER+ALT+A" quickshell/components/launchers/ControlCenter.qml
```

Expected: one hit per command.

- [ ] **Step 5: Commit**

```bash
git add quickshell/shell.qml quickshell/components/launchers/ControlCenter.qml hypr/hyprland.lua
git commit -m "feat(quickshell): wire AirPods into IPC and the keybind"
```

---

## Task 9: Normative specs and inventory

**Files:**
- Create: `quickshell/specs/launchers/AirPods-Center.md`
- Create: `quickshell/specs/bar/AirPods.md`
- Modify: `quickshell/specs/SPECS.md`
- Modify: `quickshell/AGENTS.md`

- [ ] **Step 1: Write the launcher spec**

`AirPods-Center.md` header:

```markdown
# AirPods-Center — Refined Spec

> Command: `SUPER+ALT+A` · File: `components/launchers/AirPodsCenter.qml` · View: `components/launchers/airpods/AirPodsView.qml` · Service: `AirPodsService.qml`
```

Sections: purpose; window (620 px, Audio Center pattern); battery; listening; features; shared behaviours (vim, hotkeys, `/`, `Esc`); service contract (`availableModes`, `setNoiseMode`, `setAdaptiveNoiseLevel`, `setConversationalAwareness`, `setOneBudANC`, `setEarDetectionBehavior`, `cycleNoiseMode`, `cycleEarDetection`, `refresh`, `notePanelOpen`, `notePanelClosed`); degraded states; acceptance checklist mirroring the design's §11 and the smoke checks.

- [ ] **Step 2: Write the bar spec**

`AirPods.md` header:

```markdown
# AirPods — Refined Spec

> Parent: Bar.md · Service: AirPodsService.qml · File: components/bar/AirPodsIcon.qml
```

Sections: position (after Audio, before Wi-Fi); geometry (bar slot height, width from content); states (daemon down, disconnected, battery, charging, ≤20 %, unknown case/lid); interaction (click opens the launcher, tooltip content); service contract (read-only `hasBattery`, `leftPod`, `rightPod`, `caseBattery`, `headsetBattery`, `noiseMode`, `conversationalAwareness`, `oneBudANC`, `earDetectionBehavior`); acceptance.

- [ ] **Step 3: Update `SPECS.md`**

- §2.2 dependencies: add `librepods` (the omarchy-pods daemon + `librepods-ctl`, `nixos/programs/librepods.nix`, `systemd.user.services.librepods`).
- §5.1 bar inventory: add `AirPods | Right | bar/AirPods.md | AirPodsService` and update the detailed order to `... Audio | AirPods | Wifi ...`.
- §5.2 launchers: add `AirPods-Center | SUPER+ALT+A | AirPods-Center.md`.
- §5/§6 build order/acceptance: add the AirPods Center, the daemon lifecycle and the live-device check.

- [ ] **Step 4: Update the `AGENTS.md` read-order table**

Add `bar/AirPods.md` to step 6 and `launchers/AirPods-Center.md` to step 10. Do not rewrite the historical "no spec work remains" note.

- [ ] **Step 5: Check the docs**

```bash
git diff --check
grep -n "AirPods" quickshell/specs/SPECS.md quickshell/AGENTS.md | head
```

Expected: no whitespace errors; the inventory and read order mention the new specs.

- [ ] **Step 6: Commit**

```bash
git add quickshell/specs/launchers/AirPods-Center.md quickshell/specs/bar/AirPods.md \
        quickshell/specs/SPECS.md quickshell/AGENTS.md
git commit -m "docs(quickshell): specify the AirPods Center and badge"
```

---

## Task 10: Full verification, live patched-daemon test, final commit

**Files:** none expected; fixes only if a gate fails.

- [ ] **Step 1: Run the unit and smoke gates**

```bash
bash quickshell/tests/run.sh
bash quickshell/tests/smoke-airpods.sh
bash tests/check-no-hardcoded-home.sh
```

Expected: all pass; `SMOKE DONE failures=0`.

- [ ] **Step 2: Check no hard-coded colours or glyphs**

```bash
grep -R "#[0-9a-fA-F]" --include="*.qml" quickshell/ | grep -v "theme/Theme.qml"
```

Expected: empty.

- [ ] **Step 3: Load the real shell**

```bash
timeout 15 quickshell -p ./quickshell/shell.qml
```

Expected: no QML errors; the new `AirPodsCenter` and badge load. If the live shell owns the IPC target, run the same command with `QT_QPA_PLATFORM=offscreen` against `tests/smoke/airpods.qml` instead and note it.

- [ ] **Step 4: Evaluate the NixOS configuration**

```bash
nix flake check ./nixos --no-write-lock-file
nix build --impure --no-link --print-out-paths --expr '
let pkgs = (builtins.getFlake "nixpkgs").legacyPackages.x86_64-linux;
in pkgs.callPackage ./nixos/programs/librepods.nix {}'
```

Expected: evaluation succeeds; the package builds.

- [ ] **Step 5: Dry-build the real machine (no switch)**

```bash
DOTFILES_MACHINE_DIR=/etc/nixos nixos-rebuild dry-build --flake ./nixos#default --impure
```

Expected: the unit and package evaluate; no switch. If `/etc/nixos` is unavailable in the environment, report that the dry-build was skipped.

- [ ] **Step 6: Live patched-daemon test**

Run the patched daemon with temporary state/config (never the real `~/.config/AirPodsTrayApp`), exactly as the pre-patch test:

```bash
out=$(nix build --impure --no-link --print-out-paths --expr '
let pkgs = (builtins.getFlake "nixpkgs").legacyPackages.x86_64-linux;
in pkgs.callPackage ./nixos/programs/librepods.nix {}')
base=/tmp/opencode/airpods-patched
rm -rf "$base"; mkdir -p "$base/state" "$base/config"
XDG_STATE_HOME="$base/state" XDG_CONFIG_HOME="$base/config" \
  QT_LOGGING_RULES=openpods.debug=false "$out/bin/librepods" --headless &
pid=$!
# poll $base/state/librepods/status.json until it exists
# run librepods-ctl noise:anc, noise:transparency, ca:on, ca:off,
#   onebud:on, onebud:off, ear:one, ear:both, ear:off, status
# capture the status lines, then kill -TERM $pid
```

Assertions:

- `model_name === "AirPods 5"`, `model_number` is `A3439` (the live device), `left/right` levels arrive.
- `supports_adaptive`, `supports_conversational_awareness`, `supports_one_bud_anc` are true after the patch.
- Every verb exits 0 and the status file changes accordingly.
- `journalctl --user -u librepods` has no errors if the service path was used.
- Measure RSS with `ps -o rss= -p $pid` while connected; note the value.
- Stop the daemon; delete `$base` (including the temporary pairing keys); confirm no real `~/.config/AirPodsTrayApp` or `~/.local/state/librepods` was created.
- Report the codec/profile change, if any.

- [ ] **Step 7: Commit fixes, or record the clean run**

If any gate required a fix:

```bash
git add -u
git commit -m "fix(quickshell): address AirPods verification findings"
```

If everything passed without changes, no commit is needed; report the gate outputs and the live-test findings.

---

## Self-Review Notes

- Spec coverage: §7 package/unit → Task 1; §9 parser → Task 2; §8 lifecycle → Tasks 3/5; §8.1 Bluetooth → Task 4; §10 service → Task 5; §11 UI/badge/wiring → Tasks 6–8; §12 patch → Task 1 + Task 10; §13/§14 constraints → Global Constraints; §15 verification → Task 10; §4 specs/inventory → Task 9.
- Type consistency: `leftPod`/`rightPod`/`caseBattery`/`headsetBattery`, `availableModes()`, `set*` and the parser constants are used with the same names in Tasks 2, 5, 6 and 7.
- Every Review Focus item has a task test or a live check; the remaining manual items are the degraded-state visuals in Task 10.
