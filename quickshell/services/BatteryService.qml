pragma Singleton
import QtQuick
import Quickshell.Io

QtObject {
    id: root
    property bool available: false
    property bool charging: false
    property bool plugged: false
    property int capacity: -1

    property Process poll: Process {
        command: ["sh", "-c", "b=$(ls /sys/class/power_supply/ 2>/dev/null | grep -E '^BAT' | head -n1); if [ -z \"$b\" ]; then echo NONE; else echo \"$(cat /sys/class/power_supply/$b/status 2>/dev/null) $(cat /sys/class/power_supply/$b/capacity 2>/dev/null)\"; fi"]
        stdout: StdioCollector {
            onStreamFinished: {
                const txt = String(this.text).trim()
                if (!txt || txt === "NONE") {
                    root.available = false
                    root.charging = false
                    root.plugged = false
                    root.capacity = -1
                    return
                }
                const parts = txt.split(/\s+/)
                if (parts.length < 2) return
                const cap = parseInt(parts[parts.length - 1], 10)
                root.capacity = isNaN(cap) ? -1 : Math.max(0, Math.min(100, cap))
                root.charging = parts[0] === "Charging"
                root.plugged = parts[0] === "Not" || parts[0] === "Full"
                root.available = true
            }
        }
    }

    property Timer timer: Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: root.poll.running = true
    }

    property Timer initTimer: Timer {
        interval: 100
        running: true
        repeat: false
        onTriggered: root.poll.running = true
    }
}