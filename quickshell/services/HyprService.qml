pragma Singleton
import QtQuick
import Quickshell.Io
import Quickshell.Hyprland

QtObject {
    id: root
    property string layoutName: "US"
    property bool available: true
    property var monitors: []
    property var allMonitors: []
    property var availableMonitors: []

    function isBuiltinName(name) {
        const n = String(name || "")
        return n.indexOf("eDP") === 0 || n.indexOf("DSI") === 0
    }
    readonly property string refMonitorName: {
        const b = root.allMonitors.find(m => root.isBuiltinName(m.name))
        if (b) return b.name
        const ba = root.monitors.find(m => root.isBuiltinName(m.name))
        if (ba) return ba.name
        return root.monitors.length > 0 ? root.monitors[0].name : ""
    }
    readonly property bool externalAvailable: allMonitors.some(m => m.name !== refMonitorName)
    readonly property bool externalConnected: monitors.some(m => m.name !== refMonitorName)

    function cycleLayout() {
        root.kbProc.running = true
        root.switchProc.running = true
    }
    function refreshMonitors() {
        root.monProc.running = true
    }

    property Process kbProc: Process {
        command: ["sh", "-c", "hyprctl devices -j 2>/dev/null | python3 -c \"import json,sys; d=json.load(sys.stdin); kbs=d.get('keyboards',[]); k=next((k for k in kbs if k.get('main')), kbs[0] if kbs else None); print(k.get('active_keymap','US') if k else 'US')\" 2>/dev/null || echo US"]
        stdout: StdioCollector {
            onStreamFinished: {
                const txt = this.text ? this.text.trim() : "US"
                if (txt.toLowerCase().indexOf("italian") !== -1 || txt.toLowerCase().indexOf("it") === 0) root.layoutName = "IT"
                else root.layoutName = "US"
            }
        }
    }
    property Process switchProc: Process {
        command: ["hyprctl", "switchxkblayout", "at-translated-set-2-keyboard", "next"]
        stdout: StdioCollector { onStreamFinished: root.kbProc.running = true }
    }

    property Process monProc: Process {
        command: ["sh", "-c", "hyprctl monitors -j; printf '\\n---SPLIT---\\n'; hyprctl monitors all -j 2>/dev/null || hyprctl monitors -j"]
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = String(this.text || "").split("---SPLIT---")
                try {
                    const active = JSON.parse(parts[0])
                    root.monitors = active.map(m => ({ name: m.name, mode: (m.width + "x" + m.height + "@" + m.refreshRate), scale: m.scale, pos: m.x + "x" + m.y, focused: m.focused }))
                } catch (err) { root.monitors = [] }
                try {
                    const all = JSON.parse(parts[1])
                    root.allMonitors = all.map(m => ({ name: m.name, mode: m.width ? (m.width + "x" + m.height) : "preferred" }))
                    const names = root.monitors.map(m => m.name)
                    root.availableMonitors = all
                        .filter(m => names.indexOf(m.name) === -1 || m.disabled)
                        .map(m => ({ name: m.name, mode: m.width ? (m.width + "x" + m.height) : "preferred" }))
                } catch (err) { root.allMonitors = []; root.availableMonitors = [] }
            }
        }
    }

    property Connections hyprConn: Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event && event.name === "activelayout") root.kbProc.running = true
            else if (event && (event.name.indexOf("monitor") === 0 || event.name === "configreloaded")) root.monitorDebounce.restart()
        }
    }

    property Timer monitorDebounce: Timer { interval: 300; onTriggered: root.refreshMonitors() }
    property Timer init: Timer { interval: 300; running: true; repeat: false; onTriggered: { root.kbProc.running = true; root.refreshMonitors() } }
}
