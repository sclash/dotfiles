import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../../theme"

WlrLayershell {
    id: root
    property bool isOpen: false
    property int currentSection: 0
    property bool filterActive: filterField.text.length > 0

    // keep in sync with: hypr/hyprland.lua · ghostty/config · tmux/tmux.conf · herdr/config.toml
    property var sections: [
        { name: "Shell", bindings: [
            { key: "SUPER+SPACE", action: "Control Center", desc: "meta" },
            { key: "SUPER+R", action: "App Launcher", desc: "apps" },
            { key: "SUPER+W", action: "Network", desc: "wifi" },
            { key: "SUPER+B", action: "Bluetooth", desc: "bt" },
            { key: "SUPER+A", action: "Audio", desc: "sound" },
            { key: "SUPER+D", action: "Display", desc: "monitors" },
            { key: "SUPER+SHIFT+A", action: "Notifications", desc: "bell" },
            { key: "SUPER+C", action: "Calendar", desc: "dates" },
            { key: "SUPER+Q", action: "Shutdown", desc: "power" },
            { key: "SUPER+U", action: "USB Devices", desc: "usb" },
            { key: "SUPER+T", action: "Tray Manager", desc: "tray" },
            { key: "SUPER+P", action: "Power Center", desc: "battery" },
            { key: "SUPER+SHIFT+P", action: "Perf Drawer", desc: "metrics" },
            { key: "SUPER+/", action: "Key Hints", desc: "this" },
            { key: "ESC", action: "Close Launcher", desc: "dismiss" },
            { key: "SUPER+ESC", action: "Close All Launchers", desc: "dismiss" }
        ] },
        { name: "Hyprland", bindings: [
            { key: "SUPER+Return", action: "Terminal", desc: "ghostty" },
            { key: "SUPER+E", action: "File Manager", desc: "nautilus" },
            { key: "SUPER+G", action: "Browser", desc: "chrome" },
            { key: "SUPER+X", action: "Lock Screen", desc: "hyprlock" },
            { key: "SUPER+SHIFT+C", action: "Close Window", desc: "kill" },
            { key: "SUPER+V", action: "Toggle Float", desc: "float" },
            { key: "SUPER+SHIFT+F", action: "Toggle Fullscreen", desc: "full" },
            { key: "SUPER+SHIFT+J", action: "Toggle Split", desc: "dwindle" },
            { key: "SUPER+F", action: "Restart Quickshell", desc: "reload" },
            { key: "SUPER+Z", action: "Toggle Hyprpaper", desc: "wallpaper" },
            { key: "SUPER+H/J/K/L", action: "Focus Window", desc: "focus" },
            { key: "SUPER+ALT+H/J/K/L", action: "Swap Window", desc: "swap" },
            { key: "SUPER+SHIFT+H/L", action: "Resize Window", desc: "resize" },
            { key: "SUPER+1..0", action: "Workspace 1..10", desc: "switch" },
            { key: "SUPER+SHIFT+1..0", action: "Move to Workspace", desc: "send" },
            { key: "SUPER+S", action: "Special Workspace", desc: "scratch" },
            { key: "SUPER+SHIFT+S", action: "Move to Special", desc: "scratch" },
            { key: "SUPER+SHIFT+W", action: "Toggle Tab Group", desc: "group" },
            { key: "SUPER+[ / ]", action: "Prev / Next Group Tab", desc: "tabs" },
            { key: "SUPER+SHIFT+[ / ]", action: "Move in Group", desc: "tabs" },
            { key: "SUPER+SHIFT+CTRL+[ / ]", action: "Move Into Group", desc: "tabs" },
            { key: "SUPER+SHIFT+ALT+H/J/K/L", action: "Move Out of Group", desc: "tabs" },
            { key: "SUPER+SHIFT+R", action: "Resize Submap", desc: "mode" },
            { key: "ALT+SHIFT", action: "Cycle Keyboard Layout", desc: "us/it" },
            { key: "XF86AudioRaiseVolume", action: "Volume +5%", desc: "audio" },
            { key: "XF86AudioLowerVolume", action: "Volume −5%", desc: "audio" },
            { key: "XF86AudioMute", action: "Mute Output", desc: "audio" },
            { key: "XF86AudioMicMute", action: "Mute Mic", desc: "audio" },
            { key: "XF86MonBrightnessUp", action: "Brightness +5%", desc: "backlight" },
            { key: "XF86MonBrightnessDown", action: "Brightness −5%", desc: "backlight" },
            { key: "XF86AudioNext", action: "Media Next", desc: "media" },
            { key: "XF86AudioPrev", action: "Media Previous", desc: "media" },
            { key: "XF86AudioPlay", action: "Media Play", desc: "media" },
            { key: "XF86AudioPause", action: "Media Pause", desc: "media" },
            { key: "SUPER+Scroll", action: "Cycle Workspace", desc: "mouse" },
            { key: "SUPER+LMB Drag", action: "Move Window", desc: "mouse" },
            { key: "SUPER+RMB Drag", action: "Resize Window", desc: "mouse" }
        ] },
        { name: "Ghostty", bindings: [
            { key: "ctrl+alt+up", action: "Next Tab", desc: "tab" },
            { key: "ctrl+alt+down", action: "Previous Tab", desc: "tab" },
            { key: "ctrl+shift+\\", action: "New Split Right", desc: "split" },
            { key: "ctrl+shift+-", action: "New Split Down", desc: "split" },
            { key: "ctrl+shift+z", action: "Zoom Split", desc: "zoom" },
            { key: "ctrl+shift+e", action: "Equalize Splits", desc: "split" },
            { key: "ctrl+shift+h/j/k/l", action: "Resize Split", desc: "resize" },
            { key: "ctrl+alt+h/j/k/l", action: "Go to Split", desc: "focus" }
        ] },
        { name: "Tmux", bindings: [
            { key: 'prefix+"', action: "Split Below (cwd)", desc: "pane" },
            { key: "prefix+%", action: "Split Right (cwd)", desc: "pane" },
            { key: "prefix+N", action: "New Window (cwd)", desc: "window" },
            { key: "prefix+c", action: "New Window", desc: "window" },
            { key: "prefix+1..9", action: "Window 1..9", desc: "switch" },
            { key: "prefix+n", action: "Next Window", desc: "window" },
            { key: "prefix+p", action: "Previous Window", desc: "window" },
            { key: "prefix+w", action: "Window Picker", desc: "window" },
            { key: "prefix+o", action: "Next Pane", desc: "pane" },
            { key: "prefix+q", action: "Pane Numbers", desc: "info" },
            { key: "prefix+z", action: "Zoom Pane", desc: "zoom" },
            { key: "prefix+x", action: "Kill Pane", desc: "kill" },
            { key: "prefix+&", action: "Kill Window", desc: "kill" },
            { key: "prefix+,", action: "Rename Window", desc: "rename" },
            { key: "prefix+space", action: "Next Layout", desc: "layout" },
            { key: "prefix+{ / }", action: "Swap Panes", desc: "pane" },
            { key: "prefix+[", action: "Copy Mode", desc: "scroll" },
            { key: "prefix+]", action: "Paste Buffer", desc: "paste" },
            { key: "prefix+d", action: "Detach", desc: "detach" },
            { key: "prefix+:", action: "Command Prompt", desc: "cmd" },
            { key: "prefix+?", action: "List Keys", desc: "help" },
            { key: "v (copy)", action: "Begin Selection", desc: "copy" },
            { key: "C-v (copy)", action: "Rectangle Select", desc: "copy" },
            { key: "y (copy)", action: "Copy + Exit", desc: "copy" },
            { key: "alt+h/j/k/l", action: "Focus Pane", desc: "pane" },
            { key: "alt+d", action: "Previous Window", desc: "window" },
            { key: "alt+u", action: "Next Window", desc: "window" },
            { key: "alt+t", action: "Popup Shell", desc: "popup" },
            { key: "alt+v", action: "Split Below (cwd)", desc: "pane" },
            { key: "alt+m", action: "Split Right (cwd)", desc: "pane" }
        ] },
        { name: "Herdr", bindings: [
            { key: "prefix+%", action: "Split Vertical", desc: "pane" },
            { key: 'prefix+"', action: "Split Horizontal", desc: "pane" },
            { key: "prefix+d", action: "Detach", desc: "detach" },
            { key: "prefix+c", action: "New Tab", desc: "tab" },
            { key: "prefix+tab", action: "Next Workspace", desc: "ws" },
            { key: "prefix+shift+tab", action: "Previous Workspace", desc: "ws" },
            { key: "prefix+alt+h/j/k/l", action: "Resize Pane", desc: "resize" },
            { key: "prefix+alt+1..9", action: "Focus Agent", desc: "agent" },
            { key: "alt+h/j/k/l", action: "Focus Pane", desc: "pane" },
            { key: "alt+d", action: "Previous Tab", desc: "tab" },
            { key: "alt+u", action: "Next Tab", desc: "tab" },
            { key: "alt+tab", action: "Next Agent", desc: "agent" },
            { key: "alt+shift+tab", action: "Previous Agent", desc: "agent" }
        ] }
    ]

    function open(){ isOpen=true }
    function close(){ isOpen=false; resetFilter() }
    function toggle(){ if(isOpen) close(); else open() }

    anchors { top:true; bottom:true; left:true; right:true }
    onIsOpenChanged: if(isOpen) { resetFilter(); Qt.callLater(()=> listView.forceActiveFocus()) }
    color: "transparent"
    visible: isOpen
    keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore
    Rectangle { anchors.fill: parent; color: Theme.overlay; MouseArea { anchors.fill: parent; onClicked: root.close() } }

    Rectangle {
        width: 640
        height: Math.min(560, col.implicitHeight + Theme.padL*2)
        anchors.centerIn: parent
        radius: Theme.roundingLauncher
        color: Theme.bgLauncher
        border.width: 1
        border.color: Theme.borderActive
        ColumnLayout {
            id: col
            anchors.fill: parent
            anchors.margins: Theme.padL
            spacing: Theme.gapM
            focus: true
            Text { text: "Key Hints"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fgMuted; font.capitalization: Font.AllUppercase; font.letterSpacing: 1.2 }
            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border }
            RowLayout {
                id: tabBar
                Layout.fillWidth: true
                spacing: Theme.gapS
                Repeater {
                    model: root.sections
                    Rectangle {
                        required property var modelData
                        required property int index
                        property bool active: index === root.currentSection
                        Layout.preferredHeight: 26
                        Layout.preferredWidth: pillLabel.implicitWidth + Theme.padM*2 + numLabel.implicitWidth
                        radius: Theme.roundingItem
                        color: active ? Theme.bgBarAlt : "transparent"
                        border.width: active ? 1 : 0
                        border.color: Theme.borderActive
                        RowLayout {
                            anchors.centerIn: parent
                            spacing: Theme.gapS
                            Text { id: numLabel; text: index+1; font.family: Theme.fontFamily; font.pixelSize: 10; color: Theme.fgDim }
                            Text { id: pillLabel; text: modelData.name; font.family: Theme.fontFamily; font.pixelSize: 11; font.weight: Theme.fontWeightMedium; color: active ? Theme.fg : Theme.fgMuted }
                        }
                        MouseArea { anchors.fill: parent; onClicked: root.selectSection(index) }
                    }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.gapM
                Rectangle {
                    id: filterBar
                    visible: false
                    Layout.fillWidth: true
                    Layout.preferredHeight: 38
                    radius: Theme.roundingItem
                    color: Theme.bgActive
                    border.color: filterField.activeFocus ? Theme.borderSelected : Theme.border
                    border.width: 1
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.padM
                        Text { text: Icons.search; font.family: Theme.fontFamily; font.pixelSize: 16; color: Theme.fgMuted }
                        TextField {
                            id: filterField
                            Layout.fillWidth: true
                            placeholderText: "Filter keys…"
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            color: Theme.fg
                            placeholderTextColor: Theme.fgDim
                            background: null
                            cursorDelegate: Rectangle {
                                width: Math.max(6, Math.round(parent.font.pixelSize * 0.65))
                                height: Math.round(parent.font.pixelSize * 1.5)
                                color: Theme.fg
                            }
                            onTextChanged: { listView.model = visibleRows(); listView.contentY = 0 }
                            Keys.onPressed: (e)=>{
                                if(e.key===Qt.Key_Escape) {
                                    if(filterField.text.length>0) listView.forceActiveFocus()
                                    else { filterBar.visible=false; listView.forceActiveFocus() }
                                    e.accepted=true
                                }
                            }
                        }
                    }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.gapL
                Text { text: "KEY"; font.family: Theme.fontFamily; font.pixelSize: 10; color: Theme.fgMuted; font.weight: Theme.fontWeightMedium; Layout.preferredWidth: 150 }
                Text { text: "ACTION"; font.family: Theme.fontFamily; font.pixelSize: 10; color: Theme.fgMuted; font.weight: Theme.fontWeightMedium; Layout.fillWidth: true }
                Text { text: root.filterActive ? "SECTION" : ""; font.family: Theme.fontFamily; font.pixelSize: 10; color: Theme.fgMuted; font.weight: Theme.fontWeightMedium; Layout.preferredWidth: 80; horizontalAlignment: Text.AlignRight }
            }
            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border }
            ListView {
                id: listView
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(430, Math.max(240, contentHeight))
                clip: true
                spacing: 2
                model: root.sections[root.currentSection].bindings
                delegate: Rectangle {
                    required property var modelData
                    width: listView.width
                    height: 36
                    radius: Theme.roundingItem
                    color: "transparent"
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.padM
                        anchors.rightMargin: Theme.padM
                        spacing: Theme.gapM
                        Text {
                            text: modelData.key
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            font.weight: Theme.fontWeightMedium
                            color: Theme.fg
                            Layout.preferredWidth: 150
                            elide: Text.ElideRight
                        }
                        Text { text: modelData.action; font.family: Theme.fontFamily; font.pixelSize: 13; color: Theme.fg; Layout.fillWidth: true; elide: Text.ElideRight }
                        Text {
                            text: root.filterActive ? modelData.section : modelData.desc
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            color: root.filterActive ? Theme.fgDim : Theme.fgMuted
                            font.italic: root.filterActive
                            Layout.preferredWidth: 80
                            horizontalAlignment: Text.AlignRight
                            elide: Text.ElideRight
                        }
                    }
                }
                Keys.onPressed: (e)=>{
                    if(e.key===Qt.Key_J || e.key===Qt.Key_Down) { if(listView.contentHeight > listView.height) listView.contentY = Math.min(listView.contentHeight - listView.height, listView.contentY + 38); e.accepted=true }
                    else if(e.key===Qt.Key_K || e.key===Qt.Key_Up) { listView.contentY = Math.max(0, listView.contentY - 38); e.accepted=true }
                    else if(e.key===Qt.Key_Backtab) { root.selectSection((root.currentSection + root.sections.length - 1) % root.sections.length); e.accepted=true }
                    else if(e.key===Qt.Key_Tab) { root.selectSection((root.currentSection + 1) % root.sections.length); e.accepted=true }
                    else if(e.key===Qt.Key_Left) { root.selectSection((root.currentSection + root.sections.length - 1) % root.sections.length); e.accepted=true }
                    else if(e.key===Qt.Key_Right) { root.selectSection((root.currentSection + 1) % root.sections.length); e.accepted=true }
                    else if(e.key>=Qt.Key_1 && e.key<=Qt.Key_9 && e.key-Qt.Key_1 < root.sections.length) { root.selectSection(e.key-Qt.Key_1); e.accepted=true }
                    else if(e.key===Qt.Key_Escape) root.close()
                    else if(e.text==="/") { filterBar.visible=true; filterField.forceActiveFocus(); e.accepted=true }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.gapL
                Text {
                    text: "1-5/tab sections · / filter · j/k scroll · esc close"
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    color: Theme.fgDim
                    Layout.minimumWidth: 0
                    elide: Text.ElideRight
                }
                Text {
                    text: "sync: hyprland.lua · ghostty · tmux · herdr"
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    color: Theme.fgDim
                    font.italic: true
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    horizontalAlignment: Text.AlignRight
                    elide: Text.ElideRight
                }
            }
        }
    }

    function selectSection(i){
        currentSection = i
        if(filterField) { filterField.text = ""; filterBar.visible = false }
        listView.model = visibleRows()
        listView.contentY = 0
        listView.forceActiveFocus()
    }
    function visibleRows(){
        const q = filterField.text.toLowerCase()
        if(q.length>0){
            var out=[]
            for(var s=0; s<sections.length; s++){
                const name = sections[s].name.toLowerCase()
                for(var b=0; b<sections[s].bindings.length; b++){
                    const row = sections[s].bindings[b]
                    if(row.key.toLowerCase().indexOf(q)!==-1 || row.action.toLowerCase().indexOf(q)!==-1 || name.indexOf(q)!==-1)
                        out.push({ key: row.key, action: row.action, desc: row.desc, section: sections[s].name })
                }
            }
            return out
        }
        return sections[currentSection].bindings
    }
    function resetFilter(){
        if(filterField) { filterField.text = ""; filterBar.visible = false }
        if(listView) { listView.model = visibleRows(); listView.contentY = 0 }
    }
}
