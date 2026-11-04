import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../theme"

// Per-output settings view. Renders rows from the hardware descriptor and
// turns keys into service writes; the panel owns no processes.
Item {
    id: root

    property var monitor: ({})
    property var hardware: ({})
    property int selIndex: 0
    property bool pickerOpen: false
    property int pickerIndex: 0
    property var pickerOptions: []
    property string _monitorName: ""

    signal closeRequested()
    signal setBrightness(real percent)
    signal setTemperature(int kelvin)

    readonly property var brightness: (hardware && hardware.brightness) ? hardware.brightness : ({ available: false })
    readonly property var temperature: (hardware && hardware.temperature) ? hardware.temperature : ({ available: false })

    readonly property var rows: {
        const r = []
        if (root.brightness.available) r.push("brightness")
        if (root.temperature.available) r.push("temperature")
        return r
    }
    readonly property string brightnessBackend: {
        if (!root.brightness.available) return ""
        return root.brightness.backend === "gamma" ? "software" : root.brightness.backend
    }
    readonly property string unavailableHint: {
        if (!root.brightness.available && !root.temperature.available)
            return "No brightness or color temperature backend detected"
        if (!root.temperature.available)
            return "Color temperature unavailable — wl-gammarelay-rs not running"
        if (!root.brightness.available)
            return "Brightness unavailable — no backlight or DDC/CI"
        return ""
    }

    function currentKind() {
        return root.rows.length > 0 ? root.rows[Math.max(0, Math.min(root.selIndex, root.rows.length - 1))] : ""
    }
    function rowFor(kind) {
        return kind === "brightness" ? root.brightness : root.temperature
    }
    function reset() {
        root.selIndex = 0
        root.pickerOpen = false
        root.pickerIndex = 0
        root.pickerOptions = []
    }

    function moveSel(delta) {
        const n = root.rows.length
        if (n === 0) return
        root.selIndex = Math.max(0, Math.min(n - 1, root.selIndex + delta))
        Qt.callLater(() => {
            if (rowsList) rowsList.positionViewAtIndex(root.selIndex, ListView.Contain)
            root.forceActiveFocus()
        })
    }

    function adjust(delta) {
        const kind = root.currentKind()
        if (kind === "") return
        const hw = root.rowFor(kind)
        if (kind === "brightness") {
            root.setBrightness(hw.value + delta * 5)
        } else if (kind === "temperature") {
            root.setTemperature(hw.value + delta * 100)
        }
    }

    // Range rows are adjusted with h/l; the picker stack lands in Task 5.
    function activate() {
    }

    function back() {
        if (root.pickerOpen) {
            root.pickerOpen = false
            return
        }
        root.closeRequested()
    }

    function handleKey(event) {
        if (event.key === Qt.Key_Escape) { root.back(); return true }
        if (root.pickerOpen) {
            if (event.key === Qt.Key_J || event.key === Qt.Key_Down) {
                root.pickerIndex = Math.min(root.pickerOptions.length - 1, root.pickerIndex + 1)
                return true
            }
            if (event.key === Qt.Key_K || event.key === Qt.Key_Up) {
                root.pickerIndex = Math.max(0, root.pickerIndex - 1)
                return true
            }
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                root.activate()
                return true
            }
            return false
        }
        if (event.key === Qt.Key_J || event.key === Qt.Key_Down) { root.moveSel(1); return true }
        if (event.key === Qt.Key_K || event.key === Qt.Key_Up) { root.moveSel(-1); return true }
        if (event.key === Qt.Key_H || event.key === Qt.Key_Left) { root.adjust(-1); return true }
        if (event.key === Qt.Key_L || event.key === Qt.Key_Right) { root.adjust(1); return true }
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { root.activate(); return true }
        return false
    }

    function setRatio(kind, ratio) {
        const hw = root.rowFor(kind)
        const r = Math.max(0, Math.min(1, ratio))
        const v = hw.min + r * (hw.max - hw.min)
        if (kind === "brightness") root.setBrightness(Math.round(v))
        else if (kind === "temperature") root.setTemperature(Math.round(v / 100) * 100)
    }

    onMonitorChanged: {
        const name = root.monitor ? (root.monitor.name || "") : ""
        if (name !== root._monitorName) {
            root._monitorName = name
            root.reset()
        }
    }
    onRowsChanged: root.selIndex = Math.max(0, Math.min(root.selIndex, root.rows.length - 1))
    focus: true

    Rectangle {
        id: card
        width: 640
        height: Math.min(640, body.implicitHeight + Theme.padL * 2)
        anchors.centerIn: parent
        radius: Theme.roundingLauncher
        color: Theme.bgLauncher
        border.width: 1
        border.color: Theme.borderActive
        clip: true

        ColumnLayout {
            id: body
            anchors.fill: parent
            anchors.margins: Theme.padL
            spacing: Theme.gapM

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.gapS
                Text {
                    text: root.monitor.name || ""
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                    font.weight: Theme.fontWeightMedium
                    color: Theme.fg
                }
                Text {
                    readonly property string desc: root.monitor.description || root.monitor.make || ""
                    visible: desc.length > 0
                    text: "·"
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    color: Theme.fgDim
                }
                Text {
                    readonly property string desc: root.monitor.description || root.monitor.make || ""
                    text: desc
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    color: Theme.fgMuted
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                    Layout.maximumWidth: Number.POSITIVE_INFINITY
                }
                Text {
                    text: "Settings"
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    color: Theme.fgMuted
                    font.capitalization: Font.AllUppercase
                    font.letterSpacing: 1.2
                }
            }
            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border }

            ListView {
                id: rowsList
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(400, contentHeight)
                clip: true
                spacing: 4
                model: root.rows
                delegate: Rectangle {
                    id: row
                    required property string modelData
                    required property int index
                    readonly property var hw: root.rowFor(modelData)
                    readonly property bool isSel: index === root.selIndex
                    readonly property real ratio: {
                        const span = hw.max - hw.min
                        return span > 0 ? Math.max(0, Math.min(1, (hw.value - hw.min) / span)) : 0
                    }
                    width: rowsList.width
                    height: 68
                    radius: Theme.roundingItem
                    color: isSel ? Theme.bgSelected : Theme.bgActive
                    border.color: isSel ? Theme.accent : Theme.border
                    border.width: isSel ? 2 : 1

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.selIndex = row.index
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: Theme.padM
                        spacing: Theme.gapS

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.gapS
                            Text {
                                text: row.modelData === "brightness" ? Icons.eye : Icons.temp
                                font.family: Theme.fontFamily
                                font.pixelSize: 14
                                color: row.isSel ? Theme.fgBright : Theme.fgMuted
                            }
                            Text {
                                text: row.modelData === "brightness" ? "Brightness" : "Color temperature"
                                font.family: Theme.fontFamily
                                font.pixelSize: 13
                                color: Theme.fg
                                Layout.fillWidth: true
                            }
                            Text {
                                visible: row.modelData === "brightness"
                                text: root.brightnessBackend
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                                color: Theme.fgDim
                            }
                            Text {
                                text: row.modelData === "brightness"
                                    ? Math.round(row.hw.value) + "%"
                                    : Math.round(row.hw.value) + " K"
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                                font.weight: Theme.fontWeightMedium
                                color: Theme.fgBright
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.gapS

                            Rectangle {
                                width: 22; height: 22
                                radius: Theme.roundingItem
                                color: minusMouse.containsMouse ? Theme.bgHover : "transparent"
                                Text { anchors.centerIn: parent; text: "−"; font.family: Theme.fontFamily; font.pixelSize: 14; color: Theme.fgMuted }
                                MouseArea {
                                    id: minusMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: { root.selIndex = row.index; root.adjust(-1) }
                                }
                            }

                            Item {
                                Layout.fillWidth: true
                                implicitHeight: 20
                                Rectangle {
                                    id: track
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width
                                    height: 4
                                    radius: 2
                                    color: Theme.border
                                }
                                Rectangle {
                                    width: Math.max(0, Math.min(track.width, track.width * row.ratio))
                                    height: track.height
                                    radius: 2
                                    color: Theme.fgMuted
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                Rectangle {
                                    x: Math.max(0, Math.min(track.width - width, track.width * row.ratio - width / 2))
                                    width: 10; height: 10
                                    radius: 5
                                    color: Theme.fg
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: (m) => {
                                        root.selIndex = row.index
                                        root.setRatio(row.modelData, m.x / width)
                                    }
                                }
                            }

                            Rectangle {
                                width: 22; height: 22
                                radius: Theme.roundingItem
                                color: plusMouse.containsMouse ? Theme.bgHover : "transparent"
                                Text { anchors.centerIn: parent; text: "+"; font.family: Theme.fontFamily; font.pixelSize: 14; color: Theme.fgMuted }
                                MouseArea {
                                    id: plusMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: { root.selIndex = row.index; root.adjust(1) }
                                }
                            }
                        }
                    }
                }
            }

            Text {
                visible: root.unavailableHint.length > 0
                text: root.unavailableHint
                font.family: Theme.fontFamily
                font.pixelSize: 11
                color: Theme.fgDim
                Layout.fillWidth: true
            }

            Text {
                text: "j/k move · h/l change · r re-probe · s/Esc back"
                font.family: Theme.fontFamily
                font.pixelSize: 10
                color: Theme.fgDim
                Layout.alignment: Qt.AlignHCenter
            }
        }
    }
}
