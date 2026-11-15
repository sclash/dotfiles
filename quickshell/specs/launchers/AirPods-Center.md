# AirPods-Center — Refined Spec

> Command: `SUPER+ALT+A` · File: `components/launchers/AirPodsCenter.qml` · View: `components/launchers/airpods/AirPodsView.qml` · Service: `AirPodsService.qml`

---

## 1. Purpose

Center-screen window to inspect and change the connected AirPods: per-pod, case or headset battery, listening mode, Adaptive level, Conversation Awareness, One-Bud ANC and ear detection. It is a pure reader/writer over `AirPodsService`; the `AirPods` bar badge reflects the same singleton.

The panel owns no process and no timer. Opening it tells `AirPodsService` the panel is open, which may start `librepods`; closing always reports the panel closed, because a card left open would keep the daemon alive in the background.

## 2. Window

* Overlay `WlrLayershell` in the Audio Center pattern: full-screen dim (`Theme.overlay`), `WlrLayer.Overlay`, `ExclusionMode.Ignore`, exclusive keyboard focus.
* Card: `width: 620`, `height: Math.min(640, view.implicitHeight)`, centered, `Theme.bgLauncher`, `radius: Theme.roundingLauncher`, 1 px `Theme.borderActive`, clipped.
* Content: `AirPodsView.qml` fills the card and owns the rows, the selection and every key; the overlay routes each key through its one `handleKey()`.
* A click on the dim closes. `Esc` closes (after clearing the filter). `q` closes while the list has focus; the filter field takes it as text.
* Opening resets the selection to the first row, clears the filter, refreshes the status file and takes focus.
* Content taller than 640 px scrolls inside the card: a `Flickable` with a 4 px `ScrollBar` (`Theme.borderActive`), and the selected row is kept visible on every move.

## 3. Battery

Top section, after the header (`AirPods` label, separator, device name, model line):

* **Earbuds:** `Left`, `Right`, `Case`.
* **Headset (AirPods Max):** a single `Headset` row, no case row.
* Row shape: battery mark (`Icons.battery`, or `Icons.batteryCharging` at `Theme.accent` while charging), label, a 72×3 px meter, the level right-aligned in a fixed 42 px column, then the hint.
* Level text is `{level}%`, or `--` when the daemon reports no reading (`Parse.levelText`). The meter fills `level/100` and draws an empty track for an unknown level.
* Meter colour: `Theme.warning` at ≤ 20 %, `Theme.accent` while charging, otherwise `Theme.fgMuted`.
* Hint (10 px, `Theme.fgMuted`): `Charging` when that part charges, otherwise `In ear` when it is worn. Charging wins.
* The case row appends `Lid Open` / `Lid Closed` when the daemon reports the lid. An unknown lid prints nothing — including while the daemon pauses its BLE scan and cannot read the case at all.
* Levels are drawn only while the panel is live (`daemonReachable && connected`). Not live → `--`, no hint, no lid, even though the service keeps the last readings after the daemon stops.

## 4. Listening

Only the modes the device has, in the order `availableModes()` returns:

| Row | Shown when |
|---|---|
| `Off` | `supportsNoiseControl` and `supportsNoiseOff` |
| `Transparency` | `supportsNoiseControl` |
| `Adaptive` | `supportsAdaptive` |
| `Noise Cancellation` | `supportsNoiseControl` |

* The heading and its rows are absent when `availableModes()` is empty (AirPods 1/2/3, plain AirPods 4) and while the AirPods are not connected.
* Active mode: label `Theme.fgBright` plus `Icons.check` at `Theme.success`; every other row `Theme.fg`.
* `Enter`, `Space` or a click sends the row's mode. `o` / `t` / `a` / `n` select `Off` / `Transparency` / `Adaptive` / `Noise Cancellation` directly and are ignored when that mode is not in `availableModes()`.
* **Adaptive level** row: only while `supportsAdaptive` and Adaptive is the active mode. 90×3 px meter (`Theme.fgMuted` fill), level right-aligned in 42 px, and an `h/l` hint. `h`/`l` or `←`/`→` step it by 5 %; the service clamps to 0–100. The row takes the cursor, but `Enter` does nothing on it.

