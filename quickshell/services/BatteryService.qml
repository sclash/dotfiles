pragma Singleton
import QtQuick
import Quickshell.Io

QtObject {
    id: root
    property bool available: false
    property bool charging: false
    property bool plugged: false
    property bool discharging: false
    property int capacity: -1
    // Raw sysfs readings (µWh / µW). -1 when unreadable.
    property double energyNow: -1
    property double energyFull: -1
    property double powerNow: -1
    // Live estimate, minutes. -1 = unknown (plugged, idle draw 0, or no data).
    // Discharging: energyNow / powerNow. Charging: (energyFull - energyNow) / powerNow (time to full).
    property int timeLeftMinutes: -1

    function refresh(): void { poll.running = true }

    property Process poll: Process {
        command: ["sh", "-c", "b=$(ls /sys/class/power_supply/ 2>/dev/null | grep -E '^BAT' | head -n1); if [ -z \"$b\" ]; then echo NONE; else echo \"$(cat /sys/class/power_supply/$b/status 2>/dev/null)|$(cat /sys/class/power_supply/$b/capacity 2>/dev/null)|$(cat /sys/class/power_supply/$b/energy_now 2>/dev/null)|$(cat /sys/class/power_supply/$b/energy_full 2>/dev/null)|$(cat /sys/class/power_supply/$b/power_now 2>/dev/null)\"; fi"]
        stdout: StdioCollector {
            onStreamFinished: {
                const txt = String(this.text).trim()
                if (!txt || txt === "NONE") {
                    root.available = false
                    root.charging = false
                    root.plugged = false
                    root.discharging = false
                    root.capacity = -1
                    root.energyNow = -1
                    root.energyFull = -1
                    root.powerNow = -1
                    root.timeLeftMinutes = -1
                    return
                }
                const parts = txt.split("|")
                const status = (parts[0] || "").trim()
                const cap = parseInt((parts[1] || "").trim(), 10)
                const eNow = parseFloat((parts[2] || "").trim())
                const eFull = parseFloat((parts[3] || "").trim())
                const pNow = parseFloat((parts[4] || "").trim())
                root.capacity = isNaN(cap) ? -1 : Math.max(0, Math.min(100, cap))
                root.energyNow = isNaN(eNow) ? -1 : eNow
                root.energyFull = isNaN(eFull) ? -1 : eFull
                root.powerNow = isNaN(pNow) ? -1 : pNow
                root.charging = status === "Charging"
                root.plugged = status === "Full" || status === "Not charging"
                root.discharging = status === "Discharging"
                root.available = true
                // Live estimate — only when unplugged and actually drawing power,
                // or charging towards full. Power draw of 0 (idle on AC, or
                // sysfs without power_now) means unknown, not infinite.
                let mins = -1
                if (root.discharging && root.energyNow > 0 && root.powerNow > 0) {
                    mins = Math.round(root.energyNow / root.powerNow * 60)
                } else if (root.charging && root.powerNow > 0 && root.energyFull > root.energyNow) {
                    mins = Math.round((root.energyFull - root.energyNow) / root.powerNow * 60)
                }
                root.timeLeftMinutes = mins
            }
        }
    }

    property Timer timer: Timer {
        interval: 15000
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
