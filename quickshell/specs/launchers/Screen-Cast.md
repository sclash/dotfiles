# Screen-Cast — Refined Spec

> Command: `SUPER+SHIFT+K` · File: `components/launchers/ScreenCastLauncher.qml` · Service: `ScreenCastService.qml` · Backend: `org.gnome.NetworkDisplays.Manager` (session bus) + `hyprctl`

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
| **Duplicate** (default) | `duplicate` | No pre-action. The main output (`HyprService.refMonitorName`) is shared; the desktop is cloned. |
| **Extend** | `extend` | `hyprctl output create headless SCREENCAST` runs before `StartStream`, then `SCREENCAST` is placed flush right of the main output (`HyprService.refMonitorName`), top edges aligned, so the cursor and windows can cross onto it. The catch-all `position = "auto"` rule otherwise lets Hyprland stack it anywhere, e.g. above the panel. `SCREENCAST` is shared. |
| **Only remote** | `only-remote` | Same as Duplicate; after streaming starts, session settings exposes a **Local panel** toggle. The panel is never turned off automatically: if the share picker falls back to the dialog (§6), it is displayed on that panel. |
| **Window** | `window` | Choosing a display opens the picker (§3.4) over the open windows (`Hyprland.toplevels`: title · app id); picking one connects and shares only that window. No window open → nothing happens. |

The selected mode is stored in `ScreenCastService.mode`. The hint line under the chips states, in plain language, what will be shared. No share dialog appears: the launcher answers the portal itself (§6, **Share source**).

### 3.2 Displays (scan)

