# Audio — Bar Icon — Refined Spec

> Parent: [`Bar.md`](./Bar.md) · Service: `services/AudioService.qml` over `Quickshell.Services.Pipewire`

---

## 1. Purpose

Glyph in the right group reflecting the **default sink** volume/mute state.
Click opens `Audio-Center` (`SUPER+a`).

## 2. States & Glyphs

| State | Condition | Glyph | Colour | Tooltip |
|---|---|---|---|---|
| **Volume n%** | `!muted && sink != null` | `Icons.audioVolume` (``) + `" {volume}% "` | `Theme.fg` | `"{sinkName}: {volume}%"` |
| **Muted** | `muted === true` | `Icons.audioMuted` (`🔇`) | `Theme.fgDim` | `"Muted — {sinkName}"` |
| **No sink** | `Pipewire.defaultAudioSink == null` | `🔇` | `Theme.critical` | `"No audio device"` |

Format parity with Waybar `wireplumber: { format: "  {volume}% ", format-muted: "🔇" }`.

* Optional tiered icons (low/medium/high) may be added later; not required for v1.
* Text form: `"  42% "` including the leading space inside the format — replicate Waybar spacing.

## 3. Service Contract — `AudioService.qml`

Thin wrapper; prefer `Quickshell.Services.Pipewire` directly when possible.

```qml
QtObject {
  readonly property PwNode sink: Pipewire.defaultAudioSink
  readonly property bool muted: sink ? sink.audio.muted : false
  readonly property int volume: sink ? Math.round(sink.audio.volume * 100) : 0
  readonly property string sinkName: sink ? sink.description : ""
  // microphones exposed for launcher but not needed for bar icon
  readonly property list<PwNode> sources: Pipewire.nodes.values.filter(n => n.isSource)
}
```

* **Bind to PipeWire signals** — no polling. `Pipewire` emits `defaultAudioSinkChanged`, `PwNode.audio.volumeChanged`, `mutedChanged`.
* **Fallback** if `Pipewire` unavailable (e.g., PulseAudio-only host): `Process { command: ["wpctl","get-volume","@DEFAULT_AUDIO_SINK@"] }` parsed at 2s.
* **Scroll to adjust** — optional parity with Waybar `scroll-step: 5`: `MouseArea { onWheel: sink.audio.volume = clamp(...) }` with step 0.05.

## 4. Interaction

* **Click** → `launcher.toggle("audio")`.
* **Scroll up/down** → volume ±5% (if enabled; must clamp 0–1.0 and not fight PipeWire's own limits).
* **Hover** → tooltip with sink name + volume.

## 5. Launcher Sync

`Audio-Center` mutates the same `Pipewire` nodes. Bar icon updates via signal — no extra wiring.

## 6. Error Handling

* No PipeWire daemon → degraded `🔇` + tooltip "PipeWire unavailable — is `wireplumber` running?".
* `defaultAudioSink` is null at startup → retry on `Pipewire.readyChanged` (debounce 500 ms).

## 7. Acceptance

* [ ] Volume changes via `wpctl` / `pavucontrol` / launcher reflect on icon within 200 ms.
* [ ] Mute toggles glyph and colour correctly.
* [ ] Scroll adjusts volume without opening launcher (if implemented).
* [ ] No polling when PipeWire service is available.
* [ ] Degraded state renders when PipeWire is stopped.