## 5. Features

Rows in this order, each one line with the current value spelled out:

| Row | Shown when | Value | Key |
|---|---|---|---|
| `Conversation Awareness` | `supportsConversationalAwareness` | `On` / `Off` | `c` |
| `One-Bud ANC` | `supportsOneBudANC` | `On` / `Off` | `b` |
| `Ear detection` | connected | `Pause when one is out` / `Pause when both are out` / `Never pause` | `e` |
| `Refresh` | always | `Working…` while a verb runs | `r` |

* `Enter`, `Space` or a click toggles CA and One-Bud, cycles ear detection one → both → never → one, and refreshes on the `Refresh` row.
* The on-value is `Theme.fgBright`, off is `Theme.fgMuted`, and the `Refresh` value is `Theme.fgDim`.
* `c` and `b` are no-ops unless the matching capability flag is set and the device is connected; `e` is a no-op while disconnected.

## 6. Shared Behaviours

* **Vim nav:** `j`/`k` and `↓`/`↑` move `selIndex` across the flattened listening + feature rows, stopping at both ends. The selected row is `Theme.bgSelected` with a 1 px `Theme.borderSelected` border.
* **Activate:** `Enter`, keypad `Enter` or `Space`. A row click selects and then activates, so both paths agree.
* **Filter:** `/` opens an inline field above the list and filters row labels by case-insensitive substring. Battery rows are outside the list and are never hidden. `Enter` in the field returns focus to the list with the query kept. No match shows `No matching settings`.
* **Clear and close:** `Esc` clears the filter when it is open; otherwise it asks the overlay to close. `q` closes from the list; the filter field consumes it as text.
* **Footer:** `j/k · Enter · o/t/a/n modes · c CA · b One-Bud · e ear · r refresh · / filter · Esc close` at `Theme.fgDim`.
* **Refresh** is reachable three ways: the `Refresh` row, `r`, and opening the panel (the overlay calls the service).
* Every value is a binding over `AirPodsService`; no `Process` and no `Timer` in `AirPodsCenter.qml` or `AirPodsView.qml`.

## 7. Service Contract

