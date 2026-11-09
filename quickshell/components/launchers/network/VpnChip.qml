import QtQuick
import QtQuick.Layouts
import "../../../theme"

// Two-option chip (Save | Ask, Data | Secret). Space or a click toggles;
// Enter moves on (advance). The current option is bright, the other dim.
Rectangle {
    id: chip
    property string first: "Save"
    property string second: "Ask"
    property bool isSecond: false
    signal toggled()
    signal advance(var from)

    implicitWidth: 112
    implicitHeight: 36
    Layout.preferredWidth: implicitWidth
    Layout.preferredHeight: implicitHeight
    radius: Theme.roundingItem
    color: "transparent"
    border.color: chip.activeFocus ? Theme.borderSelected : Theme.border
    border.width: 1
    activeFocusOnTab: true

    Keys.onPressed: (e) => {
        if (e.key === Qt.Key_Space) { chip.toggled(); e.accepted = true }
        else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { chip.advance(chip); e.accepted = true }
    }

    RowLayout {
        anchors.centerIn: parent
        spacing: Theme.gapS
        Text {
            text: chip.first
            font.family: Theme.fontFamily
            font.pixelSize: 11
            font.weight: chip.isSecond ? Theme.fontWeightNormal : Theme.fontWeightMedium
            color: chip.isSecond ? Theme.fgDim : Theme.fgBright
        }
        Text { text: "|"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fgDim }
        Text {
            text: chip.second
            font.family: Theme.fontFamily
            font.pixelSize: 11
            font.weight: chip.isSecond ? Theme.fontWeightMedium : Theme.fontWeightNormal
            color: chip.isSecond ? Theme.fgBright : Theme.fgDim
        }
    }
    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { chip.forceActiveFocus(); chip.toggled() } }
}
