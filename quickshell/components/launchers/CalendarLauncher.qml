import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../../theme"

WlrLayershell {
    id: root
    property bool isOpen: false
    property int cursorYear: 1970
    property int cursorMonth: 0
    property int cursorDay: 1
    property int todayYear: 1970
    property int todayMonth: 0
    property int todayDay: 1
    property string copyNote: ""

    function open() { refreshToday(); gotoToday(); copyNote = ""; isOpen = true }
    function close() { isOpen = false; copyNote = ""; copyTimer.stop() }
    function toggle() { if (isOpen) close(); else open() }

    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    visible: isOpen
    keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore
    Rectangle { anchors.fill: parent; color: Theme.overlay; MouseArea { anchors.fill: parent; onClicked: root.close() } }

    // Keep the "today" highlight correct if the launcher stays open past midnight.
    Timer {
        interval: 30000
        running: root.isOpen
        repeat: true
        onTriggered: root.refreshToday()
    }
    Timer {
        id: copyTimer
        interval: 1500
        repeat: false
        onTriggered: root.copyNote = ""
    }

    Rectangle {
        id: card
        width: 480
        height: Math.min(560, mainCol.implicitHeight + Theme.padL * 2)
        anchors.centerIn: parent
        radius: Theme.roundingLauncher
        color: Theme.bgLauncher
        border.width: 1
        border.color: Theme.borderActive
        clip: true

        ColumnLayout {
            id: mainCol
            anchors.fill: parent
            anchors.margins: Theme.padL
            spacing: Theme.gapM
            focus: true

            Text {
                text: "Calendar"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.fgMuted
                font.capitalization: Font.AllUppercase
                font.letterSpacing: 1.2
            }
            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border }

            // Month / year navigation header
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.gapS

                Rectangle {
                    width: 32; height: 32
                    radius: Theme.roundingItem
                    color: yearPrevMA.containsMouse ? Theme.bgHover : "transparent"
                    border.color: Theme.border
                    border.width: 1
                    Text { anchors.centerIn: parent; text: "«"; font.family: Theme.fontFamily; font.pixelSize: 14; color: Theme.fgMuted }
                    MouseArea {
                        id: yearPrevMA
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { root.addYears(-1); mainCol.forceActiveFocus() }
                    }
                }
                Rectangle {
                    width: 32; height: 32
                    radius: Theme.roundingItem
                    color: monthPrevMA.containsMouse ? Theme.bgHover : "transparent"
                    border.color: Theme.border
                    border.width: 1
                    Text { anchors.centerIn: parent; text: Icons.chevronLeft; font.family: Theme.fontFamily; font.pixelSize: 14; color: Theme.fg }
                    MouseArea {
                        id: monthPrevMA
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { root.addMonths(-1); mainCol.forceActiveFocus() }
                    }
                }
                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: root.monthLabel()
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeLauncher
                    font.weight: Theme.fontWeightMedium
                    color: Theme.fgBright
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { root.gotoToday(); mainCol.forceActiveFocus() }
                    }
                }
                Rectangle {
                    width: 32; height: 32
                    radius: Theme.roundingItem
                    color: monthNextMA.containsMouse ? Theme.bgHover : "transparent"
                    border.color: Theme.border
                    border.width: 1
                    Text { anchors.centerIn: parent; text: Icons.chevronRight; font.family: Theme.fontFamily; font.pixelSize: 14; color: Theme.fg }
                    MouseArea {
                        id: monthNextMA
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { root.addMonths(1); mainCol.forceActiveFocus() }
                    }
                }
                Rectangle {
                    width: 32; height: 32
                    radius: Theme.roundingItem
                    color: yearNextMA.containsMouse ? Theme.bgHover : "transparent"
                    border.color: Theme.border
                    border.width: 1
                    Text { anchors.centerIn: parent; text: "»"; font.family: Theme.fontFamily; font.pixelSize: 14; color: Theme.fgMuted }
                    MouseArea {
                        id: yearNextMA
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { root.addYears(1); mainCol.forceActiveFocus() }
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: root.selectedLabel()
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.fgMuted
                elide: Text.ElideRight
            }

            // Weekday header (Monday-first)
            GridLayout {
                Layout.fillWidth: true
                columns: 7
                columnSpacing: 4
                rowSpacing: 4
                Repeater {
                    model: ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
                    Text {
                        required property string modelData
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: modelData
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        font.weight: Theme.fontWeightMedium
                        color: Theme.fgMuted
                    }
                }
            }

            // Month grid — always 6 rows, view follows the cursor
            GridLayout {
                id: grid
                Layout.fillWidth: true
                columns: 7
                columnSpacing: 4
                rowSpacing: 4
                Repeater {
                    model: 42
                    Rectangle {
                        required property int index
                        property var cell: root.cellAt(index)
                        property bool inMonth: cell.inMonth
                        property bool selected: cell.y === root.cursorYear && cell.m === root.cursorMonth && cell.d === root.cursorDay
                        property bool today: cell.y === root.todayYear && cell.m === root.todayMonth && cell.d === root.todayDay
                        Layout.fillWidth: true
                        Layout.preferredHeight: 40
                        radius: Theme.roundingItem
                        color: selected ? Theme.bgSelected : (dayMA.containsMouse ? Theme.bgHover : "transparent")
                        border.width: selected ? 2 : 1
                        border.color: selected ? Theme.borderSelected : (today ? Theme.accent : Theme.border)
                        Behavior on border.color { ColorAnimation { duration: Theme.durationFast } }
                        Text {
                            anchors.centerIn: parent
                            text: String(cell.d)
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            font.weight: (selected || today) ? Theme.fontWeightMedium : Theme.fontWeightNormal
                            color: !inMonth ? Theme.fgDim : (today ? Theme.accent : (selected ? Theme.fgBright : Theme.fg))
                        }
                        MouseArea {
                            id: dayMA
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { root.setCursor(cell.y, cell.m, cell.d); mainCol.forceActiveFocus() }
                            onWheel: (wheel) => {
                                if (wheel.angleDelta.y > 0) root.addMonths(-1)
                                else if (wheel.angleDelta.y < 0) root.addMonths(1)
                            }
                        }
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: root.copyNote !== "" ? root.copyNote : "h/l day · j/k week · H/L month · J/K year · t today · Enter copy · Esc close"
                font.family: Theme.fontFamily
                font.pixelSize: 10
                color: root.copyNote !== "" ? Theme.accent : Theme.fgDim
                wrapMode: Text.Wrap
            }

            Keys.onPressed: (e) => {
                const shift = (e.modifiers & Qt.ShiftModifier) !== 0
                if (e.key === Qt.Key_Escape) { root.close(); e.accepted = true }
                else if (e.key === Qt.Key_H || e.key === Qt.Key_Left) {
                    if (e.key === Qt.Key_Left || !shift) root.addDays(-1)
                    else root.addMonths(-1)
                    e.accepted = true
                } else if (e.key === Qt.Key_L || e.key === Qt.Key_Right) {
                    if (e.key === Qt.Key_Right || !shift) root.addDays(1)
                    else root.addMonths(1)
                    e.accepted = true
                } else if (e.key === Qt.Key_J || e.key === Qt.Key_Down) {
                    if (e.key === Qt.Key_Down || !shift) root.addDays(7)
                    else root.addYears(-1)
                    e.accepted = true
                } else if (e.key === Qt.Key_K || e.key === Qt.Key_Up) {
                    if (e.key === Qt.Key_Up || !shift) root.addDays(-7)
                    else root.addYears(1)
                    e.accepted = true
                } else if (e.key === Qt.Key_T) { root.gotoToday(); e.accepted = true }
                else if (e.key === Qt.Key_Home) { root.setCursor(root.cursorYear, root.cursorMonth, 1); e.accepted = true }
                else if (e.key === Qt.Key_End) { root.setCursor(root.cursorYear, root.cursorMonth, root.daysIn(root.cursorYear, root.cursorMonth)); e.accepted = true }
                else if (e.key === Qt.Key_PageUp) {
                    if (shift) root.addYears(-1)
                    else root.addMonths(-1)
                    e.accepted = true
                } else if (e.key === Qt.Key_PageDown) {
                    if (shift) root.addYears(1)
                    else root.addMonths(1)
                    e.accepted = true
                } else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { root.copyIso(); e.accepted = true }
            }
            Component.onCompleted: forceActiveFocus()
        }
        onVisibleChanged: if (visible) mainCol.forceActiveFocus()
    }

    onIsOpenChanged: {
        if (isOpen) Qt.callLater(() => mainCol.forceActiveFocus())
    }

    // ---- date logic (pure JS, no process) ----
    function daysIn(y, m) {
        return new Date(y, m + 1, 0).getDate()
    }
    function setCursor(y, m, d) {
        cursorYear = y
        cursorMonth = m
        cursorDay = Math.min(d, daysIn(y, m))
    }
    function addDays(n) {
        const d = new Date(cursorYear, cursorMonth, cursorDay + n)
        setCursor(d.getFullYear(), d.getMonth(), d.getDate())
    }
    function addMonths(n) {
        const total = cursorYear * 12 + cursorMonth + n
        const y = Math.floor(total / 12)
        const m = ((total % 12) + 12) % 12
        setCursor(y, m, cursorDay)
    }
    function addYears(n) {
        setCursor(cursorYear + n, cursorMonth, cursorDay)
    }
    function refreshToday() {
        const n = new Date()
        todayYear = n.getFullYear()
        todayMonth = n.getMonth()
        todayDay = n.getDate()
    }
    function gotoToday() {
        refreshToday()
        setCursor(todayYear, todayMonth, todayDay)
    }
    function monthLabel() {
        return Qt.formatDateTime(new Date(cursorYear, cursorMonth, 1), "MMMM yyyy")
    }
    function isoOf(y, m, d) {
        const mm = String(m + 1).padStart(2, "0")
        const dd = String(d).padStart(2, "0")
        return y + "-" + mm + "-" + dd
    }
    function selectedLabel() {
        const long = Qt.formatDateTime(new Date(cursorYear, cursorMonth, cursorDay), "ddd MMM dd, yyyy")
        return long + "  ·  " + isoOf(cursorYear, cursorMonth, cursorDay)
    }
    function cellAt(i) {
        // Monday-first offset of the 1st of the cursor month
        const first = (new Date(cursorYear, cursorMonth, 1).getDay() + 6) % 7
        const dim = daysIn(cursorYear, cursorMonth)
        if (i < first) {
            const pm = cursorMonth === 0 ? 11 : cursorMonth - 1
            const py = cursorMonth === 0 ? cursorYear - 1 : cursorYear
            const pdim = daysIn(py, pm)
            return { y: py, m: pm, d: pdim - first + 1 + i, inMonth: false }
        }
        const day = i - first + 1
        if (day <= dim)
            return { y: cursorYear, m: cursorMonth, d: day, inMonth: true }
        const nm = cursorMonth === 11 ? 0 : cursorMonth + 1
        const ny = cursorMonth === 11 ? cursorYear + 1 : cursorYear
        return { y: ny, m: nm, d: day - dim, inMonth: false }
    }
    function copyIso() {
        const iso = isoOf(cursorYear, cursorMonth, cursorDay)
        copyProc.command = ["sh", "-c", "printf '%s' '" + iso + "' | wl-copy"]
        copyProc.running = true
        copyNote = "Copied " + iso
        copyTimer.restart()
    }

    property Process copyProc: Process {}
}
