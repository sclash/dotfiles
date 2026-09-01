# Agentic Setup — Quickshell Desktop Environment

> How to build the shell with a **Herdr-orchestrated multi-agent team**.
> Tool: [`/herdr` skill](https://opencode.ai/docs) · Runtime: `herdr` (already enabled via `nixos/programs/herdr.nix`)

---

## 1. Topology

Single **Herdr workspace**: `quickshell-build`.

```
workspace: quickshell-build  (w1)
├── tab: orchestrator  (w1:t1)  — 1 pane: orchestrator agent
├── tab: services      (w1:t2)  — 2 panes: theme/services builder, launcher-base builder
├── tab: bar           (w1:t3)  — 3 panes: bar-shell, perf/date, icons (audio/bt/wifi/kb)
├── tab: launchers-a   (w1:t4)  — 3 panes: app, network, bluetooth
├── tab: launchers-b   (w1:t5)  — 3 panes: audio, display, notifications
├── tab: launchers-c   (w1:t6)  — 2 panes: control, shutdown+keys (lightest)
└── tab: tester        (w1:t7)  — 1 pane: tester agent
```

* Tabs keep the Herdr UI navigable; panes keep agents isolated.
* Builders communicate **only** via the orchestrator — no builder-to-builder direct messaging. This enforces single-threaded integration.

### Roles

| Role | Cardinality | Responsibility |
|---|---|---|
| **Orchestrator** | 1 | Owns the workspace, dispatches builders, triggers tester, merges & commits, arbitrates bar↔launcher shared-service contracts. |
| **Builders** | 8–10 | Each owns one workstream/spec. Implements QML, wires to services, ensures `Theme.*` usage. Reports to orchestrator. |
| **Tester** | 1 | On demand from orchestrator: QML parse, `quickshell` smoke, spec-conformance checklist, CPU/mem idle measurement. |

---

## 2. Workstreams (Builders)

Each builder is a Herdr agent in its own pane, prompted with the refined spec path(s).

| # | Builder name | Spec(s) | Deliverables |
|---|---|---|---|
| B1 | `theme-services` | `STYLE.md`, `SPECS.md:3` | `theme/Theme.qml`, `theme/Icons.qml`, `services/NetworkService.qml`, `BluetoothService.qml`, `AudioService.qml`, `PerfService.qml`, `NotifService.qml` |
| B2 | `launcher-base` | `SPECS.md:3.4`, `STYLE.md:5` | `components/launchers/LauncherBase.qml` (shared card, Esc, vim nav, focus, Hypr ipc) |
| B3 | `bar-shell` | `bar/Bar.md`, `desktop-environnment/*`, `Date.md` | `Bar.qml`, `components/bar/Workspaces.qml`, `AppTray.qml`, `DateBlock.qml` |
| B4 | `bar-icons` | `bar/Wifi.md`, `Bluetooth.md`, `Audio.md`, `KeyBoard.md` | `components/bar/WifiIcon.qml`, `BluetoothIcon.qml`, `AudioIcon.qml`, `KeyboardIcon.qml` |
| B5 | `bar-perf` | `bar/Bar-performance.md` | `components/bar/PerfDrawer.qml` + perf polling wiring |
| B6 | `launcher-app` | `launchers/App-Launcher.md` | `components/launchers/AppLauncher.qml` |
| B7 | `launcher-net-bt` | `Network-Center.md`, `Bluetooth-Center.md` | `NetworkCenter.qml`, `BluetoothCenter.qml` (both share their services with the bar icons — must satisfy the sync contract) |
| B8 | `launcher-media` | `Audio-Center.md`, `Display-manager.md` | `AudioCenter.qml`, `DisplayManager.qml` |
| B9 | `launcher-system` | `Notification-Center.md`, `Shutdown-Launcher.md`, `Key-Launcher.md` | `NotificationCenter.qml`, `ShutdownLauncher.qml`, `KeyLauncher.qml` |
| B10 | `launcher-control` | `Control-Center.md` | `ControlCenter.qml` (depends on all other launchers being dispatchable) |

> **B7 coalesces Network + Bluetooth** because both involve `nmcli`/`bluetoothctl` DBus and the bar-icon state sync is the critical integration test. If bandwidth allows, split B7 into two panes.

### Build Order (orchestrator dispatches in waves)

1. **Wave 0 — foundation:** B1 (theme/services) + B2 (launcher base). Blocks all others.
2. **Wave 1 — bar:** B3, B4, B5 (can run in parallel once B1 is green).
3. **Wave 2 — launchers:** B6, B7, B8, B9 (parallel; B7 may start after B4 has stubbed the shared services).
4. **Wave 3 — meta:** B10 (Control Center) after Wave 2 completes — needs all launcher targets to exist.
5. **Wave 4 — integration:** Hyprland `hyprland.lua` keybindings + `IpcHandler` (`shell.qml`) wired end-to-end by the orchestrator.

---

## 3. Orchestrator Protocol

### 3.1 Lifecycle per builder

```
Builder ──► "ready for review: <workstream>" ──► Orchestrator
Orchestrator ──► "test <workstream>" ──► Tester
Tester ──► PASS → Orchestrator commits → Builder done
        └─► FAIL (with checklist) → Orchestrator ─► "fix: <items>" → Builder
                                    ↑ loop until PASS or escalate
```

* Builder **must not** self-merge or commit. Only the orchestrator commits.
* Builder reports completion in-pane via `herdr agent prompt <builder> "done"` or by writing a sentinel file that the orchestrator polls — either is fine, but **one** convention must be chosen at workspace creation.

### 3.2 Orchestrator duties

* Create the workspace/tabs/panes (see §5.2 bootstrap).
* Prompt each builder with: spec paths, Theme/Icons tokens to use, shared-service contract, and the bar↔launcher sync requirement where relevant.
* Trigger the tester after each builder reports done.
* On **PASS**: `git add <workstream files> && git commit -m "<type>: <meaningful message>"` — see §6.
* On **FAIL**: relay the tester's checklist to the builder (verbatim, no paraphrase) and re-trigger tester after the fix.
* Own `hyprland.lua` keybinding + `shell.qml` `IpcHandler` integration.
* Final validation (§4).

### 3.3 Shared-service arbitration

When a bar icon and a launcher share a service (Wifi↔Network-Center, Bluetooth↔Bluetooth-Center, Audio↔Audio-Center, Date bell↔Notification-Center):

* The **service** is owned by the bar-icon builder (B4/B3) — launcher builders **import** it, never duplicate it.
* Any service API extension needed by a launcher must be requested via the orchestrator → bar-icon builder.

---

## 4. Tester Protocol

Triggered only by the orchestrator (`herdr agent prompt tester "test <workstream>" --wait`).

### 4.1 Checks (deterministic, scripted)

| Check | Command / method | Pass criterion |
|---|---|---|
| **QML parse** | `quickshell -p` or `qmllint` on changed files | exit 0, no `file:line` errors |
| **Quickshell smoke** | `timeout 5 quickshell --no-reload` | no QML runtime errors in stderr |
| **Theme token compliance** | `grep -R "#[0-9a-fA-F]\\{3,8\\}" --include="*.qml" quickshell/ \| grep -v "theme/Theme.qml"` | no matches (all colours via `Theme.*`) |
| **Hard-coded glyphs** | `grep -R "\|󰂯\|" --include="*.qml" quickshell/components \| grep -v "Icons\."` | no matches (all glyphs via `Icons.*`) |
| **Spec conformance** | checklist from the relevant refined `*.md` `## Acceptance` | every box ticked (manual attest) |
| **Service sharing** | `grep -R "Process.*nmcli\|Process.*bluetoothctl\|Process.*wpctl" --include="*.qml"` outside `services/` | no matches (launchers don't spawn their own services) |
| **Idle cost** | `systemd-cgtop` / `ps -o rss,pcpu -p $(pgrep quickshell)` after 30s idle, perf drawer closed | RSS < 200 MB, CPU < 0.5% |

### 4.2 Response format

```
PASS <workstream>
```

or

```
FAIL <workstream>
- <check>: <detail>
- <check>: <detail>
```

The orchestrator relays `FAIL` verbatim to the builder.

### 4.3 Independence

* Tester **never** edits code.
* Tester may read specs and `waybar/*` references to validate parity, but does not implement.

---

## 5. Herdr Bootstrap

### 5.1 Preflight

```bash
test "${HERDR_ENV:-}" = 1 || { echo "Not inside Herdr"; exit 1; }
herdr --help
herdr workspace list
herdr agent list
```

If outside Herdr, launch Herdr TUI (`herdr`) first, then bootstrap inside it.

### 5.2 Create workspace + tabs + panes

```bash
# Workspace — orchestrator tab is created implicitly
herdr workspace create --name quickshell-build

# Discover returned workspace/tab/pane IDs from JSON — use .result.workspace etc.
# Subsequent creates must target the same workspace id ($WID).
WID=$(herdr workspace list | jq -r '.[] | select(.name=="quickshell-build") | .workspace_id')

# Tabs
herdr tab create --workspace "$WID" --name services
herdr tab create --workspace "$WID" --name bar
herdr tab create --workspace "$WID" --name launchers-a
herdr tab create --workspace "$WID" --name launchers-b
herdr tab create --workspace "$WID" --name launchers-c
herdr tab create --workspace "$WID" --name tester

# Pane splits — example for tab w1:t2 (services)
# Use pane split --direction right/down with --cwd "$PWD" --no-focus
# Keep at most 3 panes per tab to avoid narrow columns.
herdr pane split --current --direction right --cwd "$PWD" --no-focus
# Read .result.pane.pane_id after each split.

# Start agents — one per pane
herdr agent start orchestrator --kind opencode --pane <pane-id>
herdr agent start theme-services --kind opencode --pane <pane-id>
herdr agent start launcher-base  --kind opencode --pane <pane-id>
# ... repeat for each builder
herdr agent start tester --kind opencode --pane <pane-id>
```

### 5.3 Prompting pattern

```bash
herdr agent prompt theme-services "
You are builder B1 (theme-services).
Implement: theme/Theme.qml, theme/Icons.qml, services/* per:
  - specs/STYLE.md
  - specs/SPECS.md:2.2,3.1
When done, message the orchestrator.
" --wait --timeout 300000
```

The orchestrator prompt should always include **exact spec file paths** so the builder has no ambiguity.

---

## 6. Git Commits

* **Only the orchestrator** commits, and only after tester **PASS**.
* **Frequency:** one commit per builder workstream that passed (i.e., up to 10 commits).
* **Format:** Conventional Commits — `<type>: <description>` where `type` in `feat, fix, refactor, docs, chore`.

  Examples:

  ```
  feat: add theme tokens and shared services (Theme, Icons, NetworkService, BluetoothService)
  feat: add bar shell with workspaces, app-tray, and date block
  feat: add wifi/bluetooth/audio/keyboard bar icons over shared services
  feat: add perf drawer with paused polling when collapsed
  feat: add app launcher over elephant/walker/DesktopEntries fallback
  feat: add network and bluetooth centers with bar state sync
  feat: add audio center and display manager
  feat: add notification, shutdown, and key launchers
  feat: add control center dispatching all launchers
  chore: wire hyprland keybindings and quickshell ipc handlers
  ```
* **Content:** commit only the workstream's files + any service API extensions it required (no unrelated changes).
* **Push:** not automatic; orchestrator pushes with `-u` after final integration or on demand.

---

## 7. Cost of the Agentic Setup Itself

| Resource | Cost | Notes |
|---|---|---|
| Orchestrator agent | ~1 LLM context | coordinator, not a heavy coder |
| Each builder agent | ~1 LLM context | prompts are spec-precise; no broad exploration needed |
| Tester agent | ~1 LLM context | mostly script runners + checklist |
| Herdr panes (terminals) | ~5 MB RAM each | 15 panes ≈ 75 MB |
| LLM CPU/memory | model-dependent | running 3–4 builders in parallel is the sweet spot; 8 concurrent builders will saturate the host — stagger waves |
| Wall-clock | ~2–4 h end-to-end | wave-sequenced; each builder's work is ~15–30 min with tests |

**Recommendation:** run waves sequentially (Wave 0 → 1 → 2 → 3) with at most **3 concurrent builders** per wave to bound LLM cost and avoid service-contract races.

---

## 8. Verification of the Setup

* `herdr workspace list` shows `quickshell-build` with 7 tabs.
* `herdr agent list` shows orchestrator + builders + tester.
* `herdr pane list --workspace "$WID"` shows 15+ panes.
* `git log --oneline -10` shows one commit per passed workstream with the format above.
* Final `quickshell -p` clean + `ps` memory < 200 MB idle.
