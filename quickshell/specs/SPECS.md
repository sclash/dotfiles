# Quickshell Desktop Environment — Refined Master Spec

> Status: **refined** — every component spec under `./bar` and `./launchers` is
> normative. Build agents must satisfy the refined specs exactly.
> Hyprland + Quickshell. Waybar is the legacy reference; Omarchy is the styling reference.

---

## 1. Goal

Build a **minimal, keyboard-driven** desktop shell in **Quickshell (QML)**
running on **Hyprland / Wayland**. No mouse required for any primary action.
The shell replaces Waybar and provides:

* A top bar (`Bar`) with left / center / right groups.
* Center-screen launchers toggled via `SUPER+<key>`, closed with `Esc`, navigable with vim motions.
* Consistent dark/minimal styling (Waybar colours + Omarchy iconography).

We are **not building generic DE scaffolding** — only the shell surface described below.

---

## 2. Feasibility Assessment

### 2.1 Is it doable with Quickshell on Hyprland?

**Yes — fully feasible.** Quickshell is designed for this exact use case.

| Requirement | Quickshell capability | Notes |
|---|---|---|
| Top bar per-screen (`PanelWindow`) | `Quickshell.PanelWindow` + `Quickshell.screens` | `Bar.qml:6-25` already prototypes this |
| Hyprland workspaces / active window | `Quickshell.Hyprland` singleton | `Hyprland.workspaces`, `Hyprland.focusedWorkspace`, `Hyprland.clients` |
| System tray (Flameshot, etc.) | `Quickshell.Services.SystemTray` | Works on Wayland via `StatusNotifierItem` |
| Audio (PipeWire/WirePlumber) | `Quickshell.Services.Pipewire` | Native nodes/links model, no CLI polling needed |
| Network state / Wi-Fi | **No native service** | Use `Process { command: ["nmcli",...] }` or DBus via `Quickshell.DBus` |
| Bluetooth | **No native service** | Use `bluetoothctl` / `bluetoothd` DBus (`org.bluez`) |
| Keyboard layout | Hyprland IPC `hyprctl devices -j` + `switchxkblayout` | Already prototyped in `waybar/config.jsonc:37-43` |
| CPU / RAM / Disk / Temp | `/proc` + `sysfs` via `Process` or `FileView` polling | Standard pattern in Quickshell examples |
| Date / time | `Process { command: ["date"] }` + `Timer` | `Bar.qml:27-50` already does this; refine to `Qt.formatDateTime` |
| Launchers (center overlay) | `PanelWindow { anchors.centerIn }` or `PopupWindow` + Hyprland `layerrule` | Standard Quickshell launcher pattern |
| Notifications | `Quickshell.Services.Notifications` | Replaces `swaync` daemon |
| Battery | `Quickshell.Services.UPower` | Optional — present in Waybar config but not required for this spec |
| Keybinding dispatch | Hyprland `bind = SUPER, <key>, exec, quickshell ipc call ...` | Quickshell `IpcHandler` |
| App launcher backend | `elephant` / `walker` already in autostart (`hyprland.lua:38`) | Reuse verbatim; QML just renders results |
| Multi-monitor | `Variants { model: Quickshell.screens }` | Each screen gets its own `PanelWindow` |

**Risks / mitigations:**

* **NetworkManager & BlueZ have no first-class Quickshell service** → wrap `nmcli`/`bluetoothctl`/DBus and debounce polling (see §4). Tested pattern; not a blocker.
* **Hyprland IPC socket availability at shell startup** → guard with retry timer (2s) if `Hyprland` singleton reports disconnected.
* **Wayland layer-shell exclusivity** → bar uses `exclusionMode: ExclusionMode.Auto`; launchers use `ExclusionMode.Ignore` + `focusable: true`.

### 2.2 External dependencies

All dependencies must be declared in `nixos/programs/quickshell.nix` or `configuration.nix`.

