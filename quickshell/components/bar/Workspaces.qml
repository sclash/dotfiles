pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import "../../services"
import "../../theme"

// Left-pill workspace row. Workspaces are grouped per monitor — ordered by
// physical position — each group prefixed with a monitor glyph + name label
// and separated by a thin divider. Groups on monitors other than the bar's
// own screen render dimmed, so it is obvious at a glance where a workspace
// lives. With a single monitor the labels/dividers stay hidden (no clutter).
RowLayout {
    id: root
    spacing: Theme.gapS

    // Wayland output name of the screen this bar instance lives on (e.g.
    // "eDP-1"). Empty means "unknown" → every group renders at full strength.
    property string screenName: ""

    // With more than one monitor the dot glyph carries no identity, so each
    // slot shows its numeric workspace id instead (single monitor keeps dots).
    readonly property bool numbered: groups.length > 1

    function isOnScreen(name) {
        return root.screenName === "" || name === root.screenName
    }

    function workspaceFor(id) {
        const model = Hyprland.workspaces
        if (!model) return null
        const list = model.values
        for (let i = 0; i < list.length; i++)
            if (list[i].id === id) return list[i]
        return null
    }

    // Windows on workspace <id>, straight from the Hyprland IPC toplevel model.
    // Event-driven (openwindow/closewindow/movewindowv2) — no polling.
    function toplevelsFor(id) {
        const list = []
        if (!Hyprland.toplevels) return list
        for (let i = 0; i < Hyprland.toplevels.values.length; i++) {
            const t = Hyprland.toplevels.values[i]
            if (t.workspace && t.workspace.id === id) list.push(t)
        }
        return list
    }

    // One entry per monitor: { name, builtin, description, ids, slots }.
    // `ids` are the real workspace ids on that monitor, `slots` adds synthetic
    // free ids on the focused monitor (>= 3 dots, plus one create-workspace
    // affordance). Recomputes on any workspace/monitor/focus IPC change.
    readonly property var rawGroups: {
        const monList = Hyprland.monitors ? Hyprland.monitors.values : []
        const allWs = Hyprland.workspaces ? Hyprland.workspaces.values : []
        const wsList = []
        for (const w of allWs) if (w.id > 0) wsList.push(w)

        const order = monList.slice()
            .sort((a, b) => (a.x - b.x) || (a.y - b.y))
            .map((m, i) => ({ name: m.name, builtin: HyprService.isBuiltinName(m.name), description: m.description || "", ids: [], pos: i }))
        const byName = {}
        for (const g of order) byName[g.name] = g

        // Workspaces whose monitor isn't in the monitor list yet (startup race).
        for (const w of wsList) {
            const name = w.monitor ? w.monitor.name : ""
            if (name === "" || byName[name]) continue
            const g = { name: name, builtin: HyprService.isBuiltinName(name), description: "", ids: [], pos: order.length }
            byName[name] = g
            order.push(g)
        }
        // Workspaces Hyprland has not attached to a monitor yet (create/destroy
        // race: they land in the workspace list before their monitor is
        // reported). Keep their ids — they are parked on the focused monitor
        // below. Dropping them instead would shrink the slot row for a frame
        // and shove the rest of the bar sideways.
        const orphaned = []
        for (const w of wsList) {
            const name = w.monitor ? w.monitor.name : ""
            if (name !== "" && byName[name]) byName[name].ids.push(w.id)
            else orphaned.push(w.id)
        }

        // No monitor info at all (Hyprland IPC down): degrade to 3 dim dots.
        if (order.length === 0)
            order.push({ name: root.screenName, builtin: HyprService.isBuiltinName(root.screenName), description: "", ids: [], pos: 0 })

        // Synthetic slots live on the focused monitor — the monitor where
        // `workspace <id>` would create a new workspace.
        const focusedName = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""
        let host = order[0]
        for (const g of order) if (g.name === focusedName) host = g

        // Park monitor-less workspaces on the focused monitor (the one
        // Hyprland just created them on) so the rendered dot count is the same
        // before and after the IPC settles.
        for (const id of orphaned) host.ids.push(id)
        for (const g of order) g.ids.sort((a, b) => a - b)

        // Displays with the lowest workspace number come first so the numerals
        // read ascending across groups; workspace-less monitors fall back to
        // physical position (x, then y).
        order.sort((a, b) => {
            const ka = a.ids.length > 0 ? a.ids[0] : Infinity
            const kb = b.ids.length > 0 ? b.ids[0] : Infinity
            return (ka - kb) || (a.pos - b.pos)
        })

        const used = {}
        for (const w of wsList) used[w.id] = true
        let next = 1
        const take = function() {
            while (next <= 10 && used[next]) next++
            if (next > 10) return 0
            used[next] = true
            return next
        }

        host.slots = host.ids.slice()
        let padded = false
        while (wsList.length + (host.slots.length - host.ids.length) < 3) {
            const id = take()
            if (id === 0) break
            host.slots.push(id)
            padded = true
        }
        // Create-workspace affordance: one free dot on the focused monitor once
        // every real workspace is shown (the padding slot doubles as one when
        // fewer than 3 workspaces exist — matches the previous count rule).
        if (wsList.length > 0 && !padded) {
            const id = take()
            if (id !== 0) host.slots.push(id)
        }
        for (const g of order) {
            if (!g.slots) g.slots = g.ids.slice()
            g.slots.sort((a, b) => a - b)
        }
        return order
    }

    // Published model for the row Repeater. Hyprland reports a workspace create
    // and the previous workspace's destroy as separate events a few milliseconds
    // apart, so `rawGroups` momentarily counts both workspaces at once and the
    // row gains a dot. Rendering that widens the row and shoves the rest of the
    // bar sideways for a frame. A raw value whose row geometry matches what is
    // already published goes out immediately (id/focus updates stay instant);
    // one that would resize the row is held until the burst has settled.
    property var groups: []

    // Row-width signature — what actually pushes the bar's right-hand side
    // around: how many slots each monitor row has, and how many monitor rows
    // there are (labels and dividers appear past the first).
    function rowKey(gs) {
        let k = gs.length + "/"
        for (let i = 0; i < gs.length; i++) k += gs[i].slots.length + ","
        return k
    }

    Timer {
        id: groupsSettle
        interval: 16
        repeat: false
        onTriggered: root.groups = root.rawGroups
    }

    onRawGroupsChanged: {
        const raw = root.rawGroups
        if (root.groups.length === 0 || root.rowKey(raw) === root.rowKey(root.groups)) {
            groupsSettle.stop()
            root.groups = raw
        } else {
            groupsSettle.restart()
        }
    }

    Repeater {
        model: root.groups

        delegate: RowLayout {
            id: monGroup
            required property var modelData
            required property int index
            spacing: Theme.gapS
            opacity: root.isOnScreen(monGroup.modelData.name) ? 1.0 : 0.55
            Behavior on opacity { NumberAnimation { duration: Theme.durationFast } }

            // Divider between monitor groups (only when > 1 monitor is connected).
            Rectangle {
                visible: monGroup.index > 0
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: 1
                implicitHeight: 14
                color: Theme.border
            }

            // Monitor label: built-in (laptop) vs external (monitor) glyph + name.
            Item {
                visible: root.groups.length > 1
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: monLabel.implicitWidth
                implicitHeight: monLabel.implicitHeight

                Text {
                    id: monLabel
                    anchors.fill: parent
                    text: (monGroup.modelData.builtin ? Icons.laptop : Icons.display) + " " + monGroup.modelData.name
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                    color: root.isOnScreen(monGroup.modelData.name) ? Theme.fgMuted : Theme.fgDim
                    verticalAlignment: Text.AlignVCenter
                }
                MouseArea {
                    id: monMA
                    anchors.fill: parent
                    hoverEnabled: true
                }
                BarToolTip {
                    visible: monMA.containsMouse
                    text: {
                        const g = monGroup.modelData
                        const kind = g.builtin ? "Built-in display" : "External display"
                        let t = g.name === "" ? kind : kind + " · " + g.name
                        if (g.description !== "") t += "\n" + g.description
                        return t
                    }
                    anchorItem: monLabel
                }
            }

            Repeater {
                model: monGroup.modelData.slots

                delegate: RowLayout {
                    id: slot
                    required property int modelData
                    property int wsId: slot.modelData
                    property var ws: root.workspaceFor(wsId)
                    property var apps: root.toplevelsFor(wsId)
                    property bool isFocused: slot.ws !== null && slot.ws.focused
                    property bool isActive: slot.ws !== null && slot.ws.active
                    spacing: 2

                    // Workspace slot — dot (single monitor) or number (multi-monitor);
                    // click switches workspace (unchanged).
                    Item {
                        implicitWidth: root.numbered ? 22 : 20
                        implicitHeight: 20
                        Text {
                            id: dot
                            anchors.centerIn: parent
                            text: root.numbered ? String(slot.wsId) : Icons.workspaceDot
                            font.family: Theme.fontFamily
                            font.pixelSize: root.numbered
                                            ? (slot.isFocused ? 13 : 12)
                                            : (slot.isFocused ? 10 : (slot.isActive ? 9 : 8))
                            font.weight: root.numbered && slot.isFocused ? Theme.fontWeightMedium : Theme.fontWeightNormal
                            color: dotMA.containsMouse ? Theme.fgBright
                                   : (slot.isFocused || slot.isActive) ? Theme.fg : Theme.fgDim
                            opacity: slot.ws !== null ? (slot.isFocused ? 1.0 : 0.85) : 0.55
                            Behavior on color { ColorAnimation { duration: Theme.durationFast } }
                        }
                        BarToolTip {
                            visible: dotMA.containsMouse
                            text: "Workspace " + slot.wsId
                                  + (monGroup.modelData.name !== "" ? " · " + monGroup.modelData.name : "")
                                  + (monGroup.modelData.builtin ? "" : " (external)")
                            anchorItem: dot
                        }
                        MouseArea {
                            id: dotMA
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Hyprland.dispatch('hl.dsp.focus({ workspace = ' + slot.wsId + ' })')
                        }
                    }

                    // Per-workspace app tray — up to wsAppIconMax micro icons.
                    Repeater {
                        model: Math.min(slot.apps.length, Theme.wsAppIconMax)

                        delegate: Item {
                            id: iconSlot
                            required property int index
                            property var toplevel: slot.apps[index]
                            // Wayland app_id. XWayland windows expose no wayland
                            // handle, so for those fall back to the WM_CLASS from
                            // the raw Hyprland IPC object (static per window).
                            property string appId: toplevel && toplevel.wayland ? (toplevel.wayland.appId || "") : ""
                            property string wmClass: toplevel && !toplevel.wayland && toplevel.lastIpcObject
                                ? (toplevel.lastIpcObject["class"] || "")
                                : ""
                            // "" when nothing resolves, which reveals the Icons.window
                            // glyph below instead of Quickshell's placeholder tile.
                            property string iconSource: Icons.appIconFor(appId, wmClass)
                            implicitWidth: Theme.wsAppIcon; implicitHeight: Theme.wsAppIcon
                            Layout.alignment: Qt.AlignVCenter

                            Rectangle {
                                anchors.fill: parent
                                radius: Theme.roundingItem
                                color: slotMA.containsMouse ? Theme.bgHover : "transparent"
                                Behavior on color { ColorAnimation { duration: Theme.durationFast } }

                                Image {
                                    id: appIcon
                                    anchors.centerIn: parent
                                    width: Theme.wsAppIconGlyph; height: Theme.wsAppIconGlyph
                                    source: iconSlot.iconSource
                                    smooth: true
                                    asynchronous: true
                                    sourceSize: Qt.size(Theme.wsAppIconGlyph, Theme.wsAppIconGlyph)
                                    visible: source !== "" && status !== Image.Error
                                    opacity: iconSlot.toplevel && iconSlot.toplevel.activated ? 1.0 : 0.55
                                }
                                Text {
                                    anchors.centerIn: parent
                                    visible: !appIcon.visible
                                    text: Icons.window
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.wsAppIconGlyph - 1
                                    color: iconSlot.toplevel && iconSlot.toplevel.activated ? Theme.fg : Theme.fgDim
                                }
                            }

                            BarToolTip {
                                id: slotTip
                                visible: slotMA.containsMouse && !!iconSlot.toplevel
                                text: iconSlot.toplevel && iconSlot.toplevel.title ? iconSlot.toplevel.title : ""
                                anchorItem: iconSlot
                            }

                            MouseArea {
                                id: slotMA
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (iconSlot.toplevel && iconSlot.toplevel.address)
                                        Hyprland.dispatch('hl.dsp.focus({ window = "address:0x' + iconSlot.toplevel.address + '" })')
                                }
                            }
                        }
                    }

                    // Overflow count when more than wsAppIconMax windows on this workspace.
                    Text {
                        visible: slot.apps.length > Theme.wsAppIconMax
                        text: "+" + (slot.apps.length - Theme.wsAppIconMax)
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.fgDim
                        Layout.alignment: Qt.AlignVCenter
                    }
                }
            }
        }
    }
}
