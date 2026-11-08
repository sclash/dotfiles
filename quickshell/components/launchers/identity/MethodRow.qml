import QtQuick
import QtQuick.Layouts
import "../../../theme"

// One selectable row: glyph, title + note, state on the right. Used for the
// method list and for each method's on/off toggle.
Rectangle {
    id: row
    property string icon: ""
    property string title: ""
    property string note: ""
    property string stateText: ""
    property bool selected: false
    property bool dim: false                 // unavailable/disabled look
    signal clicked()

    Layout.fillWidth: true
    implicitHeight: 46
    radius: Theme.roundingItem
    color: selected ? Theme.bgSelected : (ma.containsMouse ? Theme.bgHover : "transparent")
    border.color: selected ? Theme.borderSelected : Theme.border
    border.width: 1

    MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; onClicked: row.clicked() }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Theme.padM
        anchors.rightMargin: Theme.padM
        spacing: Theme.gapM
        Text {
            text: row.icon
            font.family: Theme.fontFamily
            font.pixelSize: 18
            color: row.dim ? Theme.fgDim : Theme.fg
            Layout.preferredWidth: 22
        }
        ColumnLayout {
            spacing: 1
            Text {
                text: row.title
                font.family: Theme.fontFamily
                font.pixelSize: 13
                font.weight: Theme.fontWeightMedium
                color: Theme.fg
            }
            Text {
                visible: row.note !== ""
                text: row.note
                font.family: Theme.fontFamily
                font.pixelSize: 10
                color: Theme.fgDim
            }
        }
        Item { Layout.fillWidth: true }
        Text {
            text: row.stateText
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
            color: row.dim ? Theme.fgDim : Theme.fg
        }
    }
}
