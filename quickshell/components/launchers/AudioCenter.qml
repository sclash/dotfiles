import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire
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
    onIsOpenChanged: if(isOpen) { AudioService.updateLists(); Qt.callLater(()=> mainCol.forceActiveFocus()) }

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
            Rectangle {
                Layout.fillWidth: true
                height: outCol.implicitHeight + Theme.padM*2
                radius: Theme.roundingItem
                color: Theme.bgActive
                border.color: Theme.border
                border.width: 1
                ColumnLayout {
                    id: outCol
                    anchors.fill: parent
                    anchors.margins: Theme.padM
                    spacing: Theme.gapS
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.gapM
                        Rectangle {
                            width: 40; height: 40
                            radius: 8
                            color: AudioService.muted ? Theme.bgCritical : Theme.fg
                            Text { anchors.centerIn: parent; text: AudioService.muted ? Icons.audioMuted : Icons.audioVolume; font.family: Theme.fontFamily; font.pixelSize: 18; color: Theme.bgBar }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            Text {
                                text: AudioService.hasSink ? (AudioService.sinkName || "Unknown") : "No output device"
                                font.family: Theme.fontFamily
                                font.pixelSize: 13
                                font.weight: Theme.fontWeightMedium
                                color: AudioService.hasSink ? Theme.fg : Theme.fgDim
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                            }
                            Text { text: AudioService.hasSink ? AudioService.volume + "%" + (AudioService.muted ? " · muted" : "") : ""; color: Theme.fgMuted; font.family: Theme.fontFamily; font.pixelSize: 11 }
                        }
                        Switch { checked: !AudioService.muted; onClicked: AudioService.toggleMute() }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.gapM
                        Text { text: "−"; font.pixelSize: 14; color: Theme.fgMuted; MouseArea { anchors.fill: parent; onClicked: AudioService.adjustVolume(-0.05) } }
                        Slider {
                            id: volSlider
                            Layout.fillWidth: true
                            from: 0; to: 1
                            value: (AudioService.sink && AudioService.sink.audio) ? AudioService.sink.audio.volume : 0
                            onMoved: AudioService.setVolume(value)
                            // Keep slider in sync when volume changes externally (wheel, Pipewire)
                            Connections {
                                target: AudioService.sink && AudioService.sink.audio ? AudioService.sink.audio : null
                                function onVolumeChanged(){ volSlider.value = target.volume }
                                function onVolumesChanged(){ volSlider.value = target.volume }
                            }
                            background: Rectangle { implicitHeight: 6; radius: 3; color: Theme.border; Rectangle { width: volSlider.visualPosition*parent.width; height: parent.height; radius: 3; color: Theme.accent } }
                            handle: Rectangle { x: volSlider.leftPadding + volSlider.visualPosition*(volSlider.availableWidth - width); y: volSlider.topPadding + volSlider.availableHeight/2 - height/2; width: 16; height: 16; radius: 8; color: Theme.accent; border.color: Theme.accent; border.width: 2 }
                        }
                        Text { text: "+"; font.pixelSize: 14; color: Theme.fgMuted; MouseArea { anchors.fill: parent; onClicked: AudioService.adjustVolume(0.05) } }
                    }
                }
            }

            Text { text: "Sinks"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fgMuted }
            ListView {
                id: sinksList
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(140, contentHeight)
                clip: true
                spacing: 4
                model: AudioService.sinkList
                delegate: Rectangle {
                    required property var modelData
                    width: sinksList.width
                    height: 44
                    radius: Theme.roundingItem
                    color: (AudioService.sink && modelData.id === AudioService.sink.id) ? Theme.bgActive : (ma.containsMouse ? Theme.bgHover : "transparent")
                    border.color: (AudioService.sink && modelData.id === AudioService.sink.id) ? Theme.fg : "transparent"
                    border.width: 1
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.padM
                        anchors.rightMargin: Theme.padM
                        spacing: Theme.gapM
                        Text { text: Icons.audioVolume; font.family: Theme.fontFamily; font.pixelSize: 16; color: (AudioService.sink && modelData.id === AudioService.sink.id) ? Theme.fg : Theme.fgMuted }
                        Text { text: modelData.description || modelData.name; font.family: Theme.fontFamily; font.pixelSize: 13; color: Theme.fg; Layout.fillWidth: true; elide: Text.ElideRight }
                        Text { visible: AudioService.sink && modelData.id === AudioService.sink.id; text: Icons.check; color: Theme.success; font.family: Theme.fontFamily; font.pixelSize: 14 }
                    }
                    MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; onClicked: AudioService.setDefaultSink(modelData.id) }
                }
            }

            Text { text: "Input"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fgMuted }
            Rectangle {
                Layout.fillWidth: true
                height: inCol.implicitHeight + Theme.padM*2
                radius: Theme.roundingItem
                color: Theme.bgActive
                border.color: Theme.border
                border.width: 1
                ColumnLayout {
                    id: inCol
                    anchors.fill: parent
                    anchors.margins: Theme.padM
                    Text {
                        text: AudioService.hasSource ? (AudioService.source.description || AudioService.source.name) : "No input device"
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                        color: AudioService.hasSource ? Theme.fg : Theme.fgDim
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Slider {
                            id: micSlider
                            Layout.fillWidth: true
                            from: 0; to: 1
                            value: (AudioService.source && AudioService.source.audio) ? AudioService.source.audio.volume : 0
                            onMoved: if(AudioService.source && AudioService.source.audio) AudioService.source.audio.volume = value
                            Connections {
                                target: AudioService.source && AudioService.source.audio ? AudioService.source.audio : null
                                function onVolumeChanged(){ micSlider.value = target.volume }
                                function onVolumesChanged(){ micSlider.value = target.volume }
                            }
                            background: Rectangle { implicitHeight: 6; radius: 3; color: Theme.border; Rectangle { width: micSlider.visualPosition*parent.width; height: parent.height; radius: 3; color: Theme.accent } }
                            handle: Rectangle { x: micSlider.leftPadding + micSlider.visualPosition*(micSlider.availableWidth - width); y: micSlider.topPadding + micSlider.availableHeight/2 - height/2; width: 16; height: 16; radius: 8; color: Theme.accent; border.color: Theme.accent; border.width: 2 }
                        }
                        Switch { checked: AudioService.source && AudioService.source.audio ? !AudioService.source.audio.muted : false; onClicked: if(AudioService.source && AudioService.source.audio) AudioService.source.audio.muted = !AudioService.source.audio.muted }
                    }
                }
            }
            ListView {
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(110, contentHeight)
                clip: true
                spacing: 4
                model: AudioService.sourceList
                delegate: Rectangle {
                    required property var modelData
                    width: parent.width
                    height: 40
                    radius: Theme.roundingItem
                    color: (AudioService.source && modelData.id===AudioService.source.id) ? Theme.bgActive : "transparent"
                    border.color: (AudioService.source && modelData.id===AudioService.source.id) ? Theme.fg : "transparent"
                    border.width: 1
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.padM
                        Text { text: Icons.audio; font.family: Theme.fontFamily; font.pixelSize: 14; color: Theme.fgMuted }
                        Text { text: modelData.description || modelData.name; font.family: Theme.fontFamily; font.pixelSize: 13; color: Theme.fg; Layout.fillWidth: true; elide: Text.ElideRight }
                        Text { visible: AudioService.source && modelData.id===AudioService.source.id; text: Icons.check; color: Theme.success; font.family: Theme.fontFamily }
                    }
                    MouseArea { anchors.fill: parent; onClicked: AudioService.setDefaultSource(modelData.id) }
                }
            }
            Text { text: "h/l adjust · j/k move · Esc close"; font.family: Theme.fontFamily; font.pixelSize: 10; color: Theme.fgDim; Layout.alignment: Qt.AlignHCenter }
        }
        Keys.onPressed: (e)=>{
            if(e.key===Qt.Key_Escape) root.close()
            else if(e.key===Qt.Key_H || e.key===Qt.Key_Left) { AudioService.adjustVolume(-0.05); e.accepted=true }
            else if(e.key===Qt.Key_L || e.key===Qt.Key_Right) { AudioService.adjustVolume(0.05); e.accepted=true }
        }
    }
}
