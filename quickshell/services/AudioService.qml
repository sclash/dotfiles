pragma Singleton
import QtQuick
import Quickshell.Io
import Quickshell.Services.Pipewire

QtObject {
    id: root

    property PwNode sink: Pipewire.defaultAudioSink
    property PwNode source: Pipewire.defaultAudioSource
    property bool muted: false
    property int volume: 0
    property var sinkList: []
    property var sourceList: []

    readonly property bool hasSink: sink !== null
    readonly property bool hasSource: source !== null
    readonly property bool available: Pipewire.ready || hasSink
    readonly property string sinkName: sink ? (sink.nickname || sink.description || sink.name || "") : ""
    readonly property string sourceName: source ? (source.nickname || source.description || source.name || "") : ""

    // 0.3.0: pipewire objects are unbound by default. PwObjectTracker binds the
    // defaults so that sink.audio.muted / sink.audio.volume are live and writable.
    property PwObjectTracker tracker: PwObjectTracker {
        objects: [root.sink, root.source]
    }

    Component.onCompleted: refresh()

    property Connections pipeConn: Connections {
        target: Pipewire
        function onReadyChanged() { root.refresh() }
        function onDefaultAudioSinkChanged() { root.refresh() }
        function onDefaultAudioSourceChanged() { root.refresh() }
    }

    property Connections sinkConn: Connections {
        target: null
        function onReadyChanged() { root.syncValues() }
    }

    property Connections audioConn: Connections {
        target: null
        function onMutedChanged() { root.muted = target.muted }
        function onVolumesChanged() { root.volume = Math.round(target.volume * 100) }
    }

    function refresh() {
        sinkConn.target = root.sink
        audioConn.target = (root.sink && root.sink.audio) ? root.sink.audio : null
        syncValues()
        updateLists()
    }

    function syncValues() {
        if (root.sink && root.sink.audio) {
            root.muted = root.sink.audio.muted
            root.volume = Math.round(root.sink.audio.volume * 100)
        } else {
            root.muted = false
            root.volume = 0
        }
    }

    function setVolume(v) {
        const s = root.sink
        if (s && s.audio) s.audio.volume = Math.max(0, Math.min(1, v))
    }
    function adjustVolume(delta) {
        const s = root.sink
        if (s && s.audio) s.audio.volume = Math.max(0, Math.min(1, s.audio.volume + delta))
    }
    function toggleMute() {
        const s = root.sink
        if (s && s.audio) s.audio.muted = !s.audio.muted
    }
    function setSourceMuted(m) {
        const s = root.source
        if (s && s.audio) s.audio.muted = m
    }

    function findById(list, id) {
        for (let i = 0; i < list.length; i++) if (list[i].id === id) return list[i]
        return null
    }
    function setDefaultSink(id) {
        const n = findById(root.sinkList, id)
        if (n) Pipewire.preferredDefaultAudioSink = n
    }
    function setDefaultSource(id) {
        const n = findById(root.sourceList, id)
        if (n) Pipewire.preferredDefaultAudioSource = n
    }

    function updateLists() {
        if (!Pipewire.ready) return
        const sinks = []
        const sources = []
        const values = Pipewire.nodes ? Pipewire.nodes.values : []
        for (let i = 0; i < values.length; i++) {
            const n = values[i]
            if (!n || !n.audio) continue
            if (n.isSink && !n.isStream) sinks.push(n)
            else if (!n.isSink && !n.isStream) sources.push(n)
        }
        root.sinkList = sinks
        root.sourceList = sources
    }

    // Degraded fallback — polls wpctl only while PipeWire itself is not ready (spec §6)
    function parseWpctlVolume(text) {
        const m = text.match(/([0-9]+\.[0-9]+)/)
        if (m) {
            const v = parseFloat(m[1])
            if (!isNaN(v)) root.volume = Math.round(v * 100)
        }
        root.muted = text.indexOf("MUTED") !== -1
    }

    property Process fallbackPoll: Process {
        command: ["sh", "-c", "wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null || echo \"no-pipewire\""]
        stdout: StdioCollector {
            onStreamFinished: {
                const txt = this.text.trim()
                if (txt && txt !== "no-pipewire") root.parseWpctlVolume(txt)
            }
        }
    }
    property Timer fallbackTimer: Timer {
        interval: 2000
        running: !Pipewire.ready
        repeat: true
        onTriggered: if (!Pipewire.ready) root.fallbackPoll.running = true
    }
}