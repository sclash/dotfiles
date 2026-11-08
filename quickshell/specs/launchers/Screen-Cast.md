# Screen-Cast — Refined Spec

> Command: `SUPER+K` · File: `components/launchers/ScreenCastLauncher.qml` · Service: `ScreenCastService.qml` · Backend: `org.gnome.NetworkDisplays.Manager` (session bus) + `hyprctl`

---

## 1. Purpose

Center-screen window to project this desktop onto a wireless display (Miracast / Wi-Fi Display, and Chromecast where the sink speaks it), equivalent to Windows `Win+K`. It discovers sinks automatically through the GNOME Network Displays daemon, connects on `Enter`, and then exposes the cast session: mode, the cast output's resolution and scale, and a local-panel toggle.

The launcher is a **view over `ScreenCastService`**. All Processes, timers and D-Bus/systemd calls live in the service; the QML file never spawns its own.

## 2. Window

* Centered card `width: 640`, `radius: Theme.roundingLauncher`, max height `660`, inside a `Flickable` (same scrollbar treatment as Network Center).
* `WlrLayershell` overlay (`ExclusionMode.Ignore`, `WlrKeyboardFocus.Exclusive`), dim `Theme.overlay`, click outside closes.
* Vim `j/k`, `Enter` acts, `Esc` closes one level at a time, `/` filters the display list.

## 3. Sections

### 3.1 Mode (top)

Three mutually exclusive chips, always visible:

| Chip | Value | Runtime behaviour |
|---|---|---|
| **Duplicate** (default) | `duplicate` | No pre-action. The share dialog is used to pick the built-in panel; the desktop is cloned. |
| **Extend** | `extend` | `hyprctl output create headless SCREENCAST` runs before `StartStream`; the share dialog offers `SCREENCAST` as an extra monitor. |
| **Only remote** | `only-remote` | Same as Duplicate; after streaming starts, session settings exposes a **Local panel** toggle. The panel is never turned off automatically — the share picker is displayed on that panel. |

The selected mode is stored in `ScreenCastService.mode`. The hint line under the chips states, in plain language, which source to pick in the share dialog.

### 3.2 Displays (scan)

