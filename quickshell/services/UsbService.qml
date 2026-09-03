pragma Singleton
import QtQuick
import Quickshell.Io

QtObject {
    id: root

    property bool udisksAvailable: false
    property bool lsusbAvailable: false
    readonly property bool available: udisksAvailable && lsusbAvailable
    // Mountable leaves folded under their USB disk (LUKS children flattened)
    property var storage: []
    // Every USB device reported by lsusb
    property var allDevices: []
    property string lastError: ""
    property string busyNode: ""   // visible row currently acted upon
    property string busyOp: ""     // mount | unmount | poweroff | unlock
    property var cmdQueue: []      // pending udisksctl operations
    property var currentCmd: null  // operation currently running
    property bool monitoring: true
    signal dataUpdated()

    property var _leafRows: []
    property var _diskVids: ({})
    property string _rawLsusb: ""
    property string _pendingAutoMount: ""   // partition name awaiting auto-mount after unlock

    // refresh() re-probes tool availability too — binaries may appear after the
    // shell started (e.g. a rebuild landing mid-session).
    function refresh() {
        root.availabilityProc.running = true
        root.refreshData()
    }
    function refreshData() {
        root.blkProc.running = true
        root.vidsProc.running = true
        root.lsusbProc.running = true
    }

    function reportError(txt) {
        const t = (txt || "").trim()
        if (!t) return
        const line = t.split("\n").filter(l => l.indexOf("Error") !== -1)[0] || t.split("\n")[0]
        if (line) { root.lastError = line; root.dataUpdated() }
    }

    // ---------- mutations (serialized through the udisksctl queue) ----------

    function mount(node) {
        root.enqueue({ op: "mount", node: node, args: ["sh", "-c", "udisksctl mount -b '" + node + "' 2>&1"] })
    }
    function unmount(node) {
        root.enqueue({ op: "unmount", node: node, args: ["sh", "-c", "udisksctl unmount -b '" + node + "' 2>&1"] })
    }
    // Safe removal: unmount every mounted child first, then power off the disk.
    // Any failed step is critical and aborts the remaining chain.
    function powerOff(diskNode) {
        const rows = root.storage.filter(r => r.diskNode === diskNode && r.mountPoint)
        for (const r of rows)
            root.enqueue({ op: "unmount", node: r.node, critical: true, args: ["sh", "-c", "udisksctl unmount -b '" + r.node + "' 2>&1"] })
        root.enqueue({ op: "poweroff", node: diskNode, critical: true, args: ["sh", "-c", "udisksctl power-off -b '" + diskNode + "' 2>&1"] })
    }
    function unlock(node, passphrase) {
        // Passphrase travels via the environment — never interpolated into shell text.
        root.enqueue({
            op: "unlock", node: node,
            env: { USB_PASS: passphrase || "", USB_NODE: node },
            args: ["sh", "-c", "printf %s \"$USB_PASS\" | udisksctl unlock -b \"$USB_NODE\" --key-file=- 2>&1"]
        })
    }
    function openInFileManager(path) {
        root.fmProc.command = ["nautilus", path]
        root.fmProc.running = true
    }

    function enqueue(cmd) {
        root.cmdQueue = root.cmdQueue.concat([cmd])
        if (!root.currentCmd) root.runNext()
    }
    function runNext() {
        if (root.currentCmd) return
        if (root.cmdQueue.length === 0) {
            root.busyNode = ""; root.busyOp = ""; root.dataUpdated(); return
        }
        const c = root.cmdQueue[0]
        root.cmdQueue = root.cmdQueue.slice(1)
        root.currentCmd = c
        root.busyNode = c.node || ""
        root.busyOp = c.op || ""
        root.dataUpdated()
        root.actionProc.environment = c.env || ({})
        root.actionProc.command = c.args
        root.actionProc.running = true
    }
    // udisksctl is quiet on success ("Mounted …" / "Unlocked …") and prefixes
    // failures with "Error …" on the merged stream — stderr is folded in via 2>&1.
    function finishAction(text) {
        const c = root.currentCmd
        root.currentCmd = null
        const out = (text || "").trim()
        const failed = out.indexOf("Error") !== -1
        if (failed) {
            root.lastError = out.split("\n")[0]
            if (c && c.critical) root.cmdQueue = []
            if (c && c.op === "unlock") root._pendingAutoMount = ""
        } else {
            root.lastError = ""
            if (c && c.op === "unlock") root._pendingAutoMount = String(c.node).replace(/^\/dev\//, "")
        }
        root.refresh()
        root.runNext()
    }

    // ---------- parsing ----------

    function collectLeaf(node, disk, partName, enc, rows) {
        const isLuks = node.fstype === "crypto_LUKS"
        const encrypted = enc || isLuks
        const kids = node.children || []
        if (kids.length === 0) rows.push(root.makeLeaf(node, disk, partName, encrypted))
        else for (const k of kids) root.collectLeaf(k, disk, partName, encrypted, rows)
    }
    function makeLeaf(node, disk, partName, encrypted) {
        return {
            node: node.path || ("/dev/" + node.name),
            diskNode: disk.path || ("/dev/" + disk.name),
            diskName: disk.name || "",
            partName: partName || node.name || "",
            label: node.label || disk.label || node.name || "",
            size: node.size || "",
            fstype: node.fstype || "",
            mountPoint: node.mountpoint || null,
            encrypted: encrypted,
            locked: encrypted && node.fstype === "crypto_LUKS",
            vid: "", pid: ""
        }
    }
    function rebuild() {
        const vidMap = root._diskVids
        const rows = (root._leafRows || []).map(r => {
            const copy = Object.assign({}, r)
            const vp = vidMap[r.diskName]
            if (vp) { copy.vid = vp.vid; copy.pid = vp.pid }
            return copy
        })
        root.storage = rows
        // Auto-mount the freshly unlocked LUKS leaf once it shows up in lsblk.
        if (root._pendingAutoMount) {
            const t = root._pendingAutoMount
            const candidates = rows.filter(r => r.partName === t)
            if (candidates.length === 0) root._pendingAutoMount = ""
            else {
                const target = candidates.find(r => !r.mountPoint)
                if (target) { root._pendingAutoMount = ""; root.mount(target.node) }
            }
        }
        const sKeys = {}
        for (const r of rows) if (r.vid && r.pid) sKeys[r.vid + ":" + r.pid] = true
        const devs = []
        const lines = (root._rawLsusb || "").trim().split("\n").filter(Boolean)
        for (const l of lines) {
            const m = l.match(/^Bus (\d+) Device (\d+): ID ([0-9a-fA-F]{4}):([0-9a-fA-F]{4}) ?(.*)$/)
            if (!m) continue
            devs.push({
                bus: m[1], dev: m[2],
                vid: m[3].toLowerCase(), pid: m[4].toLowerCase(),
                name: (m[5] || "").trim() || "Unknown device",
                isStorage: false
            })
        }
        for (const d of devs)
            d.isStorage = !!sKeys[d.vid + ":" + d.pid] || /mass storage|sata bridge/i.test(d.name)
        root.allDevices = devs
        root.dataUpdated()
    }

    // ---------- processes (one per probe / subsystem) ----------

    property Process availabilityProc: Process {
        command: ["sh", "-c", "command -v udisksctl >/dev/null 2>&1 && echo UDISKS_OK; command -v lsusb >/dev/null 2>&1 && echo LSUSB_OK"]
        stdout: StdioCollector {
            onStreamFinished: {
                const t = this.text
                root.udisksAvailable = t.indexOf("UDISKS_OK") !== -1
                root.lsusbAvailable = t.indexOf("LSUSB_OK") !== -1
                root.refreshData()
            }
        }
    }

    property Process blkProc: Process {
        command: ["lsblk", "-J", "-o", "NAME,PATH,LABEL,FSTYPE,SIZE,MOUNTPOINT,TRAN"]
        stdout: StdioCollector {
            onStreamFinished: {
                const txt = this.text
                if (!txt || txt.trim().length === 0) { root._leafRows = []; root.rebuild(); return }
                try {
                    const json = JSON.parse(txt)
                    const rows = []
                    for (const d of (json.blockdevices || [])) {
                        if (d.tran !== "usb") continue
                        if (d.children && d.children.length > 0)
                            for (const c of d.children) root.collectLeaf(c, d, c.name, false, rows)
                        else if (d.fstype)
                            rows.push(root.makeLeaf(d, d, d.name, d.fstype === "crypto_LUKS"))
                    }
                    root._leafRows = rows
                    root.rebuild()
                } catch (err) {
                    root.reportError("lsblk parse failed: " + err)
                }
            }
        }
    }

    // Disk vid:pid via udev properties — links lsblk disks to their lsusb entries.
    property Process vidsProc: Process {
        command: ["sh", "-c", "for d in $(lsblk -dno NAME,TRAN 2>/dev/null | awk '$2==\"usb\"{print $1}'); do udevadm info -q property -n /dev/$d 2>/dev/null | awk -v d=$d '/^ID_VENDOR_ID=/{v=substr($0,14)} /^ID_MODEL_ID=/{m=substr($0,13)} END{if(v!=\"\")print d, v\":\"m}'; done"]
        stdout: StdioCollector {
            onStreamFinished: {
                const map = {}
                const lines = this.text.trim().split("\n").filter(Boolean)
                for (const l of lines) {
                    const parts = l.trim().split(/\s+/)
                    if (parts.length >= 2 && parts[1].indexOf(":") !== -1) {
                        const vp = parts[1].split(":")
                        map[parts[0]] = { vid: vp[0] || "", pid: vp[1] || "" }
                    }
                }
                root._diskVids = map
                root.rebuild()
            }
        }
    }

    property Process lsusbProc: Process {
        command: ["lsusb"]
        stdout: StdioCollector { onStreamFinished: { root._rawLsusb = this.text; root.rebuild() } }
    }

    property Process actionProc: Process {
        stdout: StdioCollector { onStreamFinished: root.finishAction(this.text) }
    }

    property Process fmProc: Process { command: ["true"] }

    // Plug/unplug/mount events — debounced into a single refresh per burst,
    // no polling (SPECS.md §2.3 rule 1).
    property Process monitorProc: Process {
        running: true
        command: ["udevadm", "monitor", "--udev", "--subsystem-match=usb", "--subsystem-match=block"]
        stdout: SplitParser { onRead: root.monitorDebounce.restart() }
    }
    property Timer monitorDebounce: Timer { interval: 300; onTriggered: root.refresh() }
    property Timer monitorWatchdog: Timer {
        interval: 5000; running: true; repeat: true
        onTriggered: {
            root.monitoring = root.monitorProc.running
            if (!root.monitorProc.running) root.monitorProc.running = true
        }
    }

    Component.onCompleted: root.availabilityProc.running = true
}
