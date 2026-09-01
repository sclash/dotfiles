pragma Singleton
import QtQuick
import Quickshell.Io
import Quickshell.Services.Pipewire

QtObject {
    id: root
    property PwNode sink: Pipewire.defaultAudioSink
    property PwNode source: Pipewire.defaultAudioSource
    property bool muted: sink && sink.audio ? sink.audio.muted : false
    property int volume: sink && sink.audio ? Math.round(sink.audio.volume * 100) : 0
    property string sinkName: sink ? (sink.description || sink.name || "") : ""
    property bool hasSink: sink !== null
    property bool hasSource: source !== null
    property bool available: Pipewire.ready || hasSink
    property var sinkList: []
    property var sourceList: []

    function setVolume(v) {
        const s = Pipewire.defaultAudioSink
        if (s && s.audio) s.audio.volume = Math.max(0, Math.min(1, v))
    }
    function adjustVolume(delta) {
        const s = Pipewire.defaultAudioSink
        if (s && s.audio) s.audio.volume = Math.max(0, Math.min(1, s.audio.volume + delta))
    }
    function toggleMute() {
        const s = Pipewire.defaultAudioSink
        if (s && s.audio) s.audio.muted = !s.audio.muted
    }
    function setDefaultSink(id) {
        let target = null
        for (let i = 0; i < sinkList.length; i++) if (sinkList[i].id === id) { target = sinkList[i]; break }
        if (target && Pipewire.preferredDefaultAudioSink !== undefined) {
            Pipewire.preferredDefaultAudioSink = target
        } else {
            root.wpSinkProc.command = ["wpctl", "set-default", String(id)]; root.wpSinkProc.running = true
        }
    }
    function setDefaultSource(id) {
        let target = null
        for (let i = 0; i < sourceList.length; i++) if (sourceList[i].id === id) { target = sourceList[i]; break }
        if (target && Pipewire.preferredDefaultAudioSource !== undefined) {
            Pipewire.preferredDefaultAudioSource = target
        } else {
            root.wpSourceProc.command = ["wpctl", "set-default", String(id)]; root.wpSourceProc.running = true
        }
    }
    function setSourceMuted(m) {
        const s = Pipewire.defaultAudioSource
        if (s && s.audio) s.audio.muted = m
    }

    function updateLists() {
        if (!Pipewire.nodes) return
        let vals = null
        try { vals = Pipewire.nodes.values } catch (e) { vals = null }
        if (!vals) return
        const sinks = []
        const sources = []
        for (let i=0;i<vals.length;i++) {
            const n = vals[i]
            if (!n) continue
            const isSink = n.isSink === true
            const isSource = n.isSource === true
            const isStream = n.isStream === true
            if (isSink && !isStream) sinks.push(n)
            if (isSource && !isStream) sources.push(n)
        }
        root.sinkList = sinks
        root.sourceList = sources
    }

    function parseWpctlVolume(text) {
        // wpctl get-volume prints: "Volume: 0.42" or "Volume: 0.42 [MUTED]"
        const m = text.match(/([0-9]+\.[0-9]+)/)
        if (m) {
            const v = parseFloat(m[1])
            if (!isNaN(v)) root.volume = Math.round(v * 100)
        }
        root.muted = text.indexOf("MUTED") !== -1
    }

    property Process wpSinkProc: Process {
        stdout: StdioCollector { onStreamFinished: Qt.callLater(root.updateLists) }
    }
    property Process wpSourceProc: Process {
        stdout: StdioCollector { onStreamFinished: Qt.callLater(root.updateLists) }
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
    Component.onCompleted: root.updateLists()

    // React to Pipewire changes — no polling when Pipewire is ready
    property Connections pipeConn: Connections {
        target: Pipewire
        function onDefaultAudioSinkChanged() { root.sink = Pipewire.defaultAudioSink; root.source = Pipewire.defaultAudioSource; Qt.callLater(root.updateLists) }
        function onDefaultAudioSourceChanged() { root.source = Pipewire.defaultAudioSource; Qt.callLater(root.updateLists) }
        function onReadyChanged() {
            // At startup sink is null until ready; sync it when PipeWire becomes ready
            root.sink = Pipewire.defaultAudioSink
            root.source = Pipewire.defaultAudioSource
            Qt.callLater(root.updateLists)
            if (Pipewire.ready) {
                // refresh volume/muted from new sink
                if (root.sink && root.sink.audio) {
                    root.muted = root.sink.audio.muted
                    root.volume = Math.round(root.sink.audio.volume * 100)
                }
            }
        }
    }
    // Fallback poll only when PipeWire is NOT ready (e.g. wireplumber not running)
    property Timer fallbackTimer: Timer {
        interval: 2000
        running: !Pipewire.ready
        repeat: true
        onTriggered: if (!Pipewire.ready) root.fallbackPoll.running = true
    }
    // Node hotplug: update lists when nodes change, gated to avoid tight loop
    property Timer pipePoll: Timer {
        interval: 2000
        running: !Pipewire.ready
        repeat: true
        onTriggered: root.updateLists()
    }
    // Keep muted/volume in sync with sink audio signals
    property Connections sinkAudioConn: Connections {
        target: root.sink && root.sink.audio ? root.sink.audio : null
        function onMutedChanged() { if (root.sink && root.sink.audio) root.muted = root.sink.audio.muted }
        function onVolumeChanged() { if (root.sink && root.sink.audio) root.volume = Math.round(root.sink.audio.volume * 100) }
        // Some Quickshell versions emit volumesChanged (plural) for per-channel; handle both
        function onVolumesChanged() { if (root.sink && root.sink.audio) root.volume = Math.round(root.sink.audio.volume * 100) }
    }
}
