import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../../theme"
import "../../services"

WlrLayershell {
    id: root
    property bool isOpen: false
    property var navItems: []
    property int selIndex: 0
    function open(){ isOpen=true }
    function close(){ isOpen=false }
    function toggle(){ if(isOpen) close(); else open() }

    anchors { top:true; bottom:true; left:true; right:true }
    onIsOpenChanged: if(isOpen) { selIndex=0; transientError=""; updateNav(); refresh(); Qt.callLater(()=> mainCol.forceActiveFocus()) }
    color: "transparent"
    visible: isOpen
    keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore
    Rectangle { anchors.fill: parent; color: Theme.overlay; MouseArea { anchors.fill: parent; onClicked: root.close() } }

    Rectangle {
        width: 640
        height: Math.min(640, mainCol.implicitHeight + Theme.padL*2)
        anchors.centerIn: parent
        radius: Theme.roundingLauncher
        color: Theme.bgLauncher
        border.width: 1
        border.color: Theme.borderActive
        ColumnLayout {
            id: mainCol
            anchors.fill: parent
            anchors.margins: Theme.padL
            spacing: Theme.gapM
            focus: true
            Text { text: "Display"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fgMuted; font.capitalization: Font.AllUppercase; font.letterSpacing: 1.2 }
            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border }

            Text { text: "Current"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fgMuted }
            ListView {
                id: currentList
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(236, contentHeight)
                clip: true
                spacing: 4
                model: monitors
                delegate: Rectangle {
                    id: monitorRow
                    required property var modelData
                    required property int index
                    readonly property int monIdx: index
                    readonly property var monRelation: root.monitorRelation(monIdx)
                    width: parent.width
                    height: 56
                    radius: Theme.roundingItem
                    readonly property bool isSel: { const it = root.navItems[root.selIndex]; return it !== undefined && it.kind === "monitor" && it.idx === index }
                    color: modelData.focused ? Theme.bgSelected : Theme.bgActive
                    border.color: isSel ? Theme.accent : (modelData.focused ? Theme.borderSelected : Theme.border)
                    border.width: isSel ? 2 : (modelData.focused ? 2 : 1)
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.padM
                        anchors.rightMargin: Theme.padM
                        spacing: Theme.gapM
                        Rectangle {
                            Layout.alignment: Qt.AlignVCenter
                            width: 36; height: 36
                            radius: 8
                            color: modelData.focused ? Theme.bgSelected : Theme.bgBar
                            Text { anchors.centerIn: parent; text: Icons.display; font.family: Theme.fontFamily; font.pixelSize: 16; color: modelData.focused ? Theme.fg : Theme.fgMuted }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.maximumWidth: Number.POSITIVE_INFINITY
                            Layout.alignment: Qt.AlignVCenter
                            Text { text: modelData.name + (modelData.focused ? " · focused" : ""); font.family: Theme.fontFamily; font.pixelSize: 13; font.weight: Theme.fontWeightMedium; color: Theme.fg; elide: Text.ElideRight; Layout.fillWidth: true }
                            Text { text: modelData.mode + " · scale " + modelData.scale + " · " + modelData.pos; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fgMuted; elide: Text.ElideRight; Layout.fillWidth: true }
                        }
                        ColumnLayout {
                            visible: root.monitors.length >= 2
                            Layout.alignment: Qt.AlignVCenter
                            spacing: 2
                            RowLayout {
                                Layout.alignment: Qt.AlignHCenter
                                spacing: Theme.gapS
                                Repeater {
                                    model: [{ dir: "left", label: "L" }, { dir: "right", label: "R" }, { dir: "top", label: "T" }, { dir: "bottom", label: "B" }]
                                    delegate: Rectangle {
                                        required property var modelData
                                        readonly property bool activeDir: monitorRow.monRelation !== null && monitorRow.monRelation.dir === modelData.dir
                                        width: 26; height: 26
                                        radius: Theme.roundingItem
                                        color: activeDir ? Theme.accent : (dirMouse.containsMouse ? Theme.bgHover : Theme.bgActive)
                                        border.color: activeDir ? Theme.accent : Theme.border
                                        border.width: 1
                                        Text { anchors.centerIn: parent; text: modelData.label; font.family: Theme.fontFamily; font.pixelSize: 10; font.weight: activeDir ? Theme.fontWeightMedium : Theme.fontWeightNormal; color: activeDir ? Theme.bgBar : Theme.fgMuted }
                                        MouseArea { id: dirMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.placeMonitor(monitorRow.monIdx, modelData.dir) }
                                    }
                                }
                            }
                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: monitorRow.monRelation !== null ? monitorRow.monRelation.dir + " of " + monitorRow.monRelation.name : modelData.pos
                                font.family: Theme.fontFamily
                                font.pixelSize: 9
                                color: monitorRow.monRelation !== null ? Theme.fgMuted : Theme.fgDim
                            }
                        }
                        Rectangle {
                            readonly property bool mirrored: root.mirrorName(modelData) !== ""
                            Layout.alignment: Qt.AlignVCenter
                            width: 72; height: 30
                            radius: Theme.roundingItem
                            color: Theme.bgBar
                            border.color: mirrored ? Theme.borderSelected : Theme.border
                            border.width: 1
                            Text { anchors.centerIn: parent; text: parent.mirrored ? "Extend" : "Duplicate"; font.family: Theme.fontFamily; font.pixelSize: 11; color: parent.mirrored ? Theme.fg : Theme.fgMuted }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.toggleMirror(index) }
                        }
                        Rectangle {
                            readonly property bool canDisconnect: root.monitors.length >= 2
                            Layout.alignment: Qt.AlignVCenter
                            width: 90; height: 30
                            radius: Theme.roundingItem
                            color: Theme.bgBar
                            border.color: canDisconnect ? Theme.critical : Theme.border
                            border.width: 1
                            Text { anchors.centerIn: parent; text: "Disconnect"; font.family: Theme.fontFamily; font.pixelSize: 11; color: parent.canDisconnect ? Theme.critical : Theme.fgDim }
                            MouseArea { anchors.fill: parent; cursorShape: parent.canDisconnect ? Qt.PointingHandCursor : Qt.ArrowCursor; onClicked: root.disconnectIndex(index) }
                        }
                    }
                }
            }

            Text { text: "Available"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fgMuted }
            ListView {
                id: availableList
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(140, contentHeight)
                clip: true
                spacing: 4
                model: availableMonitors
                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    width: parent.width
                    height: 52
                    radius: Theme.roundingItem
                    readonly property bool rowSel: { const it = root.navItems[root.selIndex]; return it !== undefined && it.kind === "available" && it.idx === index }
                    readonly property string selMode: { const it = root.navItems[root.selIndex]; return (it !== undefined && it.kind === "available" && it.idx === index) ? it.mode : "" }
                    color: rowSel ? Theme.bgActive : Theme.bgHover
                    border.color: rowSel ? Theme.accent : Theme.border
                    border.width: rowSel ? 2 : 1
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.padM
                        anchors.rightMargin: Theme.padM
                        spacing: Theme.gapM
                        Text { text: modelData.name; font.family: Theme.fontFamily; font.pixelSize: 13; color: Theme.fg; font.weight: Theme.fontWeightMedium; Layout.alignment: Qt.AlignVCenter }
                        Text { text: modelData.mode; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fgMuted; Layout.fillWidth: true; Layout.maximumWidth: Number.POSITIVE_INFINITY; elide: Text.ElideRight; Layout.alignment: Qt.AlignVCenter }
                        Rectangle {
                            Layout.alignment: Qt.AlignVCenter
                            width: 70; height: 28
                            radius: Theme.roundingItem
                            color: Theme.bgActive
                            border.color: selMode === "extend" ? Theme.accent : Theme.borderActive
                            border.width: selMode === "extend" ? 2 : 1
                            Text { anchors.centerIn: parent; text: "Extend"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fg }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.connectProc("extend", modelData.name) }
                        }
                        Rectangle {
                            Layout.alignment: Qt.AlignVCenter
                            width: 80; height: 28
                            radius: Theme.roundingItem
                            color: Theme.bgActive
                            border.color: selMode === "duplicate" ? Theme.accent : Theme.borderActive
                            border.width: selMode === "duplicate" ? 2 : 1
                            Text { anchors.centerIn: parent; text: "Duplicate"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fg }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.connectProc("duplicate", modelData.name) }
                        }
                    }
                }
            }
            Text { visible: availableMonitors.length===0; text: "No additional outputs detected"; font.family: Theme.fontFamily; font.pixelSize: 12; color: Theme.fgDim; Layout.alignment: Qt.AlignHCenter }

            Text { id: errorText; visible: text.length>0; text: root.transientError.length>0 ? root.transientError : root.hyprError; color: Theme.critical; font.family: Theme.fontFamily; font.pixelSize: 11 }
            RowLayout {
                Layout.fillWidth: true
                Rectangle {
                    id: refreshBtn
                    width: 100; height: 32
                    radius: Theme.roundingItem
                    readonly property bool isSel: root.navItems[root.selIndex] !== undefined && root.navItems[root.selIndex].kind === "refresh"
                    color: isSel ? Theme.bgActive : Theme.bgHover
                    border.color: isSel ? Theme.accent : Theme.border
                    border.width: isSel ? 2 : 1
                    Text { anchors.centerIn: parent; text: "Refresh"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fg }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: refresh() }
                }
                Item { Layout.fillWidth: true }
                Text { text: "j/k move · H/J/K/L position · Enter act · d disconnect · r refresh · Esc close"; font.family: Theme.fontFamily; font.pixelSize: 10; color: Theme.fgDim }
            }
        }
        Keys.onPressed: (e)=>{
            const shift = (e.modifiers & Qt.ShiftModifier) !== 0
            if(e.key===Qt.Key_Escape) root.close()
            else if(e.key===Qt.Key_R) { refresh(); e.accepted=true }
            else if(shift && e.key===Qt.Key_H) { root.placeFocused("left"); e.accepted=true }
            else if(shift && e.key===Qt.Key_J) { root.placeFocused("bottom"); e.accepted=true }
            else if(shift && e.key===Qt.Key_K) { root.placeFocused("top"); e.accepted=true }
            else if(shift && e.key===Qt.Key_L) { root.placeFocused("right"); e.accepted=true }
            else if(e.key===Qt.Key_J || e.key===Qt.Key_Down) { root.moveSel(1); e.accepted=true }
            else if(e.key===Qt.Key_K || e.key===Qt.Key_Up) { root.moveSel(-1); e.accepted=true }
            else if(e.key===Qt.Key_Return || e.key===Qt.Key_Enter) { root.activate(); e.accepted=true }
            else if(e.key===Qt.Key_D) { root.disconnectFocused(); e.accepted=true }
        }
    }
    function updateNav(){
        const items=[]
        for(let i=0;i<monitors.length;i++) items.push({kind:"monitor", idx:i})
        for(let i=0;i<availableMonitors.length;i++){
            items.push({kind:"available", idx:i, mode:"extend"})
            items.push({kind:"available", idx:i, mode:"duplicate"})
        }
        items.push({kind:"refresh"})
        navItems=items
        selIndex=Math.max(0, Math.min(selIndex, items.length-1))
    }
    function moveSel(delta){
        const n = navItems.length
        if(n===0) return
        selIndex = Math.max(0, Math.min(n-1, selIndex+delta))
        const it = navItems[selIndex]
        if(!it) return
        if(it.kind==="monitor" && currentList) currentList.positionViewAtIndex(it.idx, ListView.Contain)
        else if(it.kind==="available" && availableList) availableList.positionViewAtIndex(it.idx, ListView.Contain)
        Qt.callLater(()=> mainCol.forceActiveFocus())
    }
    function logicalSize(m){
        const sw = (m.transform % 2 === 1) ? m.h : m.w
        const sh = (m.transform % 2 === 1) ? m.w : m.h
        return { w: Math.round(sw / m.scale), h: Math.round(sh / m.scale) }
    }
    function anchorFor(m){
        if(!m) return null
        if(HyprService.refMonitorName && m.name !== HyprService.refMonitorName){
            const ref = monitors.find(x => x.name === HyprService.refMonitorName)
            if(ref) return ref
        }
        return monitors.find(x => x.name !== m.name) || null
    }
    function monitorRelation(idx){
        const m = monitors[idx]
        if(!m) return null
        const s = logicalSize(m)
        const near = (p,q)=> Math.abs(p-q) <= 2
        for(const o of monitors){
            if(o.name === m.name) continue
            const os = logicalSize(o)
            if(near(m.y, o.y) && near(m.x + s.w, o.x)) return { dir: "left", name: o.name }
            if(near(m.y, o.y) && near(m.x, o.x + os.w)) return { dir: "right", name: o.name }
            if(near(m.x, o.x) && near(m.y + s.h, o.y)) return { dir: "top", name: o.name }
            if(near(m.x, o.x) && near(m.y, o.y + os.h)) return { dir: "bottom", name: o.name }
        }
        return null
    }
    function luaQuote(s){
        return "\"" + String(s).replace(/\\/g, "\\\\").replace(/"/g, "\\\"") + "\""
    }
    function luaRule(name, mode, position, scale, mirror){
        return "hl.monitor({output=" + luaQuote(name)
            + ", disabled=false, mirror=" + luaQuote(mirror || "")
            + ", mode=" + luaQuote(mode)
            + ", position=" + luaQuote(position)
            + ", scale=" + scale + "})"
    }
    function mirrorName(m){
        if(!m || !m.mirrorOf || m.mirrorOf === "none") return ""
        const target = monitors.find(x => String(x.id) === String(m.mirrorOf))
        return target ? target.name : ""
    }
    function preserveRules(exceptIdx){
        let lua = ""
        for(let i=0;i<monitors.length;i++){
            if(i===exceptIdx) continue
            const m = monitors[i]
            if(mirrorName(m)) continue
            lua += luaRule(m.name, m.mode, m.x + "x" + m.y, m.scale, "") + "; "
        }
        return lua
    }
    function runLua(lua){
        evalProc.command = ["hyprctl","eval",lua]
        evalProc.running = true
    }
    function placeMonitor(idx, dir){
        const m = monitors[idx]
        if(!m || monitors.length < 2) return
        const a = anchorFor(m)
        if(!a) return
        const s = logicalSize(m)
        let x = a.x
        let y = a.y
        for(const o of monitors){
            if(o.name === m.name) continue
            const os = logicalSize(o)
            if(dir==="left") x = Math.min(x, o.x - s.w)
            else if(dir==="right") x = Math.max(x, o.x + os.w)
            else if(dir==="top") y = Math.min(y, o.y - s.h)
            else if(dir==="bottom") y = Math.max(y, o.y + os.h)
        }
        transientError = ""
        runLua(luaRule(m.name, m.mode, x + "x" + y, m.scale, "") + "; " + preserveRules(idx))
    }
    function placeFocused(dir){
        const it = navItems[selIndex]
        if(!it || it.kind!=="monitor") return
        placeMonitor(it.idx, dir)
    }
    function toggleMirror(idx){
        const m = monitors[idx]
        if(!m || monitors.length < 2) return
        const mirrored = mirrorName(m) !== ""
        let target = ""
        if(!mirrored){
            target = (HyprService.refMonitorName && m.name !== HyprService.refMonitorName)
                ? HyprService.refMonitorName
                : (anchorFor(m) ? anchorFor(m).name : "")
            if(!target) return
        }
        transientError = ""
        runLua(luaRule(m.name, "preferred", "auto", 1, target) + "; " + preserveRules(idx))
    }
    function disconnectIndex(idx){
        const m = monitors[idx]
        if(!m) return
        if(monitors.length<2){ transientError="Cannot disable the only monitor"; return }
        transientError = ""
        runLua("hl.monitor({output=" + luaQuote(m.name) + ", disabled=true}); " + preserveRules(idx))
    }
    function disconnectFocused(){
        const it = navItems[selIndex]
        if(!it || it.kind!=="monitor") return
        disconnectIndex(it.idx)
    }
    function activate(){
        const it = navItems[selIndex]
        if(!it) return
        if(it.kind==="monitor") disconnectFocused()
        else if(it.kind==="available") { const m = availableMonitors[it.idx]; if(m) connectProc(it.mode, m.name) }
        else if(it.kind==="refresh") refresh()
    }
    readonly property var monitors: HyprService.monitors
    readonly property var availableMonitors: HyprService.availableMonitors
    readonly property string hyprError: (monitors.length === 0 && HyprService.available) ? "hyprctl failed" : ""
    property string transientError: ""
    onMonitorsChanged: updateNav()
    onAvailableMonitorsChanged: updateNav()
    function refresh(){
        HyprService.refreshMonitors()
    }
    function connectProc(mode, name){
        transientError = ""
        let lua = ""
        if(mode==="extend") lua = luaRule(name, "preferred", "auto", 1, "")
        else if(mode==="duplicate") {
            const primary = HyprService.refMonitorName || (monitors.length>0 ? monitors[0].name : name)
            lua = luaRule(name, "preferred", "auto", 1, primary)
        }
        runLua(lua + "; " + preserveRules(-1))
    }
    property Process evalProc: Process { stdout: StdioCollector { onStreamFinished: refresh() } }
}