* Section label `Displays`, `Scan` button (`ScreenCastService.rescan()`), and an inline filter field when `/` is pressed.
* Rows come from `ScreenCastService.sinks` (`uuid`, `name`, `protocol`, `state`). Each row shows the sink name, `protocolLabel(protocol) · stateLabel(state)`, and `Icons.monitor`.
* `Enter` (or click) calls `ScreenCastService.connectSink(sink)`. Connections are refused while a session is active or a Process is busy.
* Sorted as returned by the daemon (priority de-duplication is the daemon's job).

### 3.3 Session card (visible when a session exists)

* Name, protocol, and mode; subline is mode-aware:
  * `connecting` → `"<Mode> · waiting for the share dialog…"` (the dialog only appears when the share picker falls back, §6)
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

The picker opens in place (list replaces the row navigation, and the main view while picking a window): `j/k` moves, `Enter`/`l` applies, `Esc`/`h` cancels. The same picker lists windows for mode `window` before connecting.

### 3.5 Error line

`ScreenCastService.lastError` renders at `Theme.critical` with `Icons.warning`, wrapped, below the sections.

## 4. Interaction

* `j/k` moves across mode chips → Scan → display rows → session buttons (→ settings rows when in settings).
* `Enter` activates the focused item.
* `1` / `2` / `3` / `4` select Duplicate / Extend / Only remote / Window directly.
* `s` opens session settings (only when a session exists); `d` disconnects; `r` rescans.
* `/` focuses the filter; typing filters by display name; `Esc` clears the filter before closing.
* `Esc` stack: picker → settings → main → close.
* Footers are exact:
  * main: `j/k move · Enter connect · 1-4 mode · s settings · d disconnect · r rescan · / filter · Esc close`
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
function open()                  // ensure the daemon is running (not while casting)
function close()                 // stop the daemon if it still runs
function ensureDaemon()
function refresh()               // re-read Displays
function rescan()

// session
function connectSink(sink, windowAddress) // windowAddress required in mode "window"
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
* **Daemon lifecycle.** The service defines `gnome-network-displays-daemon.service` as a user unit, deliberately not enabled at login. `open()` starts it; `close()` stops it. This avoids continuous Wi-Fi P2P discovery on machines that never cast. The daemon is also stopped as soon as `StartStream` returns a unit (or a running unit is adopted), for the whole session: its Wi-Fi P2P provider calls `StartFind` on every NetworkManager device state change, and a find during GO negotiation cancels the connect (wpa_supplicant `CONNECT -> SEARCH`, then NM `connecting took too long`, `Sink error`). GNOME Network Displays' own window turns discovery off while connecting; the daemon's D-Bus API has no such switch. `refresh()` does nothing while a session is active, and discovery resumes when the session ends with the launcher open.
* **Startup race.** The unit is `Type=dbus` with `BusName=org.gnome.NetworkDisplays.Manager`. With the default `Type=simple`, `systemctl start` returns as soon as the process forks — before GApplication acquires the name — so the first `get-property` races and fails with *"The name is not activatable"*. `Type=dbus` blocks `start` until the name is owned. `TimeoutStartSec=15s` keeps a stuck daemon from holding the call for 90 s. The service also retries a transient "not activatable"/`ServiceUnknown` reply up to six times at 250 ms before setting `available = false`, covering a daemon that crashes between `is-active` and `get-property`.
* **Empty stderr.** `StdioCollector` fires even when stderr is empty, and it runs after stdout. The failure decision therefore lives in `displaysProc.onExited`, keyed on the exit code, so a successful `get-property` is never overwritten by the generic "Network Displays daemon unavailable" message.
* **Stream tracking.** `StartStream` returns a transient unit named `gnome-network-displays-stream-<uuid>.service`. `sessionState` is derived from `systemctl --user is-active <unit>` (1.5 s timer while a session exists), **not** from the daemon's `state` field: the daemon only refreshes `Displays` on sink add/remove, so that field is stale during a stream.
* **Disconnect.** Stops the transient unit with `systemctl --user stop` instead of `StopStream` — the unit outlives the daemon, and stopping it must work even if the daemon already exited. `StopStream` is equivalent while the daemon is running.
* **Auto-cleanup.** If the unit reports `failed` or stays `inactive` for four polls (~6 s), the service clears the session, removes a `SCREENCAST` output it created, restores DPMS, and surfaces the error, so a dropped TV does not leave a phantom monitor or a dark panel behind.
* **Reopen.** On refresh, the service scans `systemctl --user list-units 'gnome-network-displays-stream-*.service'` and adopts an already-running unit, so restarting the shell does not lose the session. The adopted mode is `duplicate` (the real mode is not recoverable from the unit).
* **Share source.** The stream binary opens a ScreenCast portal session with `MONITOR | WINDOW | VIRTUAL`, and xdg-desktop-portal-hyprland asks a picker program for the source. `hypr/xdph.conf` sets `screencopy:custom_picker_binary = quickshell-share-picker` (`quickshell/scripts/share-picker.sh`, packaged in `nixos/programs/quickshell.nix`). Right before `StartStream`, in the same process, the service writes the source to `$XDG_RUNTIME_DIR/quickshell-cast-source` (mode 0600): `screen:<main output>`, `screen:SCREENCAST` or `window:0x<Hyprland address>`. The picker answers XDPH with it (`[SELECTION]/screen:<name>`, or `[SELECTION]/window:<toplevel handle>` mapped through `XDPH_WINDOW_SHARING_LIST`) and deletes the file. With no file, a choice older than 30 s, an unknown choice or a window that has closed, it runs `hyprland-share-picker`, so every other share (browser, OBS) keeps the stock dialog. A failed connect also deletes the file. XDPH reads `xdph.conf` only at startup. Tested by `quickshell/tests/test-share-picker.sh`.
* **Extend output.** `hyprctl output create headless SCREENCAST` before connecting; `hyprctl output remove SCREENCAST` after disconnect. Resolution/scale are applied through `HyprService.applyMonitor`, which composes `hyprctl eval` rules and preserves every other output's rule.
* **Only remote.** A manual **Local panel** toggle in session settings (default `On`) runs `hl.dsp.dpms({ action = "off"/"on", monitor = <built-in> })` through `hyprctl dispatch`; `dpms on` also runs on disconnect. It is never automatic: the ScreenCast share picker is displayed on that panel, so turning it off before the picker is answered would lock the user out. The built-in output is resolved through `HyprService.refMonitorName` (never hard-coded). If DPMS freezes the captured frames on a given machine, the fallback is brightness 0 — recorded here as an open validation item.
* **Discovery scope.** `Displays` includes Wi-Fi Display P2P, Wi-Fi Display MICE (mDNS) and Chromecast sinks. No ports are opened here: the project's firewall is disabled; if it is ever enabled, allow `p2p-wl+`, TCP 7236/7250 and UDP 7236/5353.
* **wpa_supplicant restarts.** NixOS's wpa_supplicant module restarts the daemon from udev whenever a wlan interface is added or removed. A Wi-Fi Display P2P connect creates a `p2p-<iface>-N` group interface, so the restart tore the link down and the stream exited with `NdStream: Sink error`. `nixos/configuration.nix` skips that rule while wpa_supplicant is D-Bus controlled by NetworkManager.
* **wpa_supplicant signals.** NixOS runs wpa_supplicant as the unprivileged `wpa_supplicant` user, and NetworkManager's D-Bus policy only accepts non-root messages on a fixed list of interfaces, so the bus silently dropped `fi.w1.wpa_supplicant1.Interface.P2PDevice.DeviceFound`. wpa_supplicant found the TV (`P2P-DEVICE-FOUND`) while NM's `Peers` stayed empty and the launcher listed nothing. `nixos/configuration.nix` adds a policy that lets the `wpa_supplicant` group send signals (not method calls) to NetworkManager.
* **Runtime-only.** No state file, no `hyprland.lua` writes, no persistence of mode or cast settings.

## 7. Empty / Error States

* Daemon missing or unreachable → list empty, muted `Network Displays unavailable — run \`update\` to install the daemon.`
* Session active → muted `Discovery is paused while casting — disconnect to pick another display.`
* Daemon starting or scanning → muted `Scanning for displays…`
* No sinks → muted `No displays found — put the TV in Screen Mirroring / Wireless Display mode and press r.`
* Filter matches nothing → muted `No display matches the filter.`
* `StartStream` failure, unit `failed`, or the unit stays inactive for four polls → red error line; the session is cleared and any headless output/DPMS change is undone, so the user can retry.
* A connect is refused while another Process is busy (daemon start, scan, start, stop, headless create/remove) — the launcher simply does nothing.
* Headless creation failure → `Could not create the virtual output`; no stream is started.
* Daemon stops while the launcher is open → `available = false`; the list clears on the next refresh. A successful refresh clears the stale error and returns to the list; a session error stays until its stream is no longer active.

## 8. Acceptance

* [ ] `SUPER+SHIFT+K` toggles the launcher through `quickshell ipc call launcher toggle screencast`.
* [ ] Displays are listed automatically; `r` rescans; `/` filters by name.
* [ ] Mode chips and `1-4` update `ScreenCastService.mode`; the hint matches the mode.
* [ ] Connecting shares the mode's source with no share dialog; a browser screen share still gets the dialog.
* [ ] Window mode lists the open windows; picking one casts only that window.
* [ ] `Enter` on a display starts a stream; the session card shows name, protocol, mode and state.
* [ ] Extend creates `SCREENCAST` before connecting and removes it after disconnect.
* [ ] Only-remote exposes the Local panel toggle after streaming starts; the toggle turns the panel off/on and Disconnect restores it.
* [ ] Settings → Resolution/Scale write through `HyprService.applyMonitor` only for the Extend output; other modes show the "follows the built-in panel" note.
* [ ] Extend places `SCREENCAST` right of the main output; the cursor crosses onto it.
* [ ] Disconnect stops the unit and cleans up the headless output and DPMS state.
* [ ] Daemon starts on open and stops on close; it stops when a stream starts and restarts when the session ends with the launcher open.
* [ ] Reopening the launcher while streaming adopts the transient unit.
* [ ] Degraded states render as §7; no spinner or stale session is left behind.
* [ ] Uses `Theme.*` / `Icons.*` only; no hard-coded hex or glyphs.
* [ ] `quickshell -p` parses cleanly; `services/screenCastParse.js` unit tests pass.

## 9. Not Verified (no cast device available)

* Discovery and connection against a real Miracast TV (the daemon API was validated by source inspection; `Displays`/`StartStream` shapes are covered by parser tests and must be re-checked on hardware).
* Whether `dpms off` keeps the captured frames alive while casting the built-in panel.
* Audio casting (the daemon creates a `Network-Displays` sink; this launcher does not route to it).
* Chromecast sinks end-to-end (the daemon advertises support; untested here).
