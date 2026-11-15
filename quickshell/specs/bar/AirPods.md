# AirPods — Refined Spec

> Parent: Bar.md · Service: AirPodsService.qml · File: components/bar/AirPodsIcon.qml

---

## 1. Position

Battery badge for the connected AirPods in the bar's right group: **after the Audio icon and before Wi-Fi** (`Bar.qml`). Click opens `AirPods-Center` (`SUPER+ALT+A`). It is a read-only window on `AirPodsService`: no process, no timer, no write.

## 2. Geometry

* Height `Theme.barIconSlot` (the bar slot); width from content — `badgeRow.implicitWidth + 14` — because the badge carries a percentage next to the glyph, unlike the square icons around it.
* `radius: Theme.roundingItem`; background `Theme.bgHover` on hover, transparent otherwise, with a `Theme.durationFast` colour animation.
* Glyph `Icons.airpods` at `Theme.barIconSize`; the percentage at `Theme.fontSizeSmall`, 4 px after the glyph.
* Hidden — not drawn and taking no layout width — unless `daemonReachable && hasAirPods && hasBattery` (§3).

## 3. States

| State | Condition | Drawing | Colour |
|---|---|---|---|
| **Battery** | reachable, AirPods connected, a level known | `Icons.airpods` + `{lowest}%` | `Theme.fg` |
| **Charging** | any pod, the case or the headset charging | same | `Theme.accent` |
| **Low battery** | `lowest ≤ 20` | same | `Theme.warning` |
| **Daemon down** | `!daemonReachable` (status file gone, or a start that failed) | nothing | — |
| **Disconnected** | `daemonReachable && !hasAirPods` | nothing | — |
| **No reading** | connected but no pod, case or headset level known (`!hasBattery`) | nothing | — |

* The percentage is the **lowest known** level across `leftPod`, `rightPod`, `caseBattery` and `headsetBattery`. A reading the daemon reports as unknown is dropped before the minimum, so a part it has stopped hearing from never wins.
* Low battery wins over charging when both apply: the ≤ 20 % test comes first.
* **Unknown case:** a case with no reading is ignored for the minimum and its tooltip slot prints `--`; the badge keeps showing the lowest known earbud level. If every earbud and case reading is unknown, the badge hides (`No reading`).
* **Unknown lid:** the lid is not part of the badge — it is the case row's `Lid Open` / `Lid Closed` in `AirPods-Center`. An unknown or unreadable lid therefore changes nothing here.

## 4. Interaction

* **Click** → the bar asks the shell to toggle `airpods`, exactly like `SUPER+ALT+A`. The badge never mutates the service.
* **Hover** → `BarToolTip` anchored to the badge, at most three lines, each omitted when empty:
  1. device name, else the model name, else both once as `name · model`;
  2. levels — `L {n}% · R {n}% · C {n}%` for earbuds, `H {n}%` for a headset, `--` for an unknown slot;
  3. the state that applies — the mode name (`Off`, `Transparency`, `Adaptive`, `Noise Cancellation`), `CA on`/`CA off` when supported, `1-bud on`/`1-bud off` when supported, `Ear one out`/`Ear both out`/`Ear off`.
* No scroll action, no second click target: volume and output device stay in the Audio Center, connect/disconnect/forget in the Bluetooth Center.

## 5. Service Contract

Read-only bindings over `AirPodsService.qml`; the badge imports no `Process` and no `Timer`:

```qml
readonly property bool hasAirPods        // the daemon reports a connected device
readonly property bool hasBattery        // any earbud/case (or headset) level known
property var leftPod                     // { level, charging, inEar }
property var rightPod
property var caseBattery                 // { level, charging }
property var headsetBattery              // { level, charging }
property bool isHeadset
property string deviceName
property string modelName
property int noiseMode                   // Parse.NOISE_*
property bool conversationalAwareness
property bool oneBudANC
property int earDetectionBehavior        // Parse.EAR_*
property bool daemonReachable
```

* `daemonReachable` turns true as soon as the daemon writes its status file, even when the line cannot be parsed: presence proves the daemon runs, and removal means it stopped. A parse error belongs to `lastError`, not to the badge.
* The service keeps the last readings after the daemon stops, so the badge gates on `daemonReachable` as well as on the levels and never shows a stale percentage.
* `hasBattery` follows the device shape: any of the three earbud/case readings, or the single headset reading.
* Updates arrive through the service's status-file watch; there is no polling, no refresh timer and no `librepods-ctl` call from the bar.
* The panel and the badge read the same singleton, so a mode or feature changed in `AirPods-Center` updates the tooltip without extra wiring.

## 6. Acceptance

* [ ] Badge sits between the Audio icon and Wi-Fi in the right group.
* [ ] Hidden when the daemon is down, when no AirPods are connected, and when no level is known — including right after the daemon stops, which leaves levels behind in the service.
* [ ] With a level known, the badge prints `Icons.airpods` plus the lowest known level as `{n}%`, and follows the status file when it changes.
* [ ] `≤ 20 %` draws `Theme.warning`, any charging reading draws `Theme.accent` (low battery wins), otherwise `Theme.fg`.
* [ ] The tooltip shows name/model, per-slot levels (one `H` line for a headset, `--` for an unknown slot) and the mode plus CA/One-Bud/Ear state, capped at three lines.
* [ ] Click toggles `AirPods-Center`; hover uses `Theme.bgHover`; the badge contains no `Process`, `Timer` or service write, and no hard-coded glyph or colour.
* [ ] Offscreen smoke (`bash quickshell/tests/smoke-airpods.sh`): the badge loads, is visible with the fixture's battery, reports the fixture's lowest known level and prints it as a percentage.
