import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import "../../theme"
import "../../services"

PanelWindow {
    id: root
    property bool isOpen: false
    function open(){ isOpen=true }
    function close(){ isOpen=false }
    function toggle(){ if(isOpen) close(); else open() }

    anchors { top:true; bottom:true; left:true; right:true }
    color: "transparent"
    visible: isOpen
    focusable: true
    exclusionMode: ExclusionMode.Ignore

    Rectangle { anchors.fill: parent; color: Theme.overlay; MouseArea { anchors.fill: parent; onClicked: root.close() } }

    Rectangle {
        width: 640
        anchors.centerIn: parent
        radius: Theme.roundingLauncher
        color: Theme.bgLauncher
        border.width: 1
        border.color: Theme.borderActive

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Theme.padL
            spacing: Theme.gapM

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.gapM
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 44
                    radius: Theme.roundingItem
                    color: Theme.bgActive
                    border.color: searchField.activeFocus ? Theme.fg : Theme.border
                    border.width: 1
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.padM
                        anchors.rightMargin: Theme.padM
                        spacing: Theme.gapM
                        Text { text: Icons.search; font.family: Theme.fontFamily; font.pixelSize: 18; color: Theme.fgMuted }
                        TextField {
                            id: searchField
                            Layout.fillWidth: true
                            placeholderText: "Search apps…"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeLauncher
                            color: Theme.fg
                            placeholderTextColor: Theme.fgDim
                            background: null
                            onTextChanged: debounce.restart()
                            Keys.onEscapePressed: { if (text.length>0) text=""; else root.close() }
                        }
                    }
                }
            }

            ListView {
                id: listView
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(420, contentHeight)
                clip: true
                spacing: 4
                model: filteredModel
                currentIndex: 0
                highlight: Rectangle { color: Theme.bgActive; radius: Theme.roundingItem; border.color: Theme.fg; border.width: 1 }
                highlightMoveDuration: Theme.durationFast
                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    width: listView.width
                    height: 52
                    radius: Theme.roundingItem
                    color: ListView.isCurrentItem ? Theme.bgActive : (ma.containsMouse ? Theme.bgHover : "transparent")
                    border.color: ListView.isCurrentItem ? Theme.fg : "transparent"
                    border.width: 1
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.padM
                        anchors.rightMargin: Theme.padM
                        spacing: Theme.gapM
                        Rectangle {
                            width: 36; height: 36
                            radius: 8
                            color: Theme.bgHover
                            IconImage {
                                anchors.centerIn: parent
                                source: modelData.icon ? Quickshell.iconPath(modelData.icon, "application-x-executable") : ""
                                implicitWidth: 22; implicitHeight: 22
                            }
                        }
                        ColumnLayout {
                            spacing: 2
                            Layout.fillWidth: true
                            Text { text: modelData.name || ""; font.family: Theme.fontFamily; font.pixelSize: 14; font.weight: Theme.fontWeightMedium; color: Theme.fg; elide: Text.ElideRight; Layout.fillWidth: true }
                            Text { text: modelData.comment || modelData.exec || ""; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fgMuted; elide: Text.ElideRight; Layout.fillWidth: true }
                        }
                        Text { text: Icons.check; color: Theme.fg; font.pixelSize: 14; font.family: Theme.fontFamily; visible: ListView.isCurrentItem }
                    }
                    MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; onClicked: { listView.currentIndex=index; launchCurrent() } }
                }
                Keys.onPressed: (e)=>{
                    if (e.key===Qt.Key_J || e.key===Qt.Key_Down) { currentIndex=Math.min(count-1, currentIndex+1); e.accepted=true }
                    else if (e.key===Qt.Key_K || e.key===Qt.Key_Up) { currentIndex=Math.max(0, currentIndex-1); e.accepted=true }
                    else if (e.key===Qt.Key_Return || e.key===Qt.Key_Enter) { launchCurrent(); e.accepted=true }
                    else if (e.key===Qt.Key_Escape) root.close()
                    else if (e.text==="/") { searchField.forceActiveFocus(); e.accepted=true }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.gapS
                Text {
                    visible: listView.count===0
                    text: searchField.text.length===0 ? "Type to search — / to filter, j/k to move, Enter to launch" : "No results for \"" + searchField.text + "\""
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.fgMuted
                }
                Item { Layout.fillWidth: true }
                Text {
                    visible: !hasBackend
                    text: "⊘ elephant/walker → desktop entries"
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    color: Theme.warning
                }
            }
        }

        Keys.onEscapePressed: root.close()
        Component.onCompleted: if(isOpen) searchField.forceActiveFocus()
        onVisibleChanged: if(visible) searchField.forceActiveFocus()
    }

    onIsOpenChanged: if(isOpen) { Qt.callLater(()=> searchField.forceActiveFocus()); } else { searchField.text="" }

    property var allApps: []
    property var filteredModel: []
    property bool hasBackend: false

    function updateFilter(){
        const q = searchField.text.toLowerCase()
        if (!q) filteredModel = allApps.slice(0, 20)
        else filteredModel = allApps.filter(a=> (a.name && a.name.toLowerCase().indexOf(q)!==-1) || (a.exec && a.exec.toLowerCase().indexOf(q)!==-1)).slice(0, 30)
        listView.currentIndex=0
    }

    Timer { id: debounce; interval: 120; onTriggered: updateFilter() }

    function launchCurrent(){
        if (listView.count===0 || listView.currentIndex<0) return
        const entry = filteredModel[listView.currentIndex]
        if (!entry) return
        if (entry.exec) {
            let cmd = entry.exec.replace(/%[UuFf]/g,"").trim().split(" ")
            launchProc.command = cmd
            launchProc.running = true
        } else if (entry.desktopId) {
            launchProc.command = ["gtk-launch", entry.desktopId]
            launchProc.running = true
        }
        root.close()
    }

    property Process launchProc: Process {}
    property Process probeProc: Process {
        running: true
        command: ["sh","-c","command -v elephant >/dev/null && echo elephant || (command -v walker >/dev/null && echo walker || echo desktop)"]
        stdout: StdioCollector {
            onStreamFinished: {
                const backend = this.text.trim()
                if (backend==="elephant"|| backend==="walker") root.hasBackend=true
                else root.hasBackend=false
                root.loadProc.running=true
            }
        }
    }
    property Process loadProc: Process {
        command: ["sh", "-c", "python3 -c \"import glob,configparser; files=glob.glob('/usr/share/applications/*.desktop')[:120]\nfor f in files:\n    c=configparser.ConfigParser(interpolation=None); c.optionxform=str\n    try:\n        c.read(f); print(f\\\"{c.get('Desktop Entry','Name',fallback='Unknown')}|{c.get('Desktop Entry','Exec',fallback='')}|{c.get('Desktop Entry','Icon',fallback='')}|{c.get('Desktop Entry','Comment',fallback=c.get('Desktop Entry','Exec',fallback=''))}\\\")\n    except: pass\""] 
        stdout: StdioCollector {
            onStreamFinished: {
                const lines=this.text.trim().split("\n").filter(Boolean)
                const apps=[]
                for (const l of lines) {
                    const parts=l.split("|")
                    if (parts.length<2) continue
                    apps.push({name: parts[0]||"Unknown", exec: parts[1]||"", comment: parts[3]||parts[1]||"", icon: parts[2]||"", desktopId: ""})
                }
                if (apps.length===0) apps.push({name:"Ghostty", exec:"ghostty", icon:"ghostty", comment:"Terminal"}, {name:"Nautilus", exec:"nautilus", icon:"nautilus", comment:"Files"}, {name:"Chrome", exec:"google-chrome-stable", icon:"google-chrome", comment:"Browser"})
                root.allApps=apps
                root.updateFilter()
            }
        }
    }
}
