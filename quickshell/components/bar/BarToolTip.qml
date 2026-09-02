import QtQuick
import QtQuick.Controls
import "../../theme"

ToolTip {
    id: root
    delay: 400

    property Item anchorItem: null

    x: anchorItem ? anchorItem.width / 2 - width / 2 : 0
    y: anchorItem ? anchorItem.height + 4 : 0

    background: Rectangle {
        color: Theme.bgBarAlt
        radius: Theme.roundingItem
        border.width: 1
        border.color: Theme.borderActive
    }

    contentItem: Text {
        text: root.text
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.fg
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        leftPadding: Theme.padM
        rightPadding: Theme.padM
        topPadding: Theme.padS
        bottomPadding: Theme.padS
    }
}
