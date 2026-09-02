import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../../theme"
import "../../services"

WlrLayershell {
    id: root
    property bool isOpen: false
    function open(){ isOpen=true }
    function close(){ isOpen=false }
    function toggle(){ if(isOpen) close(); else open() }

    anchors { top:true; bottom:true; left:true; right:true }
    color: "transparent"
    visible: isOpen
    keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore
    Rectangle { anchors.fill: parent; color: Theme.overlay; MouseArea { anchors.fill: parent; onClicked: root.close() } }
    onIsOpenChanged: if(isOpen) { notifList.currentIndex=0; notifList.positionViewAtIndex(0, ListView.Beginning); notifList.forceActiveFocus() }

    Rectangle {
        width: 620
        height: Math.min(600, mainCol.implicitHeight + Theme.padL*2)
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
            RowLayout {
                Layout.fillWidth: true
                Text { text: "Notifications"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fgMuted; font.capitalization: Font.AllUppercase; font.letterSpacing: 1.2; Layout.fillWidth: true }
                Rectangle {
                    width: 90; height: 32
                    radius: Theme.roundingItem
                    color: NotifService.dnd ? Theme.warning : Theme.bgHover
                    border.color: Theme.border
                    border.width: 1
                    Text { anchors.centerIn: parent; text: NotifService.dnd ? "Unsilence" : "Silence"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fg }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: NotifService.toggleDnd() }
                }
                Rectangle {
                    width: 90; height: 32
                    radius: Theme.roundingItem
                    color: Theme.bgHover
                    border.color: Theme.critical
                    border.width: 1
                    Text { anchors.centerIn: parent; text: "Clear all"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.critical }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: NotifService.clearHistory() }
                }
            }
            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border }
            RowLayout {
                Layout.fillWidth: true
                visible: filterActive
                spacing: Theme.gapM
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 36
                    radius: Theme.roundingItem
                    color: Theme.bgActive
                    border.color: filterField.activeFocus ? Theme.borderSelected : Theme.border
                    border.width: 1
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.padM
                        Text { text: Icons.search; font.family: Theme.fontFamily; font.pixelSize: 14; color: Theme.fgMuted }
                        TextField {
                            id: filterField
                            Layout.fillWidth: true
                            placeholderText: "Filter…"
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            color: Theme.fg
                            placeholderTextColor: Theme.fgDim
                            background: null
                            onTextChanged: filteredHistory = filterHistory()
                        }
                    }
                }
            }
            ListView {
                id: notifList
                Layout.fillWidth: true
                Layout.preferredHeight: 380
                clip: true
                spacing: 8
                model: filteredHistory
                currentIndex: 0
                focus: true
delegate: Rectangle {
                    required property var modelData
                    required property int index
                    readonly property bool selected: ListView.isCurrentItem
                    width: notifList.width
                    height: bodyCol.implicitHeight + Theme.padM*2
                    radius: Theme.roundingItem
                    // color: cardHover.containsMouse ? Theme.bgHover : Theme.bgBarAlt
                    color:  Theme.bgHover 
                    // border.width: 1
		    border.width: selected ? 3 : 1
                    border.color: selected ? Theme.borderSelected : Theme.border
                    MouseArea {
                        id: cardHover
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.NoButton
                    }
                    ColumnLayout {
                        id: bodyCol
                        anchors.fill: parent
                        anchors.margins: Theme.padM
                        spacing: 4
                        RowLayout {
                            Layout.fillWidth: true
                            Text { text: modelData.appName; font.family: Theme.fontFamily; font.pixelSize: 10; color: Theme.fgMuted; font.weight: Theme.fontWeightMedium }
                            Item { Layout.fillWidth: true }
                            Text { text: Qt.formatDateTime(modelData.timestamp, "hh:mm"); font.family: Theme.fontFamily; font.pixelSize: 10; color: Theme.fgDim }
                        }
                        Text { text: modelData.summary; font.family: Theme.fontFamily; font.pixelSize: 13; font.weight: Theme.fontWeightMedium; color: Theme.fg; wrapMode: Text.Wrap; Layout.fillWidth: true }
                        Text { text: modelData.body; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fgMuted; wrapMode: Text.Wrap; maximumLineCount: 3; elide: Text.ElideRight; Layout.fillWidth: true }
                        RowLayout {
                            spacing: Theme.gapS
                            Repeater {
                                model: modelData.actions ? modelData.actions.slice(0,3) : []
                                delegate: Rectangle {
                                    required property var modelData
                                    width: 80; height: 26
                                    radius: 6
                                    color: Theme.bgActive
                                    border.color: Theme.border
                                    border.width: 1
                                    Text { anchors.centerIn: parent; text: modelData.text || modelData.identifier || "Action"; font.pixelSize: 11; color: Theme.fg; font.family: Theme.fontFamily }
                                    MouseArea { anchors.fill: parent; onClicked: try { modelData.invoke() } catch(e) {} }
                                }
                            }
                            Rectangle {
                                width: 70; height: 26
                                radius: 6
                                color: Theme.bgActive
                                border.color: Theme.border
                                border.width: 1
                                Text { anchors.centerIn: parent; text: "Dismiss"; font.pixelSize: 11; color: Theme.fg; font.family: Theme.fontFamily }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: NotifService.dismiss(index) }
                            }
                        }
                    }
                }
                Keys.onPressed: (e)=>{
                    if(e.key===Qt.Key_J || e.key===Qt.Key_Down) { currentIndex=Math.min(count-1, currentIndex+1); positionViewAtIndex(currentIndex, ListView.Contain); e.accepted=true }
                    else if(e.key===Qt.Key_K || e.key===Qt.Key_Up) { currentIndex=Math.max(0, currentIndex-1); positionViewAtIndex(currentIndex, ListView.Contain); e.accepted=true }
                    else if(e.key===Qt.Key_D || e.key===Qt.Key_Delete) { NotifService.dismiss(currentIndex); e.accepted=true }
                    else if(e.key===Qt.Key_Return || e.key===Qt.Key_Enter) {
                        const m=filteredHistory[currentIndex]
                        if(m && m.notification) {
                            const acts = m.notification.actions
                            if(acts && acts.length>0) {
                                try { acts[0].invoke(); NotifService.dismiss(currentIndex) } catch(err) { NotifService.dismiss(currentIndex) }
                            } else NotifService.dismiss(currentIndex)
                        } else NotifService.dismiss(currentIndex)
                        e.accepted=true
                    }
                }
            }
            Text {
                visible: NotifService.history.length===0
                text: Icons.notification + "  No notifications — you are all caught up"
                font.family: Theme.fontFamily
                font.pixelSize: 13
                color: Theme.fgMuted
                Layout.alignment: Qt.AlignHCenter
            }
            Text { visible: NotifService.dnd; text: "Silenced — new notifications are dimmed"; color: Theme.fgDim; font.family: Theme.fontFamily; font.pixelSize: 11; wrapMode: Text.Wrap; Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter }
            Text { text: "/ filter · j/k move · d dismiss · Enter open · c clear · Ctrl+s silence · Esc close"; font.family: Theme.fontFamily; font.pixelSize: 10; color: Theme.fgDim; Layout.alignment: Qt.AlignHCenter }
        }
        Keys.onPressed: (e)=>{
            if(e.key===Qt.Key_Escape) {
                if(filterActive){ filterActive=false; filterField.text=""; notifList.forceActiveFocus(); e.accepted=true }
                else root.close()
            }
            else if(e.text==="/") { filterActive=true; filterField.forceActiveFocus(); e.accepted=true }
            else if(e.key===Qt.Key_C) { NotifService.clearHistory(); e.accepted=true }
            else if((e.key===Qt.Key_K && e.modifiers & Qt.ControlModifier) || e.key===Qt.Key_C) { NotifService.clearHistory(); e.accepted=true }
            else if(e.key===Qt.Key_S && e.modifiers & Qt.ControlModifier) { NotifService.toggleDnd(); e.accepted=true }
            else if(e.key===Qt.Key_J || e.key===Qt.Key_K || e.key===Qt.Key_Up || e.key===Qt.Key_Down) {
                notifList.forceActiveFocus()
                // forward to list
                if(e.key===Qt.Key_J || e.key===Qt.Key_Down) { notifList.currentIndex=Math.min(notifList.count-1, notifList.currentIndex+1); notifList.positionViewAtIndex(notifList.currentIndex, ListView.Contain); e.accepted=true }
                else if(e.key===Qt.Key_K || e.key===Qt.Key_Up) { notifList.currentIndex=Math.max(0, notifList.currentIndex-1); notifList.positionViewAtIndex(notifList.currentIndex, ListView.Contain); e.accepted=true }
            }
        }
    }
    property bool filterActive: false
    property var filteredHistory: NotifService.history.slice(0,50)
    function filterHistory(){
        const q=filterField.text.toLowerCase()
        if(!q) return NotifService.history.slice(0,50)
        return NotifService.history.filter(n=> (n.appName && n.appName.toLowerCase().indexOf(q)!==-1) || (n.summary && n.summary.toLowerCase().indexOf(q)!==-1) || (n.body && n.body.toLowerCase().indexOf(q)!==-1))
    }
    Connections { target: NotifService; function onHistoryChanged(){ filteredHistory = filterHistory() } }
}
