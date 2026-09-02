import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../theme"

Rectangle {
    id: card
    property var toastData
    signal dismissRequested(string toastId)
    signal primaryAction(var notification)

    width: 360
    radius: Theme.roundingItem
    color: Theme.bgBar

    implicitHeight: contentCol.implicitHeight + Theme.padM * 2

    readonly property var n: toastData && toastData.notification ? toastData.notification : null
    readonly property string summaryText: toastData ? (toastData.summary || "") : ""
    readonly property string bodyText: toastData ? (toastData.body || "") : ""

    opacity: 0
    Behavior on opacity { NumberAnimation { duration: Theme.durationFast; easing.type: Easing.OutCubic } }
    Component.onCompleted: opacity = 1

    Timer {
        interval: toastData && toastData._expiresAt ? Math.max(0, toastData._expiresAt - Date.now()) : 3000
        running: toastData !== undefined && toastData !== null
        repeat: false
        onTriggered: card.dismissRequested(card.toastData._toastId)
    }

    ColumnLayout {
        id: contentCol
        anchors.fill: parent
        anchors.margins: Theme.padM
        spacing: 4

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.gapS

            Text {
                text: toastData && toastData.appIcon ? toastData.appIcon : Icons.notification
                font.family: Theme.fontFamily
                font.pixelSize: 16
                color: Theme.fgMuted
                visible: text.length > 0
            }

            Text {
                text: toastData ? (toastData.appName || "Unknown") : ""
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.fgMuted
                font.weight: Theme.fontWeightMedium
                Layout.fillWidth: true
                elide: Text.ElideRight
            }

            Text {
                text: toastData && toastData.timestamp ? Qt.formatDateTime(toastData.timestamp, "hh:mm") : ""
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.fgDim
            }
        }

        Text {
            text: card.summaryText
            font.family: Theme.fontFamily
            font.pixelSize: 12
            font.weight: Theme.fontWeightMedium
            color: Theme.fg
            wrapMode: Text.Wrap
            Layout.fillWidth: true
            visible: text.length > 0
        }

        Text {
            text: card.bodyText
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.fgMuted
            wrapMode: Text.ElideRight
            maximumLineCount: 1
            Layout.fillWidth: true
            visible: text.length > 0
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            if (card.n) card.primaryAction(card.n)
            else card.dismissRequested(card.toastData._toastId)
        }
    }
}
