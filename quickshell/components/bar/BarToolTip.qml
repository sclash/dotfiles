import QtQuick
import Quickshell
import "../../theme"

// Popup-window tooltip: QQC ToolTip rendered inside the bar's layer surface
// and was clipped to the 32px bar height. This maps as a child popup anchored
// below the icon, styled like TrayMenu (same card language, Theme tokens).
PopupWindow {
    id: root

    // --- public API (unchanged) --------------------------------------
    property string text: ""
    property Item anchorItem: null

    // Tooltips must never take focus or interfere with hover.
    grabFocus: false
    color: "transparent"

    // Size: derived from text, but never 0 — a 0-sized buffer on map is a
    // fatal Wayland protocol error that kills the whole bar.
    readonly property int tooltipMaxWidth: 360
    implicitWidth: Math.min(Math.max(body.implicitWidth + Theme.padM * 2, Theme.padS * 2), tooltipMaxWidth)
    implicitHeight: Math.max(body.implicitHeight + Theme.padS * 2, Theme.padS * 2)

    anchor.item: anchorItem
    anchor.edges: Edges.Bottom
    anchor.gravity: Edges.Bottom
    anchor.margins.top: Theme.padXS

    Rectangle {
        anchors.fill: parent
        radius: Theme.roundingMenu
        color: Theme.bgLauncher
        border.width: Theme.borderWidth
        border.color: Theme.borderActive

        Text {
            id: body
            anchors.centerIn: parent
            width: Math.min(implicitWidth, root.tooltipMaxWidth - Theme.padM * 2)
            text: root.text
            visible: root.text !== ""
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.fg
            wrapMode: Text.Wrap
            maximumLineCount: 3
            elide: Text.ElideRight
        }
    }
}