`AirPodsService.qml` singleton (the bar's read-only view of it is in [`../bar/AirPods.md`](../bar/AirPods.md)):

```qml
function availableModes(): list<int>                  // Off, Transparency, Adaptive, ANC — only those supported
function refresh(): void                              // re-reads $XDG_STATE_HOME/librepods/status.json
function setNoiseMode(mode: int): void                // noise:off | noise:anc | noise:transparency | noise:adaptive
function setAdaptiveNoiseLevel(level: int): void      // adaptive:0 … adaptive:100, clamped
function setConversationalAwareness(on: bool): void   // ca:on | ca:off
function setOneBudANC(on: bool): void                 // onebud:on | onebud:off
function setEarDetectionBehavior(behavior: int): void // ear:one | ear:both | ear:off
function cycleNoiseMode(): void
function cycleEarDetection(): void
function notePanelOpen(): void                        // panelOpen = true; may start librepods
function notePanelClosed(): void                      // panelOpen = false; may stop librepods
```

* The panel calls `setNoiseMode` directly for `o/t/a/n` and for `Enter` on a mode row; `cycleNoiseMode()` exists for callers that cycle instead of selecting. `cycleEarDetection()` backs `e` and the `Ear detection` row.
* One verb runs at a time. The new value is shown optimistically for 4 s or until the daemon's status line agrees; a verb arriving mid-flight replaces the queued one, so key repeat cannot build a burst.
* `actionStatus` holds the last successful verb for 2.2 s, and `busy` is true while a verb runs — the `Refresh` row prints `Working…` from `busy`.
* `lastError` carries a verb's stderr or the parser's line, collapsed to one line. A parse error is dropped when the daemon next reports a good line; a `ctl` error survives a good status line and is cleared by the next successful verb. `refresh()` only reloads the file — the `status` verb is for live diagnostics, not for `r`.
* `notePanelOpen()` / `notePanelClosed()` are the only lifecycle calls the panel makes. The daemon runs while the panel is open or the AirPods are connected, and stops when neither holds.
* Read-only fields the panel binds: `daemonReachable`, `daemonStarting`, `lifecycleError`, `connected`, `deviceName`, `modelName`, `modelNumber`, `isHeadset`, the `supports*` flags, `noiseMode`, `adaptiveNoiseLevel`, `conversationalAwareness`, `oneBudANC`, `earDetectionBehavior`, `lidState`, `leftPod`, `rightPod`, `caseBattery`, `headsetBattery`, `lastError`, `busy`.

## 8. Degraded States

Each renders as one line under the header, with a hint where one helps:

| State | Line | Colour |
|---|---|---|
| Daemon starting | `Connecting…` | `Theme.fgMuted` |
| Daemon not running | `librepods is not running` + `systemctl --user start librepods` | `Theme.warning` / hint `Theme.fgDim` |
| Start failed or timed out | `lifecycleError` (`systemctl`'s error, or `librepods did not start — journalctl --user -u librepods` after 8 s) replaces the hint | `Theme.fgDim` |
| Disconnected | `AirPods not connected`; title `Not connected` | `Theme.fgMuted` |
| Unknown model | device name still shows; model line `Model {number}` or `Model not recognised` | `Theme.fgMuted` |
| Status schema too new | `librepods speaks status schema N, this panel reads 1` | `Theme.critical` |
| Empty / malformed status | `The librepods status file is empty`, `Could not read the librepods status file`, or `… carried no schema_version` | `Theme.critical` |
| `librepods-ctl` error | the verb's stderr behind `Icons.warning`; `librepods-ctl could not run` when the binary is missing | `Theme.critical` |

* Battery rows fall back to `--`; the listening section disappears; `Ear detection` disappears; `Refresh` always stays, so the user can retry.
* A readable status that says `connected: false` is a real disconnect (`Not connected`); a starting, stopped or unreadable daemon gets its own line instead, so the title stays `AirPods`.
* The panel never invents a level or a mode: a failed or too-new parse leaves the parser's defaults in place rather than the last good values.

## 9. Acceptance

* [ ] `SUPER+ALT+A` and `quickshell ipc call launcher toggle airpods` open and close the panel; the dim click, `Esc` and `q` close it.
* [ ] Card is 620 px wide with `Theme.roundingLauncher` on `Theme.bgLauncher`, dim behind it, content clipped and scrollable, selection kept visible.
* [ ] Battery rows follow the device shape: `Left`/`Right`/`Case` for earbuds, one `Headset` row for a headset; unknown readings print `--`; ≤ 20 % uses `Theme.warning`; charging uses `Icons.batteryCharging` at `Theme.accent`; the case prints the lid only when known.
* [ ] Listening shows only the supported modes, in `Off | Transparency | Adaptive | Noise Cancellation` order, with `Icons.check` at `Theme.success` on the active one; it is absent when `availableModes()` is empty or the AirPods are disconnected.
* [ ] The Adaptive level row appears only while Adaptive is the active mode, and `h`/`l` ± `←`/`→` step it by 5 % inside 0–100.
* [ ] `c` and `b` are gated by their capability flags, and `c`, `b` and `e` do nothing while disconnected; `r` and the `Refresh` row re-read the status file and print `Working…` while a verb is in flight.
* [ ] `j`/`k`/arrows move, `Enter`/`Space` activate, `/` filters labels and never battery rows, `Esc` clears then closes, `q` closes from the list.
* [ ] Opening starts `librepods` when it is down (once), shows `Connecting…` for up to 8 s, then the `systemctl` error with the journal hint; closing stops it again unless the AirPods are connected.
* [ ] Every state in §8 renders with the stated text and colour, and a `librepods-ctl` failure clears on the next success.
* [ ] Offscreen smoke (`bash quickshell/tests/smoke-airpods.sh`): the view loads, the nav order is the supported modes then `adaptive, ca, onebud, ear, refresh`, the mode labels are the daemon's names, `j` moves the cursor, `/` opens the filter, the first `Esc` clears it without closing, the second closes, and a `ctl` error surfaces in `lastError`.
* [ ] No `Process`, `Timer` or `systemctl` call in `AirPodsCenter.qml`/`AirPodsView.qml`; colours and glyphs come from `Theme`/`Icons` only.
