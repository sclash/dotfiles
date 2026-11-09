import QtQuick
import QtQuick.Layouts
import "../../../theme"

// One selectable row in the VPN views: glyph, title, note, hint on the right.
// State is shown by the border (STYLE.md §2.1).
Rectangle {
    id: row
    property string icon: ""
    property string title: ""
    property string note: ""
    property string hint: ""
    property bool selected: false
    property bool dim: false
    signal clicked()

    Layout.fillWidth: true
    implicitHeight: 40
    radius: Theme.roundingItem
    color: selected ? Theme.bgSelected : (ma.containsMouse ? Theme.bgHover : "transparent")
    border.color: selected ? Theme.borderSelected : Theme.border
    border.width: 1

    MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: row.clicked() }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Theme.padM
        anchors.rightMargin: Theme.padM
        spacing: Theme.gapM
        Text {
            visible: row.icon !== ""
            text: row.icon
            font.family: Theme.fontFamily
            font.pixelSize: 14
            color: row.dim ? Theme.fgDim : Theme.fg
            Layout.preferredWidth: 18
        }
        Text {
            text: row.title
            font.family: Theme.fontFamily
            font.pixelSize: 13
            color: row.dim ? Theme.fgDim : Theme.fg
            elide: Text.ElideMiddle
            Layout.fillWidth: true
        }
        Text { visible: row.note !== ""; text: row.note; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; color: Theme.fgMuted }
        Text { visible: row.hint !== ""; text: row.hint; font.family: Theme.fontFamily; font.pixelSize: 10; color: Theme.fgDim }
    }
}
