# AGENTS — Quickshell Desktop Environment

> Entry point for any new `opencode` session opened at `quickshell/`.
> This file tells you **what to read, in what order, and what to do**.
> All component specs are **refined and normative** — do not reinterpret them.
> All the specs are in `./specs` directory

---

## 1. Goal (one line)

Build a minimal keyboard-driven Quickshell shell on Hyprland: top bar + 9 center launchers, dark/minimal (Waybar colours + Omarchy icons), no mouse required. See `SPECS.md:9`.

---

## 2. Read Order (normative)

Read top-to-bottom; do not skip `STYLE.md` — every component must use its tokens.

| Step | File | Why |
|------|------|-----|
| 1 | `SPECS.md` | Master spec: feasibility `SPECS.md:23`, deps `SPECS.md:53`, cost `SPECS.md:75`, architecture `SPECS.md:96`, inventory `SPECS.md:185`, build order `SPECS.md:234`, acceptance `SPECS.md:244` |
| 2 | `STYLE.md` | Single source of truth for colours/radii/spacing/typography/icons (`STYLE.md:12`, `STYLE.md:58`). No hard-coded hex/glyphs elsewhere. |
| 3 | `AGENTIC-SETUP.md` | Herdr orchestration: topology `AGENTIC-SETUP.md:8`, workstreams `AGENTIC-SETUP.md:28`, orchestrator/tester protocols, git policy `AGENTIC-SETUP.md:138`. Read only if you will spawn agents. |
| 4 | `bar/Bar.md` | Bar shell geometry + three-pill layout (`bar/Bar.md:12`). Read before any bar icon. |
| 5 | `bar/Date.md` + `bar/desktop-environnment/Bar-Desktop-Environment.md` + `Bar-App-Tray.md` | Center + left pill (clock `bar/Date.md:12`, workspaces `Bar-Desktop-Environment.md:12`, tray `Bar-App-Tray.md:8`). |
| 6 | `bar/Wifi.md`, `Bluetooth.md`, `Audio.md`, `KeyBoard.md` | Right-group icons + shared service contracts (`NetworkService`, `BluetoothService`, `Pipewire`, Hyprland IPC). |
| 7 | `bar/Bar-performance.md` | Collapsible perf drawer (`bar/Bar-performance.md:12`, polling paused when hidden). |
| 8 | `launchers/LauncherBase` (implicit via `SPECS.md:96` + each launcher §2) + `launchers/App-Launcher.md` | Shared launcher chrome + first launcher (backend `elephant`/`walker`/`DesktopEntries`). |
| 9 | `launchers/Network-Center.md`, `Bluetooth-Center.md` | Bar↔launcher state sync is critical here — read together. |
| 10 | `launchers/Audio-Center.md`, `Display-manager.md`, `Usb-Manager.md` | Audio graph + `hyprctl monitors -j` + udisks2 USB mount/storage listing. |
| 11 | `launchers/Notification-Center.md`, `Shutdown-Launcher.md`, `Key-Launcher.md` | System + meta. |
| 12 | `launchers/Control-Center.md` | Last — dispatches to all others (`Control-Center.md:12`). |

Each file header declares its parents (e.g. `bar/Wifi.md:3` → `Parent: Bar.md · Service: NetworkService.qml`).

---

## 3. What Is Already Done vs What You Must Do

| Done (this refinement) | You must do (build) |
|---|---|
| Every `*.md` under `bar/` and `launchers/` is refined with states, service contracts, interaction, acceptance | Implement `theme/Theme.qml`, `Icons.qml`, `services/*.qml`, `components/bar/*.qml`, `components/launchers/*.qml`, `shell.qml`/`Bar.qml` per `SPECS.md:96` file layout |
| `SPECS.md` feasibility/deps/cost/architecture | Declare new Nix deps in `nixos/programs/quickshell.nix` (`SPECS.md:53`) |
| `STYLE.md` tokens extracted from `waybar/{config.jsonc,style.css}` | Wire `hyprland.lua` `SUPER+<key>` → `quickshell ipc call launcher toggle <name>` (`SPECS.md:151`) |
| `AGENTIC-SETUP.md` Herdr workspace + tester checks | Run `quickshell -p` clean + idle RSS <200 MB (`SPECS.md:244`) |

No spec work remains — only implementation.

---

## 4. How to Build

### Single-agent (quick fix)

Follow `SPECS.md:234` build order: foundation (`theme/`+`services/`+`LauncherBase.qml`) → bar → launchers (app → network/bt → audio/display → notif/shutdown/keys → control) → `hyprland.lua`+`IpcHandler` → perf audit.

### Multi-agent (preferred for full build)

Use `AGENTIC-SETUP.md:58` waves (≤3 concurrent builders):

* **Wave 0:** `theme-services` + `launcher-base`
* **Wave 1:** `bar-shell`, `bar-icons`, `bar-perf`
* **Wave 2:** `launcher-app`, `launcher-net-bt`, `launcher-media`, `launcher-system`
* **Wave 3:** `launcher-control` then `hyprland.lua` wiring by orchestrator

Orchestrator dispatches, tester validates (`AGENTIC-SETUP.md:88` — `quickshell -p`, `Theme.*`/`Icons.*` grep, `services/` isolation, acceptance checklists), orchestrator commits (`AGENTIC-SETUP.md:138` Conventional Commits, one per passed workstream).

Herdr bootstrap: `AGENTIC-SETUP.md:104` preflight + workspace/tab/pane creation.

---

## 5. Rules

* Use `Theme.*` / `Icons.*` everywhere — `AGENTIC-SETUP.md:88` tester will fail on hard-coded `#hex` or glyphs.
* One `Process` per subsystem in `services/` — launchers never poll (`SPECS.md:88`).
* Bar icons are read-only over shared services; launchers mutate them (`SPECS.md:143`).
* All launchers: centered card 560–640 px, `rounding: 12`, `Esc` closes, vim `j/k` + `/` filter, `Enter` acts (`STYLE.md:58`).
* Every component must render a degraded state (see each spec §6).

---

## 6. Quick Start for a New Session

```bash
# 1. Read the plan
cat specs/SPECS.md | head -n 50
cat specs/AGENTS.md          # this file

# 2. (optional) spawn Herdr team
# see AGENTIC-SETUP.md:104

# 3. Implement one workstream, then
quickshell -p                # must be clean
grep -R "#[0-9a-fA-F]" --include="*.qml" quickshell/ | grep -v "theme/Theme.qml"  # must be empty
```

---

## 7. Useful References

* `waybar/{config.jsonc,style.css}` — legacy behaviour/colours (`SPECS.md:256`)
* `hypr/hyprland.lua:38` — current autostart/binds
* `nixos/programs/quickshell.nix` / `herdr.nix` — Nix wiring
* `hacking/omarchy/` — modular config precedent
