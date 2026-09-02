import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire
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
    color: "transparent"
    visible: isOpen
    keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore
    Rectangle { anchors.fill: parent; color: Theme.overlay; MouseArea { anchors.fill: parent; onClicked: root.close() } }

    Rectangle {
        width: 620
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
            Text { text: "Audio"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fgMuted; font.capitalization: Font.AllUppercase; font.letterSpacing: 1.2 }
            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border }

            Text { text: "Output"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fgMuted; font.weight: Theme.fontWeightMedium }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.gapS
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.gapM
                    Layout.alignment: Qt.AlignVCenter
                    Text { text: AudioService.muted ? Icons.audioMuted : Icons.audioVolume; font.family: Theme.fontFamily; font.pixelSize: 18; color: AudioService.hasSink ? (AudioService.muted ? Theme.warning : Theme.fgBright) : Theme.fgDim }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        Text {
                            text: AudioService.hasSink ? (AudioService.sinkName || "Unknown") : "No output device"
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            font.weight: Theme.fontWeightMedium
                            color: AudioService.hasSink ? Theme.fgBright : Theme.fgDim
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }
                        Text { text: AudioService.hasSink ? AudioService.volume + "%" + (AudioService.muted ? " · muted" : "") : ""; color: Theme.fgMuted; font.family: Theme.fontFamily; font.pixelSize: 11 }
                    }
                    Switch {
                        id: muteSwitch
                        checked: !AudioService.muted
                        onClicked: AudioService.toggleMute()
                        Layout.alignment: Qt.AlignVCenter
                        readonly property bool isSel: root.navItems[root.selIndex] !== undefined && root.navItems[root.selIndex].kind === "mute"
                        indicator: Rectangle {
                            implicitWidth: 36; implicitHeight: 18
                            radius: 9
                            color: muteSwitch.checked ? Theme.bgSelected : Theme.bgBar
                            border.color: muteSwitch.isSel ? Theme.borderSelected : (muteSwitch.checked ? Theme.borderSelected : Theme.border)
                            border.width: muteSwitch.isSel ? 2 : 1
                            Rectangle {
                                width: 12; height: 12; radius: 6
                                x: muteSwitch.checked ? parent.width - width - 3 : 3
                                anchors.verticalCenter: parent.verticalCenter
                                color: muteSwitch.checked ? Theme.fg : Theme.fgMuted
                                Behavior on x { NumberAnimation { duration: Theme.durationFast } }
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.gapM
                    Rectangle {
                        id: volMinus
                        width: 24; height: 24
                        radius: Theme.roundingItem
                        readonly property bool isSel: root.navItems[root.selIndex] !== undefined && root.navItems[root.selIndex].kind === "volMinus"
                        color: isSel ? Theme.bgHover : (volMinusMouse.containsMouse ? Theme.bgHover : "transparent")
                        Text { anchors.centerIn: parent; text: "−"; font.family: Theme.fontFamily; font.pixelSize: 14; color: Theme.fgMuted }
                        MouseArea { id: volMinusMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: AudioService.adjustVolume(-0.05) }
                    }
                    Slider {
                        id: volSlider
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        from: 0; to: 1
                        value: (AudioService.sink && AudioService.sink.audio) ? AudioService.sink.audio.volume : 0
                        onMoved: AudioService.setVolume(value)
                        Connections {
                            target: AudioService.sink && AudioService.sink.audio ? AudioService.sink.audio : null
                            function onVolumeChanged(){ volSlider.value = target.volume }
                            function onVolumesChanged(){ volSlider.value = target.volume }
                        }
                        readonly property bool isSel: root.navItems[root.selIndex] !== undefined && root.navItems[root.selIndex].kind === "volSlider"
                        background: Rectangle {
                            implicitHeight: 4; radius: 2
                            color: Theme.border
                            border.color: volSlider.isSel ? Theme.borderSelected : "transparent"
                            border.width: volSlider.isSel ? 1 : 0
                            Rectangle { width: volSlider.visualPosition*parent.width; height: parent.height; radius: 2; color: Theme.fgMuted }
                        }
                        handle: Rectangle { x: volSlider.leftPadding + volSlider.visualPosition*(volSlider.availableWidth - width); y: volSlider.topPadding + volSlider.availableHeight/2 - height/2; width: 12; height: 12; radius: 6; color: Theme.fg; border.color: Theme.fg; border.width: 1 }
                    }
                    Rectangle {
                        id: volPlus
                        width: 24; height: 24
                        radius: Theme.roundingItem
                        readonly property bool isSel: root.navItems[root.selIndex] !== undefined && root.navItems[root.selIndex].kind === "volPlus"
                        color: isSel ? Theme.bgHover : (volPlusMouse.containsMouse ? Theme.bgHover : "transparent")
                        Text { anchors.centerIn: parent; text: "+"; font.family: Theme.fontFamily; font.pixelSize: 14; color: Theme.fgMuted }
                        MouseArea { id: volPlusMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: AudioService.adjustVolume(0.05) }
                    }
                }
            }

            Text { text: "Sinks"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fgMuted }
            ListView {
                id: sinksList
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(140, contentHeight)
                clip: true
                spacing: 2
                model: AudioService.sinkList
                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    width: sinksList.width
                    height: 34
                    radius: Theme.roundingItem
                    readonly property bool isSel: { const it = root.navItems[root.selIndex]; return it !== undefined && it.kind === "sink" && it.idx === index }
                    readonly property bool active: AudioService.sink && modelData.id === AudioService.sink.id
                    color: isSel ? Theme.bgHover : (ma.containsMouse ? Theme.bgHover : "transparent")
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.padM
                        anchors.rightMargin: Theme.padM
                        spacing: Theme.gapM
                        Text { text: Icons.audioVolume; font.family: Theme.fontFamily; font.pixelSize: 14; color: active ? Theme.fgBright : Theme.fgMuted }
                        Text { text: modelData.description || modelData.name; font.family: Theme.fontFamily; font.pixelSize: 13; color: active ? Theme.fgBright : Theme.fg; Layout.fillWidth: true; elide: Text.ElideRight }
                        Text { visible: active; text: Icons.check; color: Theme.success; font.family: Theme.fontFamily; font.pixelSize: 14 }
                    }
                    MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; onClicked: AudioService.setDefaultSink(modelData.id) }
                }
            }

            Text { text: "Input"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fgMuted }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.gapS
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.gapM
                    Layout.alignment: Qt.AlignVCenter
                    Text { text: Icons.audio; font.family: Theme.fontFamily; font.pixelSize: 18; color: AudioService.hasSource ? (AudioService.source.audio && AudioService.source.audio.muted ? Theme.warning : Theme.fgBright) : Theme.fgDim }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        Text {
                            text: AudioService.hasSource ? (AudioService.source.description || AudioService.source.name) : "No input device"
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            color: AudioService.hasSource ? Theme.fgBright : Theme.fgDim
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }
                        Text { text: (AudioService.source && AudioService.source.audio) ? Math.round(AudioService.source.audio.volume*100) + "%" + (AudioService.source.audio.muted ? " · muted" : "") : ""; color: Theme.fgMuted; font.family: Theme.fontFamily; font.pixelSize: 11 }
                    }
                    Switch {
                        id: micSwitch
                        checked: AudioService.source && AudioService.source.audio ? !AudioService.source.audio.muted : false
                        onClicked: if(AudioService.source && AudioService.source.audio) AudioService.source.audio.muted = !AudioService.source.audio.muted
                        Layout.alignment: Qt.AlignVCenter
                        readonly property bool isSel: root.navItems[root.selIndex] !== undefined && root.navItems[root.selIndex].kind === "micSwitch"
                        indicator: Rectangle {
                            implicitWidth: 36; implicitHeight: 18
                            radius: 9
                            color: micSwitch.checked ? Theme.bgSelected : Theme.bgBar
                            border.color: micSwitch.isSel ? Theme.borderSelected : (micSwitch.checked ? Theme.borderSelected : Theme.border)
                            border.width: micSwitch.isSel ? 2 : 1
                            Rectangle {
                                width: 12; height: 12; radius: 6
                                x: micSwitch.checked ? parent.width - width - 3 : 3
                                anchors.verticalCenter: parent.verticalCenter
                                color: micSwitch.checked ? Theme.fg : Theme.fgMuted
                                Behavior on x { NumberAnimation { duration: Theme.durationFast } }
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.gapM
                    Rectangle {
                        id: micMinus
                        width: 24; height: 24
                        radius: Theme.roundingItem
                        readonly property bool isSel: root.navItems[root.selIndex] !== undefined && root.navItems[root.selIndex].kind === "micMinus"
                        color: isSel ? Theme.bgHover : (micMinusMouse.containsMouse ? Theme.bgHover : "transparent")
                        Text { anchors.centerIn: parent; text: "−"; font.family: Theme.fontFamily; font.pixelSize: 14; color: Theme.fgMuted }
                        MouseArea { id: micMinusMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: if(AudioService.source && AudioService.source.audio) AudioService.source.audio.volume = Math.max(0, AudioService.source.audio.volume - 0.05) }
                    }
                    Slider {
                        id: micSlider
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        from: 0; to: 1
                        value: (AudioService.source && AudioService.source.audio) ? AudioService.source.audio.volume : 0
                        onMoved: if(AudioService.source && AudioService.source.audio) AudioService.source.audio.volume = value
                        Connections {
                            target: AudioService.source && AudioService.source.audio ? AudioService.source.audio : null
                            function onVolumeChanged(){ micSlider.value = target.volume }
                            function onVolumesChanged(){ micSlider.value = target.volume }
                        }
                        readonly property bool isSel: root.navItems[root.selIndex] !== undefined && root.navItems[root.selIndex].kind === "micSlider"
                        background: Rectangle {
                            implicitHeight: 4; radius: 2
                            color: Theme.border
                            border.color: micSlider.isSel ? Theme.borderSelected : "transparent"
                            border.width: micSlider.isSel ? 1 : 0
                            Rectangle { width: micSlider.visualPosition*parent.width; height: parent.height; radius: 2; color: Theme.fgMuted }
                        }
                        handle: Rectangle { x: micSlider.leftPadding + micSlider.visualPosition*(micSlider.availableWidth - width); y: micSlider.topPadding + micSlider.availableHeight/2 - height/2; width: 12; height: 12; radius: 6; color: Theme.fg; border.color: Theme.fg; border.width: 1 }
                    }
                    Rectangle {
                        id: micPlus
                        width: 24; height: 24
                        radius: Theme.roundingItem
                        readonly property bool isSel: root.navItems[root.selIndex] !== undefined && root.navItems[root.selIndex].kind === "micPlus"
                        color: isSel ? Theme.bgHover : (micPlusMouse.containsMouse ? Theme.bgHover : "transparent")
                        Text { anchors.centerIn: parent; text: "+"; font.family: Theme.fontFamily; font.pixelSize: 14; color: Theme.fgMuted }

                        MouseArea { id: micPlusMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: if(AudioService.source && AudioService.source.audio) AudioService.source.audio.volume = Math.min(1, AudioService.source.audio.volume + 0.05) }
                    }
                }
            }

            ListView {
                id: sourcesList
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(100, contentHeight)
                clip: true
                spacing: 2
                model: AudioService.sourceList
                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    width: sourcesList.width
                    height: 34
                    radius: Theme.roundingItem
                    readonly property bool isSel: { const it = root.navItems[root.selIndex]; return it !== undefined && it.kind === "source" && it.idx === index }
                    readonly property bool active: AudioService.source && modelData.id===AudioService.source.id
                    color: isSel ? Theme.bgHover : (ma2.containsMouse ? Theme.bgHover : "transparent")
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.padM
                        anchors.rightMargin: Theme.padM
                        spacing: Theme.gapM
                        Text { text: Icons.audio; font.family: Theme.fontFamily; font.pixelSize: 14; color: active ? Theme.fgBright : Theme.fgMuted }
                        Text { text: modelData.description || modelData.name; font.family: Theme.fontFamily; font.pixelSize: 13; color: active ? Theme.fgBright : Theme.fg; Layout.fillWidth: true; elide: Text.ElideRight }
                        Text { visible: active; text: Icons.check; color: Theme.success; font.family: Theme.fontFamily; font.pixelSize: 14 }
                    }
                    MouseArea { id: ma2; anchors.fill: parent; hoverEnabled: true; onClicked: AudioService.setDefaultSource(modelData.id) }
                }
            }
            Text { text: "h/l adjust · j/k move · Enter act · m mute · Esc close"; font.family: Theme.fontFamily; font.pixelSize: 10; color: Theme.fgDim; Layout.alignment: Qt.AlignHCenter }
        }
        Keys.onPressed: (e)=>{
            if(e.key===Qt.Key_Escape) root.close()
            else if(e.key===Qt.Key_H || e.key===Qt.Key_Left) { root.adjustSel(-1); e.accepted=true }
            else if(e.key===Qt.Key_L || e.key===Qt.Key_Right) { root.adjustSel(1); e.accepted=true }
            else if(e.key===Qt.Key_J || e.key===Qt.Key_Down) { root.moveSel(1); e.accepted=true }
            else if(e.key===Qt.Key_K || e.key===Qt.Key_Up) { root.moveSel(-1); e.accepted=true }
            else if(e.key===Qt.Key_Return || e.key===Qt.Key_Enter) { root.activate(); e.accepted=true }
            else if(e.key===Qt.Key_M) { AudioService.toggleMute(); e.accepted=true }
        }
    }
    function updateNav(){
        const items=[]
        items.push({kind:"mute"})
        items.push({kind:"volMinus"})
        items.push({kind:"volSlider"})
        items.push({kind:"volPlus"})
        const sinks = AudioService.sinkList
        for(let i=0;i<sinks.length;i++) items.push({kind:"sink", idx:i})
        items.push({kind:"micSwitch"})
        items.push({kind:"micMinus"})
        items.push({kind:"micSlider"})
        items.push({kind:"micPlus"})
        const sources = AudioService.sourceList
        for(let i=0;i<sources.length;i++) items.push({kind:"source", idx:i})
        navItems=items
        selIndex=Math.max(0, Math.min(selIndex, items.length-1))
    }
    function moveSel(delta){
        const n = navItems.length
        if(n===0) return
        selIndex = Math.max(0, Math.min(n-1, selIndex+delta))
        ensureVisible()
        Qt.callLater(()=> mainCol.forceActiveFocus())
    }
    function adjustSel(delta){
        const it = navItems[selIndex]
        if(!it) return
        if(it.kind==="volMinus"||it.kind==="volSlider"||it.kind==="volPlus"){ AudioService.adjustVolume(it.kind==="volMinus"?-0.05: it.kind==="volPlus"?0.05:0) }
        else if(it.kind==="micMinus"||it.kind==="micSlider"||it.kind==="micPlus"){ if(AudioService.source&&AudioService.source.audio){ AudioService.source.audio.volume=Math.max(0,Math.min(1,AudioService.source.audio.volume+(it.kind==="micMinus"?-0.05: it.kind==="micPlus"?0.05:0))) } }
    }
    function ensureVisible(){
        const it = navItems[selIndex]
        if(!it) return
        if(it.kind==="sink" && sinksList) sinksList.positionViewAtIndex(it.idx, ListView.Contain)
        else if(it.kind==="source" && sourcesList) sourcesList.positionViewAtIndex(it.idx, ListView.Contain)
    }
    function activate(){
        const it = navItems[selIndex]
        if(!it) return
        if(it.kind==="mute") AudioService.toggleMute()
        else if(it.kind==="volMinus") AudioService.adjustVolume(-0.05)
        else if(it.kind==="volSlider") { }
        else if(it.kind==="volPlus") AudioService.adjustVolume(0.05)
        else if(it.kind==="sink") { const s = AudioService.sinkList[it.idx]; if(s) AudioService.setDefaultSink(s.id) }
        else if(it.kind==="micSwitch") { if(AudioService.source && AudioService.source.audio) AudioService.source.audio.muted = !AudioService.source.audio.muted }
        else if(it.kind==="micSlider") { }
        else if(it.kind==="source") { const s = AudioService.sourceList[it.idx]; if(s) AudioService.setDefaultSource(s.id) }
    }
    Connections { target: AudioService; function onSinkListChanged(){ updateNav() } function onSourceListChanged(){ updateNav() } }
    onIsOpenChanged: if(isOpen) { selIndex=0; AudioService.updateLists(); updateNav(); Qt.callLater(()=> mainCol.forceActiveFocus()) }
}