# Audio Center Selection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the focused sink/source row in the Audio Center unmistakable, using the same row focus treatment as Network Center.

**Architecture:** Rebuild `AudioCenter.qml` on the Network/Bluetooth launcher pattern: a `Flickable` card, a `/` filter field, `filteredSinks`/`filteredSources` arrays driving `navItems`, and 44px rows whose focus state is `Theme.bgSelected` + a 1px `Theme.borderSelected` outline. Extend `AudioService` to track every audio node (so per-device volume works) and to rebuild its lists on `Pipewire.nodes.valuesChanged` (hot-plug).

**Tech Stack:** QML / Quickshell 0.3.2 / `Quickshell.Services.Pipewire`.

**Spec:** `specs/launchers/Audio-Center.md` (§3.2, §3.4, §4, §5).

## Global Constraints

- No hard-coded colours or glyphs outside `theme/Theme.qml` and `theme/Icons.qml` — use `Theme.*` / `Icons.*`.
- No polling: PipeWire signals drive list updates.
- Launchers mutate audio; the bar icon stays read-only over `AudioService`.
- Card stays 620px wide; `Esc` closes (or leaves the filter first).
- Focused row: `color: Theme.bgSelected`, `border.color: Theme.borderSelected`, `border.width: 1`.
- Active/default row: `Icons.check` at `Theme.success` + `Theme.fgBright` text.

## Review Focus

- Zero sinks or sources (PipeWire not ready): the lists must render `"No output devices"` / `"No input devices"` instead of collapsing silently.
- Filter text matching nothing: the list must say `"No matching outputs"` / `"No matching sources"`, not the no-device copy.
- Fewer devices than `selIndex` after a filter keystroke: `selIndex` must clamp, never index past the array.
- `h/l` on a non-default device: must change *that* node's volume, and do nothing when the node has no audio object.
- Hot-plug while the launcher is open: a new sink/source must appear without closing and reopening.

---

### Task 1: AudioService tracks all nodes and reacts to hot-plug

**Files:**
- Modify: `services/AudioService.qml:24-26` (tracker), `services/AudioService.qml:30-35` (connections)

**Interfaces:**
- Consumes: `Pipewire.nodes` (`UntypedObjectModel`, `values`), `PwObjectTracker.objects`.
- Produces: `AudioService.sinkList` / `sourceList` refreshed on `Pipewire.nodes.valuesChanged`; every sink/source node bound so `.audio.volume` is writable.

- [ ] **Step 1: Track every audio node, not just the defaults**

```qml
property PwObjectTracker tracker: PwObjectTracker {
    objects: root.sinkList.concat(root.sourceList)
}
```

- [ ] **Step 2: Rebuild the lists when the PipeWire graph changes**

```qml
property Connections nodesConn: Connections {
    target: Pipewire.nodes
    function onValuesChanged() { root.updateLists() }
}
```

- [ ] **Step 3: Verify the config loads with no QML errors**

Run: `quickshell -p /home/asergi/dotfiles/quickshell 2>&1 | grep -iE "error|warning|unable" | head`
Expected: no `AudioService` / `valuesChanged` errors.

- [ ] **Step 4: Verify hot-plug**

Run: `pactl load-module module-null-sink sink_name=qs_test`, then `pactl list short sinks | grep qs_test`
Expected: the test sink exists; it must appear in `AudioService.sinkList` while the launcher is open.
Clean up: `pactl unload-module module-null-sink`.

- [ ] **Step 5: Commit**

```bash
git add services/AudioService.qml
git commit -m "feat(audio): track all nodes and refresh on graph changes"
```

---

### Task 2: Audio Center rows, filter, scroll and per-device volume

**Files:**
- Modify: `components/launchers/AudioCenter.qml` (full restructure)

**Interfaces:**
- Consumes: `AudioService.sinkList`, `AudioService.sourceList`, `AudioService.sink`, `AudioService.source`, `AudioService.setDefaultSink(id)`, `AudioService.setDefaultSource(id)`, `AudioService.toggleMute()`, `AudioService.adjustVolume(delta)`.
- Produces: `filteredSinks`, `filteredSources`, `updateModels()`, `moveSel(delta)`, `adjustSel(delta)`, `activate()`, `ensureVisible()`.

- [ ] **Step 1: Add filter state and filtered models**

`root` gains `filterActive`, `suppressUpdate`, `filteredSinks`, `filteredSources`; `close()` clears `filterActive`.

- [ ] **Step 2: Wrap the card content in a Flickable with a ScrollBar**

Copy Network Center's `scrollView` block verbatim (`NetworkCenter.qml:39-53`), with `mainCol.width: scrollView.width`.

- [ ] **Step 3: Add the `/` filter field above the Output section**

`visible: root.filterActive`, `Icons.search`, `TextField` with `onTextChanged: if(!suppressUpdate) updateModels()`, `onAccepted` clears `filterActive` and refocuses `mainCol`.

- [ ] **Step 4: Give sink and source rows the Network focus treatment**

Delegate rectangle: `height: 44`, `radius: Theme.roundingItem`,
`color: isSel ? Theme.bgSelected : (ma.containsMouse ? Theme.bgHover : "transparent")`,
`border.color: isSel ? Theme.borderSelected : "transparent"`, `border.width: 1`.
List `spacing: 4`. Model is `root.filteredSinks` / `root.filteredSources`.

- [ ] **Step 5: Add empty states and the missing Sources header**

`"No output devices"` / `"No input devices"` when the unfiltered list is empty; `"No matching outputs"` / `"No matching sources"` when only the filter is empty.

- [ ] **Step 6: Add `updateModels()` and wire it to filter, lists and open**

Builds `filteredSinks`/`filteredSources` from `AudioService.*List` filtered by `description`/`name`, then `navItems` in order: mute, volMinus, volSlider, volPlus, sinks, micSwitch, micMinus, micSlider, micPlus, sources. Clamp `selIndex`. Call from `onTextChanged`, `onSinkListChanged`, `onSourceListChanged`, `Component.onCompleted`, `onIsOpenChanged`.

- [ ] **Step 7: Per-device `h/l` and `Enter`**

`adjustSel(delta)` adjusts `filteredSinks[idx]`, `filteredSources[idx]` or the default node's `.audio.volume`, clamped to 0–1. `activate()` selects the focused device via `setDefaultSink`/`setDefaultSource`.

- [ ] **Step 8: Keys — `/` opens filter, `Esc` leaves filter before closing**

```qml
else if(e.text==="/") { root.filterActive=true; filterField.forceActiveFocus(); e.accepted=true }
```

`Esc`: `filterActive` → clear and refocus `mainCol`; otherwise `root.close()`.

- [ ] **Step 9: Update the footer hint**

`"j/k · Enter select · h/l volume · / filter · m mute · Esc close"`.

- [ ] **Step 10: Verify the config loads**

Run: `quickshell -p /home/asergi/dotfiles/quickshell 2>&1 | grep -iE "error|warning|unable" | head`
Expected: no `AudioCenter.qml` errors.

- [ ] **Step 11: Verify visually**

Open the launcher, press `j` until a sink row is focused, screenshot the card.
Expected: exactly one row carries the grey outline; the active device keeps its check mark; a second `j` moves the outline, not the check.

- [ ] **Step 12: Commit**

```bash
git add components/launchers/AudioCenter.qml
git commit -m "feat(audio): network-style focused rows, filter and scroll"
```