| Package | Purpose | Required? | Nix attr |
|---|---|---|---|
| `quickshell` (unstable) | Shell runtime | **yes** | `pkgs-unstable.quickshell` — already enabled |
| `hyprland` | Compositor IPC | **yes** | already present |
| `networkmanager` + `nmcli` | Wi-Fi / VPN / ethernet | **yes** | `pkgs.networkmanager` |
| `wireplumber` + `pipewire` + `wpctl` | Audio graph | **yes** | `pkgs.wireplumber` |
| `bluez` + `bluez-tools` | Bluetooth | **yes** | `pkgs.bluez` |
| `elephant` (or `walker`) | App index for App-Launcher | **yes** | already in autostart (`hyprland.lua:38`) — ensure packaged |
| `upower` | Battery (if kept) | optional | `pkgs.upower` |
| `lm_sensors` / `sysstat` | Temperature / CPU | **yes** for perf widgets | `pkgs.lm_sensors` |
| `udisks2` | USB storage mount/unmount via `udisksctl` | **yes** for USB-Manager | `pkgs.udisks2` + `services.udisks2.enable` |
| `usbutils` | USB device listing (`lsusb`) | **yes** for USB-Manager | `pkgs.usbutils` |
| `noto-fonts` + `nerd-fonts.jetbrains-mono` | Icons / typography | **yes** | ensure in `fonts.packages` |
| `quickshell` needs `qt6.qtdeclarative` | Already in `home.packages` | **yes** | present |
| `herdr` | Agentic orchestration | **yes** for build phase | `pkgs-unstable.herdr` — already enabled |

> No new system service is required. The shell is a single user process
> started via `programs.quickshell.systemd.enable = true` (already set) or
> `exec-once = quickshell` in Hyprland.

### 2.3 Cost (CPU / memory)

Measured reference: Quickshell + typical bar on Hyprland (from upstream benchmarks and local `waybar` baseline).

| Resource | Waybar baseline | Quickshell target | Budget |
|---|---|---|---|
| Resident memory (bar only) | ~35 MB | **80–150 MB** (QML engine + Qt) | < 200 MB |
| Resident memory (all launchers idle) | — | +10–20 MB (lazy-loaded) | launchers must be `Loader { active: false }` until toggled |
| CPU idle (no polling) | <0.2% | **<0.5%** | timers at 1s (clock), 2s (perf), event-driven otherwise |
| CPU under load (perf drawer open) | ~0.5% | **<1.0%** | |
| GPU | negligible | negligible | QML is GPU-accelerated; no software rendering |

**Rules to stay within budget:**

1. **No tight polling loops.** Network/Bluetooth/DBus are event-driven (DBus signals, `nmcli monitor`, `bluetoothctl` watch). Perf widgets poll at **2s** when visible, **paused** when drawer closed.
2. **Lazy-load launchers.** Each launcher is a `Loader` / `LazyLoader`; only the bar is always resident.
3. **One `Process` per subsystem**, not per widget. Share a singleton service (e.g., `NetworkService.qml`, `BluetoothService.qml`).
4. **Icons are font glyphs**, not images — no texture cost.

---

## 3. Architecture

### 3.1 File layout (target)

```
quickshell/
├── shell.qml                 # Root Scope — registers bar + launchers, IpcHandler
├── Bar.qml                   # PanelWindow per screen, 3 groups
├── services/
│   ├── NetworkService.qml    # Singleton — nmcli / DBus wrapper
│   ├── BluetoothService.qml  # Singleton — BlueZ DBus wrapper
│   ├── AudioService.qml      # Thin wrapper over Quickshell.Services.Pipewire
│   ├── PerfService.qml       # CPU/RAM/Disk/Temp polling (pause when hidden)
│   ├── NotifService.qml      # Wrapper over Quickshell.Services.Notifications
│   ├── HyprService.qml       # Optional — Hyprland helpers beyond Quickshell.Hyprland
│   └── UsbService.qml        # Singleton — udisks2 / lsusb / udev monitor wrapper
├── components/
│   ├── bar/
│   │   ├── Workspaces.qml
│   │   ├── AppTray.qml
│   │   ├── DateBlock.qml
│   │   ├── WifiIcon.qml
│   │   ├── AudioIcon.qml
│   │   ├── BluetoothIcon.qml
│   │   ├── KeyboardIcon.qml
│   │   └── PerfDrawer.qml
│   └── launchers/
│       ├── LauncherBase.qml  # Shared: centered PopupWindow, Esc, vim nav, focus
│       ├── AppLauncher.qml
│       ├── NetworkCenter.qml
│       ├── BluetoothCenter.qml
│       ├── AudioCenter.qml
│       ├── ControlCenter.qml
│       ├── NotificationCenter.qml
│       ├── ShutdownLauncher.qml
│       ├── KeyLauncher.qml
│       ├── DisplayManager.qml
│       └── UsbManager.qml
├── theme/
│   ├── Theme.qml             # Singleton — colours, radii, spacing, fonts
│   └── Icons.qml             # Singleton — nerd-font glyph map
└── specs/                    # This directory — normative
```

