pragma Singleton
import QtQuick
import Quickshell.Io

QtObject {
    id: root
    property bool expanded: false
    property bool available: true
    property int cpuUsage: 0
    property real cpuLoad: 0.0
    property double memUsedGiB: 0
    property int memPercent: 0
    property int diskUsedGb: 0
    property int diskPercent: 0
    property int tempC: -1

    function toggle() { expanded = !expanded }

    property int _prevIdle: 0
    property int _prevTotal: 0

    property Process pollProc: Process {
        command: ["sh", "-c", "cat /proc/stat | head -n 1; echo '---'; cat /proc/meminfo | head -n 5; echo '---'; cat /proc/loadavg; echo '---'; df -BG / | tail -n 1; echo '---'; bestv=0; found=0; for z in /sys/class/thermal/thermal_zone*; do t=$(cat \"$z/type\" 2>/dev/null); v=$(cat \"$z/temp\" 2>/dev/null); case \"$v\" in \"\"|*[!0-9]*) continue;; esac; if [ \"$t\" = x86_pkg_temp ]; then echo \"$v\"; exit 0; fi; if [ \"$v\" -gt \"$bestv\" ]; then bestv=\"$v\"; found=1; fi; done; if [ \"$found\" = 1 ]; then echo \"$bestv\"; else echo -1; fi"]
        stdout: StdioCollector {
            onStreamFinished: {
                const txt = this.text
                if (!txt) { root.available = false; return }
                const secs = txt.split("---")
                if (secs.length < 5) return
                const statLine = secs[0].trim()
                const memInfo = secs[1] || ""
                const loadLine = secs[2] || ""
                const dfLine = secs[3] || ""
                const tempLine = secs[4] || ""

                const statParts = statLine.split(/\s+/).slice(1).map(v=> parseInt(v)||0)
                const idle = (statParts[3]||0) + (statParts[4]||0)
                const total = statParts.reduce((a,b)=>a+b,0)
                if (root._prevTotal !== 0) {
                    const diffIdle = idle - root._prevIdle
                    const diffTotal = total - root._prevTotal
                    if (diffTotal > 0) root.cpuUsage = Math.round((1 - diffIdle/diffTotal)*100)
                }
                root._prevIdle = idle
                root._prevTotal = total

                root.cpuLoad = parseFloat(loadLine.trim().split(" ")[0]) || 0

                const memTotalMatch = memInfo.match(/MemTotal:\s+(\d+)/)
                const memAvailMatch = memInfo.match(/MemAvailable:\s+(\d+)/)
                if (memTotalMatch && memAvailMatch) {
                    const totalKb = parseInt(memTotalMatch[1])
                    const availKb = parseInt(memAvailMatch[1])
                    const usedKb = totalKb - availKb
                    root.memUsedGiB = Math.round(usedKb / 1024 / 1024 * 10)/10
                    root.memPercent = Math.round(usedKb / totalKb * 100)
                }

                const dfParts = dfLine.trim().split(/\s+/)
                if (dfParts.length >= 5) {
                    const usePct = parseInt(dfParts[4].replace("%","")) || 0
                    root.diskPercent = usePct
                    const usedStr = dfParts[2] || "0G"
                    root.diskUsedGb = parseInt(usedStr.replace("G","")) || 0
                }

                const t = parseInt(tempLine.trim())
                if (!isNaN(t) && t > 0) {
                    root.tempC = t > 1000 ? Math.round(t/1000) : t
                } else root.tempC = -1
            }
        }
    }

    property Timer timer: Timer {
        interval: 2000
        running: root.expanded
        repeat: true
        onTriggered: root.pollProc.running = true
    }

    property Timer initTimer: Timer {
        interval: 100
        running: true
        repeat: false
        onTriggered: root.pollProc.running = true
    }
}
