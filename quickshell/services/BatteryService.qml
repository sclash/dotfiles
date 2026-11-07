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
    // Raw readings normalized to µWh / µW. -1 when unreadable.
    // The kernel exposes one of two schemes per battery:
    //   energy: energy_now/energy_full/power_now (already µWh/µW)
    //   charge: charge_now/charge_full/current_now/voltage_now (µAh/µA/µV)
    // Both are normalized here so the rest of the shell sees one shape.
    property double energyNow: -1
    property double energyFull: -1
    property double powerNow: -1
    // Live estimate, minutes. -1 = unknown (plugged, idle draw 0, or no data).
    // Discharging: energyNow / powerNow. Charging: (energyFull - energyNow) / powerNow (time to full).
    property int timeLeftMinutes: -1

    function refresh(): void { poll.running = true }

    property Process poll: Process {
        // One-shot read of the first BAT* supply. Emits every field we might need
        // from both schemes; normalization happens in JS below.
        command: ["sh", "-c", "b=$(ls /sys/class/power_supply/ 2>/dev/null | grep -E '^BAT' | head -n1); if [ -z \"$b\" ]; then echo NONE; else d=/sys/class/power_supply/$b; echo \"$(cat $d/status 2>/dev/null)|$(cat $d/capacity 2>/dev/null)|$(cat $d/energy_now 2>/dev/null)|$(cat $d/energy_full 2>/dev/null)|$(cat $d/power_now 2>/dev/null)|$(cat $d/charge_now 2>/dev/null)|$(cat $d/charge_full 2>/dev/null)|$(cat $d/current_now 2>/dev/null)|$(cat $d/voltage_now 2>/dev/null)|$(cat $d/voltage_min_design 2>/dev/null)|$(cat $d/power 2>/dev/null)\"; fi"]
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
                const num = (s) => { const v = parseFloat((s || "").trim()); return isNaN(v) ? -1 : v }
                // Presence, not sign: some drivers report negative current_now,
                // so "-1" must stay reserved for "node missing/unreadable".
                const has = (s) => (s || "").trim() !== ""
                const parts = txt.split("|")
                const status = (parts[0] || "").trim()
                const cap = parseInt((parts[1] || "").trim(), 10)

                // Energy-based scheme (µWh / µW) — preferred when present.
                let eNow = has(parts[2]) ? num(parts[2]) : -1
                let eFull = has(parts[3]) ? num(parts[3]) : -1
                let pNow = has(parts[4]) ? Math.abs(num(parts[4])) : -1
                // Charge-based scheme (µAh / µA / µV).
                const cNow = num(parts[5])
                const cFull = num(parts[6])
                const iNow = num(parts[7])
                const vNow = num(parts[8])
                const vMin = num(parts[9])
                const power = num(parts[10])

                // Prefer the live voltage; fall back to the design voltage (V).
                const volt = vNow > 0 ? vNow / 1000000 : (vMin > 0 ? vMin / 1000000 : -1)

                // Normalize charge scheme → energy scheme (consumers read µWh/µW):
                //   energy[µWh] = charge[µAh] * voltage[V]
                //   power[µW]   = current[µA] * voltage[V]
                if (eNow < 0 && has(parts[5]) && volt > 0) eNow = cNow * volt
                if (eFull < 0 && has(parts[6]) && volt > 0) eFull = cFull * volt
                // power_now wins; then current*voltage; then the `power` node.
                // Magnitude only — direction is carried by `status` (the sign
                // convention of these nodes differs per driver).
                if (pNow < 0 && has(parts[7]) && volt > 0) pNow = Math.abs(iNow) * volt
                if (pNow < 0 && has(parts[10])) pNow = Math.abs(power)

                root.capacity = isNaN(cap) ? -1 : Math.max(0, Math.min(100, cap))
                root.energyNow = eNow
                root.energyFull = eFull
                root.powerNow = pNow
                root.charging = status === "Charging"
                root.plugged = status === "Full" || status === "Not charging"
                root.discharging = status === "Discharging"
                root.available = true
                // Live estimate — only when unplugged and actually drawing power,
                // or charging towards full. Power draw of 0 (idle on AC, or
                // sysfs without current/power data) means unknown, not infinite.
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