### 3.2 Modularity

* **Yes — keep config modular** (Omarchy precedent). Each widget/launcher is its own file. `shell.qml` only composes.
* No shell scripts to *spawn* processes except via `Process` / `IpcHandler`. Legacy `waybar/scripts/*` are retired; logic lives in QML services.

### 3.3 State sharing: bar ↔ launchers

Bar icons are **read-only reflections** of the same singleton services that launchers mutate.

* `WifiIcon` reads `NetworkService.status`; `NetworkCenter` writes via `NetworkService.connect(ssid)`. No duplicate polling.
* Same for `BluetoothService`, `AudioService`, `NotifService`.
* Services expose `QtObject` properties + signals; QML bindings propagate automatically.

### 3.4 IPC / keybindings

Hyprland config (`hyprland.lua`) binds `SUPER+<key>` to `quickshell ipc call <handler> toggle <launcher>`:

```
bind = SUPER, SPACE, exec, quickshell ipc call launcher toggle control
bind = SUPER, r, exec, quickshell ipc call launcher toggle app
...
```

`shell.qml` registers:

```qml
IpcHandler {
  target: "launcher"
  function toggle(name: string): void { /* activate Loader */ }
  function closeAll(): void { ... }
}
```

Inside Quickshell, launchers also close on `Esc` (handled in `LauncherBase`).

---

## 4. Implementation Notes Common to All Components

* **Styling:** see [`STYLE.md`](./STYLE.md) — single source of truth for colours, spacing, radii, typography, elevation.
* **Icons:** Nerd Font glyphs via `Icons.qml`; no image assets.
* **Error states:** every icon/launcher must render a degraded state (e.g., `nmcli` missing → `` + tooltip "NetworkManager unavailable").
* **Polling:** perf drawer paused when hidden; network/bt via DBus signals; audio via PipeWire signals; clock via 1s `Timer`.
* **Accessibility:** all launchers keyboard-only; `j/k` or `Up/Down`, `Enter` to act, `Esc` to close, `/` to filter where applicable.

---

## 5. Components Inventory

### 5.1 Bar (`./bar`)

| Component | Position | Spec | Host service |
|---|---|---|---|
| Workspaces + App-Tray | Left | `bar/desktop-environnment/Bar-Desktop-Environment.md`, `Bar-App-Tray.md` | `Quickshell.Hyprland`, `SystemTray` |
| Date | Center | `bar/Date.md` | local `Timer` |
| Keyboard | Right | `bar/KeyBoard.md` | Hyprland IPC |
| Bluetooth | Right | `bar/Bluetooth.md` | `BluetoothService` |
| Wifi | Right | `bar/Wifi.md` | `NetworkService` |
| Audio | Right | `bar/Audio.md` | `AudioService` (PipeWire) |
| Perf drawer (CPU/RAM/Disk/Temp) | Right (collapsible) | `bar/Bar-performance.md` | `PerfService` |
| Notification bell (next to Date) | Center | `bar/Date.md` | `NotifService` |

Detailed order in bar (left → right): `Workspaces | AppTray | —spacer— | Date(+bell) | —spacer— | PerfDrawer(◀) | Audio | Bluetooth | Wifi | Keyboard | Tray`.

