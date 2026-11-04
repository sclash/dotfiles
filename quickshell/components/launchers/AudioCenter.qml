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
    property bool filterActive: false
    property bool suppressUpdate: false
    property var navItems: []
    property int selIndex: 0
    property var filteredSinks: []
    property var filteredSources: []
    function open(){ isOpen=true }
    function close(){ isOpen=false; filterActive=false }
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
        clip: true
        Flickable {
            id: scrollView
            anchors.fill: parent
            anchors.margins: Theme.padL
            clip: true
            contentWidth: width
            contentHeight: mainCol.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar {
                policy: ScrollBar.AsNeeded
                width: 4
                background: Rectangle { color: "transparent" }
                contentItem: Rectangle { color: Theme.borderActive; radius: 2 }
            }
            ColumnLayout {
                id: mainCol
                width: scrollView.width
                spacing: Theme.gapM
                focus: true
                Text { text: "Audio"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fgMuted; font.capitalization: Font.AllUppercase; font.letterSpacing: 1.2 }
                Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border }

                Rectangle {
                    visible: root.filterActive
                    Layout.fillWidth: true
                    Layout.preferredHeight: 36
                    radius: Theme.roundingItem
                    color: Theme.bgActive
                    border.color: filterField.activeFocus ? Theme.borderSelected : Theme.border
                    border.width: 1
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.padM
                        anchors.rightMargin: Theme.padM
                        spacing: Theme.gapS
                        Text { text: Icons.search; font.family: Theme.fontFamily; font.pixelSize: 14; color: Theme.fgMuted }
                        TextField {
                            id: filterField
                            Layout.fillWidth: true
                            placeholderText: "filter devices…"
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
                            onTextChanged: if(!root.suppressUpdate) root.updateModels()
                            // Keep the field visible so the applied query stays legible;
                            // Esc clears it and returns the full device list.
                            onAccepted: { Qt.callLater(()=> mainCol.forceActiveFocus()) }
                        }
                    }
                }

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
                                border.width: 1
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
                Text {
                    visible: root.filteredSinks.length === 0
                    text: AudioService.sinkList.length === 0 ? "No output devices" : "No matching outputs"
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    color: Theme.fgDim
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                }
                ListView {
                    id: sinksList
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(160, contentHeight)
                    clip: true
                    spacing: 4
                    model: root.filteredSinks
                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        width: sinksList.width
                        height: 44
                        radius: Theme.roundingItem
                        readonly property bool isSel: { const it = root.navItems[root.selIndex]; return it !== undefined && it.kind === "sink" && it.idx === index }
                        readonly property bool active: AudioService.sink !== null && modelData.id === AudioService.sink.id
                        color: isSel ? Theme.bgSelected : (sinkMA.containsMouse ? Theme.bgHover : "transparent")
                        border.color: isSel ? Theme.borderSelected : "transparent"
                        border.width: 1
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Theme.padM
                            anchors.rightMargin: Theme.padM
                            spacing: Theme.gapM
                            Text { text: Icons.audioVolume; font.family: Theme.fontFamily; font.pixelSize: 14; color: active ? Theme.fgBright : Theme.fgMuted }
                            Text { text: modelData.description || modelData.name; font.family: Theme.fontFamily; font.pixelSize: 13; color: active ? Theme.fgBright : Theme.fg; Layout.fillWidth: true; elide: Text.ElideRight }
                            Text { text: modelData.audio ? Math.round(modelData.audio.volume*100) + "%" : ""; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fgMuted }
                            Text { visible: active; text: Icons.check; color: Theme.success; font.family: Theme.fontFamily; font.pixelSize: 14 }
                        }
                        MouseArea { id: sinkMA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: AudioService.setDefaultSink(modelData.id) }
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
                                border.width: 1
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
                            MouseArea { id: micMinusMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.adjustNode(AudioService.source, -0.05) }
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
                            MouseArea { id: micPlusMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.adjustNode(AudioService.source, 0.05) }
                        }
                    }
                }

                Text { text: "Sources"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fgMuted }
                Text {
                    visible: root.filteredSources.length === 0
                    text: AudioService.sourceList.length === 0 ? "No input devices" : "No matching sources"
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    color: Theme.fgDim
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                }
                ListView {
                    id: sourcesList
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(160, contentHeight)
                    clip: true
                    spacing: 4
                    model: root.filteredSources
                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        width: sourcesList.width
                        height: 44
                        radius: Theme.roundingItem
                        readonly property bool isSel: { const it = root.navItems[root.selIndex]; return it !== undefined && it.kind === "source" && it.idx === index }
                        readonly property bool active: AudioService.source !== null && modelData.id === AudioService.source.id
                        color: isSel ? Theme.bgSelected : (sourceMA.containsMouse ? Theme.bgHover : "transparent")
                        border.color: isSel ? Theme.borderSelected : "transparent"
                        border.width: 1
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Theme.padM
                            anchors.rightMargin: Theme.padM
                            spacing: Theme.gapM
                            Text { text: Icons.audio; font.family: Theme.fontFamily; font.pixelSize: 14; color: active ? Theme.fgBright : Theme.fgMuted }
                            Text { text: modelData.description || modelData.name; font.family: Theme.fontFamily; font.pixelSize: 13; color: active ? Theme.fgBright : Theme.fg; Layout.fillWidth: true; elide: Text.ElideRight }
                            Text { text: modelData.audio ? Math.round(modelData.audio.volume*100) + "%" : ""; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fgMuted }
                            Text { visible: active; text: Icons.check; color: Theme.success; font.family: Theme.fontFamily; font.pixelSize: 14 }
                        }
                        MouseArea { id: sourceMA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: AudioService.setDefaultSource(modelData.id) }
                    }
                }

                Text { text: "j/k · Enter select · h/l volume · / filter · m mute · Esc close"; font.family: Theme.fontFamily; font.pixelSize: 10; color: Theme.fgDim; Layout.alignment: Qt.AlignHCenter }
            }
        }
        Keys.onPressed: (e)=>{
            if(e.key===Qt.Key_Escape) {
                if(root.filterActive){ root.filterActive=false; root.clearFilter(); mainCol.forceActiveFocus(); e.accepted=true }
                else root.close()
            }
            else if(e.key===Qt.Key_J || e.key===Qt.Key_Down) { root.moveSel(1); e.accepted=true }
            else if(e.key===Qt.Key_K || e.key===Qt.Key_Up) { root.moveSel(-1); e.accepted=true }
            else if(e.key===Qt.Key_H || e.key===Qt.Key_Left) { root.adjustSel(-1); e.accepted=true }
            else if(e.key===Qt.Key_L || e.key===Qt.Key_Right) { root.adjustSel(1); e.accepted=true }
            else if(e.key===Qt.Key_Return || e.key===Qt.Key_Enter) { root.activate(); e.accepted=true }
            else if(e.key===Qt.Key_M) { AudioService.toggleMute(); e.accepted=true }
            else if(e.text==="/") { root.filterActive=true; filterField.forceActiveFocus(); e.accepted=true }
        }
    }

    function clearFilter(){
        suppressUpdate = true
        filterField.text = ""
        suppressUpdate = false
        updateModels()
    }
    function updateModels(){
        const q = filterField.text.trim().toLowerCase()
        let sk = AudioService.sinkList || []
        let so = AudioService.sourceList || []
        if(q){
            sk = sk.filter(n => ((n.description || n.name || "").toLowerCase().indexOf(q) !== -1))
            so = so.filter(n => ((n.description || n.name || "").toLowerCase().indexOf(q) !== -1))
        }
        filteredSinks = sk
        filteredSources = so
        const items=[]
        items.push({kind:"mute"})
        items.push({kind:"volMinus"})
        items.push({kind:"volSlider"})
        items.push({kind:"volPlus"})
        for(let i=0;i<sk.length;i++) items.push({kind:"sink", idx:i})
        items.push({kind:"micSwitch"})
        items.push({kind:"micMinus"})
        items.push({kind:"micSlider"})
        items.push({kind:"micPlus"})
        for(let i=0;i<so.length;i++) items.push({kind:"source", idx:i})
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
    function adjustNode(n, step){
        if(n && n.audio) n.audio.volume = Math.max(0, Math.min(1, n.audio.volume + step))
    }
    function adjustSel(delta){
        const step = delta < 0 ? -0.05 : 0.05
        const it = navItems[selIndex]
        if(!it) return
        if(it.kind==="sink") root.adjustNode(filteredSinks[it.idx], step)
        else if(it.kind==="source") root.adjustNode(filteredSources[it.idx], step)
        else if(it.kind==="micMinus"||it.kind==="micSlider"||it.kind==="micPlus") root.adjustNode(AudioService.source, step)
        else if(it.kind==="volMinus"||it.kind==="volSlider"||it.kind==="volPlus") root.adjustNode(AudioService.sink, step)
    }
    function anchorFor(kind){
        if(kind==="mute") return muteSwitch
        if(kind==="volMinus") return volMinus
        if(kind==="volSlider") return volSlider
        if(kind==="volPlus") return volPlus
        if(kind==="micSwitch") return micSwitch
        if(kind==="micMinus") return micMinus
        if(kind==="micSlider") return micSlider
        if(kind==="micPlus") return micPlus
        return null
    }
    function ensureVisible(){
        const it = navItems[selIndex]
        if(!it) return
        if(it.kind==="sink" && sinksList){
            sinksList.positionViewAtIndex(it.idx, ListView.Contain)
            Qt.callLater(()=> scrollToAnchor(sinksList))
            return
        }
        if(it.kind==="source" && sourcesList){
            sourcesList.positionViewAtIndex(it.idx, ListView.Contain)
            Qt.callLater(()=> scrollToAnchor(sourcesList))
            return
        }
        const anchor = anchorFor(it.kind)
        if(anchor) Qt.callLater(()=> scrollToAnchor(anchor))
    }
    function scrollToAnchor(item){
        if(!item || !item.visible) return
        const targetY = item.mapToItem(mainCol, 0, 0).y
        const viewH = scrollView.height
        const maxY = Math.max(0, scrollView.contentHeight - viewH)
        if(targetY < scrollView.contentY) scrollView.contentY = Math.max(0, targetY - Theme.gapM)
        else if(targetY + item.height > scrollView.contentY + viewH) scrollView.contentY = Math.min(maxY, targetY + item.height + Theme.gapM - viewH)
    }
    function activate(){
        const it = navItems[selIndex]
        if(!it) return
        if(it.kind==="mute") AudioService.toggleMute()
        else if(it.kind==="volMinus") root.adjustNode(AudioService.sink, -0.05)
        else if(it.kind==="volPlus") root.adjustNode(AudioService.sink, 0.05)
        else if(it.kind==="sink") { const s = filteredSinks[it.idx]; if(s) AudioService.setDefaultSink(s.id) }
        else if(it.kind==="micSwitch") { if(AudioService.source && AudioService.source.audio) AudioService.source.audio.muted = !AudioService.source.audio.muted }
        else if(it.kind==="micMinus") root.adjustNode(AudioService.source, -0.05)
        else if(it.kind==="micPlus") root.adjustNode(AudioService.source, 0.05)
        else if(it.kind==="source") { const s = filteredSources[it.idx]; if(s) AudioService.setDefaultSource(s.id) }
    }
    Connections { target: AudioService; function onSinkListChanged(){ root.updateModels() } function onSourceListChanged(){ root.updateModels() } }
    Component.onCompleted: updateModels()
    onIsOpenChanged: if(isOpen) {
        filterActive = false
        suppressUpdate = true
        filterField.text = ""
        suppressUpdate = false
        selIndex = 0
        AudioService.updateLists()
        updateModels()
        Qt.callLater(()=> mainCol.forceActiveFocus())
    }
}
