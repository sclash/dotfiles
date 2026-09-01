pragma Singleton
import QtQuick
import Quickshell.Io
import Quickshell.Hyprland

QtObject {
    id: root
    property string layoutName: "US"
    property bool available: true

    function cycleLayout() {
        root.kbProc.running = true
        root.switchProc.running = true
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

    property Connections hyprConn: Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event && event.name === "activelayout") root.kbProc.running = true
        }
    }

    property Timer init: Timer { interval: 300; running: true; repeat: false; onTriggered: root.kbProc.running = true }
}