### 5.2 Launchers (`./launchers`)

| Launcher | Key | Spec |
|---|---|---|
| Control-Center | `SUPER+SPACE` | `Control-Center.md` |
| App-Launcher | `SUPER+r` | `App-Launcher.md` |
| Network-Center | `SUPER+w` | `Network-Center.md` |
| Bluetooth-Center | `SUPER+b` | `Bluetooth-Center.md` |
| Audio-Center | `SUPER+a` | `Audio-Center.md` |
| Display-Manager | `SUPER+d` | `Display-manager.md` |
| USB-Manager | `SUPER+u` | `Usb-Manager.md` |
| Notification-Center | `SUPER+SHIFT+a` | `Notification-Center.md` |
| Shutdown-Launcher | `SUPER+q` | `Shutdown-Launcher.md` |
| Key-Launcher | `SUPER+k` | `Key-Launcher.md` |

All launchers share `LauncherBase.qml` (centered card, 560–640 px wide, `rounding: 12`, `focusable: true`, Esc/vim nav).

---

## 6. Agentic Setup

> Full orchestration contract: [`AGENTIC-SETUP.md`](./AGENTIC-SETUP.md)

Summary:

* **Orchestrator** — one agent, owns the Herdr workspace, dispatches builders, triggers tester, merges/ commits.
* **Builders** — one per workstream (Bar + each launcher family). Each builder is an isolated Herdr pane/agent that implements exactly one refined spec and reports to the orchestrator.
* **Tester** — one agent, runs deterministic checks (QML parse, `quickshell` smoke, spec-conformance checklist) on demand from the orchestrator.
* **Communication** — Herdr agents (`/herdr` skill); no ad-hoc shell messaging.
* **Git** — orchestrator commits with a meaningful message after each builder's work is approved by tester.

---

## 7. Build Order (recommended for orchestrator)

1. `theme/Theme.qml` + `Icons.qml` + `services/*` skeletons (shared foundation).
2. `Bar.qml` shell + `LauncherBase.qml` (so builders have the canvas).
3. Bar workstreams: `Date` → `Workspaces/AppTray` → `Keyboard` → `Wifi`/`Bluetooth`/`Audio` → `PerfDrawer`.
4. Launchers: `App-Launcher` → `Network-Center` → `Bluetooth-Center` → `Audio-Center` → `Display-Manager` → `USB-Manager` → `Notification-Center` → `Control-Center` → `Shutdown-Launcher` → `Key-Launcher`.
5. Wire `hyprland.lua` keybindings + `quickshell ipc` handlers end-to-end.
6. Final pass: perf/idle measurement, memory audit, Herdr demo.

---

## 8. Acceptance Criteria (global)

* `quickshell` starts with no QML errors (`quickshell -p` clean).
* Bar renders on every `Quickshell.screens` output; workspaces track Hyprland correctly.
* Each bar icon click (or key) opens its corresponding launcher; launcher actions mutate icon state.
* All launchers toggle via `SUPER+<key>`, close on `Esc`, filter/navigate with vim keys.
* No polling when perf drawer is hidden; memory < 200 MB idle (measured via `systemd-cgtop` or `ps`).
* `nix flake check` (if present) and `home-manager switch` succeed after dep additions.

---

## 9. Useful References

* `/home/asergi/hacking/omarchy/` — modular config precedent; Hyprland helpers in `config/hypr/`.
* `/home/asergi/dotfiles/hypr/hyprland.lua` — current bindings + autostart (`Bar.qml:…` parity).
* `/home/asergi/dotfiles/waybar/{config.jsonc,style.css}` — legacy bar behaviour + colours.
* `/home/asergi/dotfiles/nixos/programs/{quickshell.nix,herdr.nix}` — Nix wiring for the shell.
* [`STYLE.md`](./STYLE.md) — colour/spacing/typography tokens.
* [`AGENTIC-SETUP.md`](./AGENTIC-SETUP.md) — Herdr orchestration contract.
