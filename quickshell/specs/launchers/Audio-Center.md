# Audio-Center — Refined Spec

> Command: `SUPER+a` · File: `components/launchers/AudioCenter.qml` · Service: `AudioService.qml` / `Quickshell.Services.Pipewire`

---

## 1. Purpose

Center-screen window to inspect and mutate audio: default sink/source, available devices, volume, mute. Mutations reflect in the `Audio` bar icon via the shared `Pipewire` graph.

## 2. Window

* `LauncherBase.qml`: `width: 580`, `radius: Theme.roundingLauncher`, vim nav, `/` filter, `Esc` closes.

## 3. Sections (top → bottom)

### 3.1 Output — Current Sink

* **Row:** `device.description` (bold) + `volume%` + `muted` badge if muted. Flat row — no card/box.
* **Slider:** slim 4px track, `Theme.border` background, filled `Theme.fgMuted`, 12px thumb `Theme.fg`. Quiet `−`/`+` step buttons at 5%.
* **Mute toggle:** checkbox / `Switch` or button — `sink.audio.muted = !sink.audio.muted`.
* If `Pipewire.defaultAudioSink == null` → `"No output device"` at `Theme.fgMuted`.

### 3.2 Output — All Sinks

* List of `Pipewire.nodes.values.filter(n => n.isSink && !n.isStream)`.
* Each row: `description` + `volume%` + active check `Icons.check` if `n === defaultAudioSink`. Rows are flat (no boxes); active device shown via `Theme.fgBright` text + check.
* **Change device:** `Enter` or click row → `Pipewire.defaultAudioSink = n` (preferred) or `wpctl set-default {n.id}` via `AudioService.setDefaultSink(id)`.
* Rows update when devices are plugged/unplugged via `Pipewire.nodesChanged`.

### 3.3 Input — Current Source (Microphones)

* Symmetric to Output — Current Sink but for `Pipewire.defaultAudioSource`.
* Slider + mute for the mic. Same null/empty handling.

### 3.4 Input — All Sources

* List of `Pipewire.nodes.values.filter(n => n.isSource && !n.isStream)` with same change-device behaviour via `Pipewire.defaultAudioSource` / `wpctl set-default`.

## 4. Shared Behaviours

* **Vim nav:** `j/k` moves `currentIndex` across sinks then sources (flattened list or section-aware — either is fine, document the choice). `Enter` selects device or toggles mute if focus is on the slider row. `h/l` or `Left/Right` adjusts volume 5% when a device row is focused.
* **Filter:** `/` filters device lists by `description` substring.
* **No polling** — PipeWire signals drive updates. Sliders bind to `sink.audio.volume` directly.

## 5. Styling

* Active device row: `Icons.check` at `Theme.success`.
* Muted: row text `Theme.fgDim`, badge at `Theme.warning`.
* Slider filled track: `Theme.fgMuted`; thumb: `Theme.fg`. Output and Input sections are visually identical (flat icon + name + switch + slim slider).

## 6. Service Contract

Prefer direct `Pipewire` bindings; wrap `wpctl` fallback in `AudioService`:

```qml
function setDefaultSink(id: int): void   // wpctl set-default {id}
function setDefaultSource(id: int): void
```

## 7. Acceptance

* [ ] Current sink/source show with slider + mute; changes reflect in bar icon within 200 ms.
* [ ] All-sinks/sources lists populate and hot-plug correctly.
* [ ] Changing default device updates `Pipewire.defaultAudioSink/Source` and the bar icon.
* [ ] Vim nav + `/` filter + `h/l` volume adjust + `Esc` close work.
* [ ] No polling; PipeWire signals are the source of truth.
* [ ] Degraded `"No output/input device"` states render when PipeWire has no nodes.