* Section label `Displays`, `Scan` button (`ScreenCastService.rescan()`), and an inline filter field when `/` is pressed.
* Rows come from `ScreenCastService.sinks` (`uuid`, `name`, `protocol`, `state`). Each row shows the sink name, `protocolLabel(protocol) · stateLabel(state)`, and `Icons.monitor`.
* `Enter` (or click) calls `ScreenCastService.connectSink(sink)`. Connections are refused while a session is active or a Process is busy.
* Sorted as returned by the daemon (priority de-duplication is the daemon's job).

### 3.3 Session card (visible when a session exists)

* Name, protocol, and mode; subline is mode-aware:
  * `connecting` → `"<Mode> · waiting for the share dialog…"`
  * `streaming` → `"<Mode> · streaming"`
  * `error` → `"<Mode> · error"`
* Buttons: `Settings` (opens §3.4) and `Disconnect` (`ScreenCastService.disconnect()`).

### 3.4 Session settings (`s`, or Settings button)

Rows, filtered by the active mode:

| Row | Visible when | Control |
|---|---|---|
| Output summary | always | read-only `name · WxH @ Hz · scale` from `ScreenCastService.castOutput` |
| Resolution | mode `extend` | picker over `castOutput.availableModes`; writes `applyOutput("mode", value)` |
| Scale | mode `extend` | picker `0.5…3`; writes `applyOutput("scale", value)` |
| Local panel | mode `only-remote` | `On`/`Off`; writes `setLocalPanel(!localPanelOff)` |
| Back | always | returns to main |

A muted line under the rows reads `Resolution and scale follow the built-in panel in this mode.` when the mode is not `extend` — because in duplicate/only-remote the cast source *is* the built-in panel, so resizing it would resize the laptop screen too.

The picker opens in place (list replaces the row navigation): `j/k` moves, `Enter`/`l` applies, `Esc`/`h` cancels.

### 3.5 Error line

`ScreenCastService.lastError` renders at `Theme.critical` with `Icons.warning`, wrapped, below the sections.

## 4. Interaction

* `j/k` moves across mode chips → Scan → display rows → session buttons (→ settings rows when in settings).
* `Enter` activates the focused item.
* `1` / `2` / `3` select Duplicate / Extend / Only remote directly.
* `s` opens session settings (only when a session exists); `d` disconnects; `r` rescans.
* `/` focuses the filter; typing filters by display name; `Esc` clears the filter before closing.
* `Esc` stack: picker → settings → main → close.
* Footers are exact:
  * main: `j/k move · Enter connect · 1/2/3 mode · s settings · d disconnect · r rescan · / filter · Esc close`
  * settings: `settings: j/k row · Enter act · Esc back`
  * picker: `picker: j/k option · Enter/l apply · h/Esc back`

## 5. Service Contract

`ScreenCastService.qml` is a singleton; the launcher is a pure view.

```qml
// state
property bool available          // daemon reachable
property bool daemonRunning
property bool scanning
property var sinks               // [{uuid, name, priority, state, protocol}]
property string mode             // duplicate | extend | only-remote
property var active              // {uuid, name, protocol, unit, mode} | null
property string sessionState     // idle | connecting | streaming | error
property bool localPanelOff
property bool extendOutputCreated
property string lastError
readonly property string extendOutput   // "SCREENCAST"
readonly property var castOutput        // mapped monitor for the cast source
signal dataUpdated()

// lifecycle
function open()                  // ensure the daemon is running
function close()                 // stop the daemon if no session is active
function ensureDaemon()
function refresh()               // re-read Displays
function rescan()

// session
function connectSink(sink)
function disconnect()
function setLocalPanel(on)
function applyOutput(key, value) // mode | scale | position

// labels
function protocolLabel(p)
function stateLabel(s)
function modeLabel(m)
```

The launcher never touches `busctl`, `systemctl`, `hyprctl` or `HyprService` directly.

## 6. Backend Notes

* **Daemon.** `gnome-network-displays-daemon` (session bus `org.gnome.NetworkDisplays.Manager`, object `/org/gnome/NetworkDisplays/Manager`) exposes:
  * `Displays` (`aa{sv}`): `uuid`, `display-name`, `priority`, `state`, `protocol`.
  * `StartStream(uuid) → unit_name`, `StopStream(unit_name)`.
  The service reads `Displays` with `busctl --user --json=short get-property` and parses it with `services/screenCastParse.js`.
* **NixOS packaging.** GND 0.99.0 hardcodes `/usr/libexec/gnome-network-displays-stream`, which does not exist on NixOS. `nixos/programs/quickshell.nix` overrides the package and substitutes the store `libexec` path. The `wrapGAppsHook` already wraps that binary, so the transient unit gets `GST_PLUGIN_SYSTEM_PATH_1_0`, `GI_TYPELIB_PATH` and `XDG_DATA_DIRS`.
* **Daemon lifecycle.** The service defines `gnome-network-displays-daemon.service` as a user unit, deliberately not enabled at login. `open()` starts it; `close()` stops it when no session is active. This avoids continuous Wi-Fi P2P discovery on machines that never cast.
* **Stream tracking.** `StartStream` returns a transient unit named `gnome-network-displays-stream-<uuid>.service`. `sessionState` is derived from `systemctl --user is-active <unit>` (1.5 s timer while a session exists), **not** from the daemon's `state` field: the daemon only refreshes `Displays` on sink add/remove, so that field is stale during a stream.
* **Disconnect.** Stops the transient unit with `systemctl --user stop` instead of `StopStream` — the unit outlives the daemon, and stopping it must work even if the daemon already exited. `StopStream` is equivalent while the daemon is running.
* **Auto-cleanup.** If the unit reports `failed` or stays `inactive` for four polls (~6 s), the service clears the session, removes a `SCREENCAST` output it created, restores DPMS, and surfaces the error, so a dropped TV does not leave a phantom monitor or a dark panel behind.
* **Reopen.** On refresh, the service scans `systemctl --user list-units 'gnome-network-displays-stream-*.service'` and adopts an already-running unit, so restarting the shell does not lose the session. The adopted mode is `duplicate` (the real mode is not recoverable from the unit).
* **Share dialog.** The stream binary opens a ScreenCast portal session with `MONITOR | WINDOW | VIRTUAL`. Hyprland's portal advertises all three types (`AvailableSourceTypes = 7`) but its picker lists only screens and windows, so the user picks the source there. This is why Extend pre-creates a named headless output and the hint tells the user to pick it.
* **Extend output.** `hyprctl output create headless SCREENCAST` before connecting; `hyprctl output remove SCREENCAST` after disconnect. Resolution/scale are applied through `HyprService.applyMonitor`, which composes `hyprctl eval` rules and preserves every other output's rule.
* **Only remote.** A manual **Local panel** toggle in session settings (default `On`) runs `hyprctl dispatch dpms off/on <built-in>`; `dpms on` also runs on disconnect. It is never automatic: the ScreenCast share picker is displayed on that panel, so turning it off before the picker is answered would lock the user out. The built-in output is resolved through `HyprService.refMonitorName` (never hard-coded). If DPMS freezes the captured frames on a given machine, the fallback is brightness 0 — recorded here as an open validation item.
* **Discovery scope.** `Displays` includes Wi-Fi Display P2P, Wi-Fi Display MICE (mDNS) and Chromecast sinks. No ports are opened here: the project's firewall is disabled; if it is ever enabled, allow `p2p-wl+`, TCP 7236/7250 and UDP 7236/5353.
* **Runtime-only.** No state file, no `hyprland.lua` writes, no persistence of mode or cast settings.

## 7. Empty / Error States

* Daemon missing or unreachable → list empty, muted `Network Displays unavailable — run \`update\` to install the daemon.`
* Daemon starting or scanning → muted `Scanning for displays…`
* No sinks → muted `No displays found — put the TV in Screen Mirroring / Wireless Display mode and press r.`
* Filter matches nothing → muted `No display matches the filter.`
* `StartStream` failure, unit `failed`, or the unit stays inactive for four polls → red error line; the session is cleared and any headless output/DPMS change is undone, so the user can retry.
* A connect is refused while another Process is busy (daemon start, scan, start, stop, headless create/remove) — the launcher simply does nothing.
* Headless creation failure → `Could not create the virtual output`; no stream is started.
* Daemon stops while the launcher is open → `available = false`; the list clears on the next refresh.

## 8. Acceptance

* [ ] `SUPER+K` toggles the launcher through `quickshell ipc call launcher toggle screencast`.
* [ ] Displays are listed automatically; `r` rescans; `/` filters by name.
* [ ] Mode chips and `1/2/3` update `ScreenCastService.mode`; the hint matches the mode.
* [ ] `Enter` on a display starts a stream; the session card shows name, protocol, mode and state.
* [ ] Extend creates `SCREENCAST` before connecting and removes it after disconnect.
* [ ] Only-remote exposes the Local panel toggle after streaming starts; the toggle turns the panel off/on and Disconnect restores it.
* [ ] Settings → Resolution/Scale write through `HyprService.applyMonitor` only for the Extend output; other modes show the "follows the built-in panel" note.
* [ ] Disconnect stops the unit and cleans up the headless output and DPMS state.
* [ ] Daemon starts on open and stops on close when idle; an active session keeps it alive.
* [ ] Reopening the launcher while streaming adopts the transient unit.
* [ ] Degraded states render as §7; no spinner or stale session is left behind.
* [ ] Uses `Theme.*` / `Icons.*` only; no hard-coded hex or glyphs.
* [ ] `quickshell -p` parses cleanly; `services/screenCastParse.js` unit tests pass.

## 9. Not Verified (no cast device available)

* Discovery and connection against a real Miracast TV (the daemon API was validated by source inspection; `Displays`/`StartStream` shapes are covered by parser tests and must be re-checked on hardware).
* Whether Hyprland's share picker lists the `SCREENCAST` headless output.
* Whether `dpms off` keeps the captured frames alive while casting the built-in panel.
* Audio casting (the daemon creates a `Network-Displays` sink; this launcher does not route to it).
* Chromecast sinks end-to-end (the daemon advertises support; untested here).
