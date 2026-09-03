import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../theme"

// Themed replacement for the native QsMenuAnchor popup (Bar-App-Tray.md §3):
// tray context menus rendered with Theme tokens instead of the Qt platform
// palette. Submenus swap the opener's handle inside this one window (stack);
// Esc pops a submenu, outside click / Esc on root dismisses (grabFocus).
PopupWindow {
    id: root

    // --- public API -------------------------------------------------
    property var trayItem: null // SystemTrayItem whose menu to show
    property Item anchorItem: null // tray slot to attach below
    readonly property bool isOpen: visible

    function openFor(item, anchorItem) {
        root.trayItem = item;
        root.anchorItem = anchorItem;
        root.menuStack = [];
        visible = true;
    }

    function close() {
        visible = false;
    }

    // --- window ------------------------------------------------------
    visible: false
    grabFocus: true
    color: "transparent"

    // Fixed width; height always > 0 — a 0-sized buffer on map is a fatal
    // Wayland protocol error ("Invalid size") that kills the whole bar.
    readonly property int menuWidth: 260
    implicitWidth: menuWidth
    implicitHeight: menuCol.implicitHeight + Theme.padS * 2

    anchor.item: anchorItem
    anchor.edges: Edges.Bottom
    anchor.gravity: Edges.Bottom
    anchor.margins.top: Theme.padXS

    // --- menu stack (submenu support) --------------------------------
    property var menuStack: []
    readonly property var currentMenu: root.menuStack.length > 0 ? root.menuStack[root.menuStack.length - 1] : (trayItem ? trayItem.menu : null)

    onVisibleChanged: if (!visible) root.menuStack = []

    QsMenuOpener {
        id: opener
        menu: root.currentMenu
    }

    // --- card ----------------------------------------------------------
    Rectangle {
        anchors.fill: parent
        radius: Theme.roundingMenu
        color: Theme.bgLauncher
        border.width: Theme.borderWidth
        border.color: Theme.borderActive

        Keys.onEscapePressed: {
            if (root.menuStack.length > 0)
                root.menuStack = root.menuStack.slice(0, -1);
            else
                root.close();
        }

        Column {
            id: menuCol
            anchors.centerIn: parent
            spacing: 0

            Repeater {
                model: opener.children

                // modelData lives on the Loader (required props inside the
                // loaded component are NOT initialized by Loader — they must
                // be referenced through the loader's id instead).
                delegate: Loader {
                    id: entryLoader

                    required property var modelData

                    sourceComponent: entryLoader.modelData.isSeparator ? separatorComp : entryComp

                    Component {
                        id: separatorComp

                        Item {
                            width: root.menuWidth
                            height: 1 + Theme.padS

                            Rectangle {
                                anchors.centerIn: parent
                                width: parent.width - Theme.padM * 2
                                height: 1
                                color: Theme.border
                            }
                        }
                    }

                    Component {
                        id: entryComp

                        Rectangle {
                            id: entryRoot

                            readonly property var item: entryLoader.modelData
                            readonly property bool checked: item.checkState === Qt.Checked
                            readonly property bool partial: item.checkState === Qt.PartiallyChecked
                            readonly property bool isCheck: item.buttonType === 1
                            readonly property bool isRadio: item.buttonType === 2
                            readonly property bool hasSubmenu: item.hasChildren && ("menuHandle" in item)

                            width: root.menuWidth
                            height: 30
                            radius: Theme.roundingMenu
                            color: entryMA.containsMouse && item.enabled ? Theme.bgBarAlt : "transparent"
                            opacity: item.enabled ? 1.0 : 0.5

                            MouseArea {
                                id: entryMA
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (!entryRoot.item.enabled)
                                        return;
                                    if (entryRoot.hasSubmenu) {
                                        root.menuStack = root.menuStack.concat([entryRoot.item.menuHandle]);
                                    } else {
                                        entryRoot.item.triggered();
                                        root.close();
                                    }
                                }
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: Theme.padM
                                anchors.rightMargin: Theme.padM
                                spacing: Theme.gapS

                                // checkbox / radio indicator (hidden for plain actions)
                                Item {
                                    Layout.preferredWidth: 14
                                    Layout.preferredHeight: 14
                                    Layout.alignment: Qt.AlignVCenter
                                    visible: entryRoot.isCheck || entryRoot.isRadio

                                    Rectangle {
                                        anchors.fill: parent
                                        visible: entryRoot.isCheck
                                        radius: Theme.padXS
                                        color: entryRoot.checked ? Theme.fg : (entryRoot.partial ? Theme.fgDim : "transparent")
                                        border.width: Theme.borderWidth
                                        border.color: Theme.borderActive

                                        Text {
                                            visible: entryRoot.checked
                                            anchors.centerIn: parent
                                            text: Icons.check
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 10
                                            color: Theme.bgBar
                                        }
                                    }

                                    Rectangle {
                                        anchors.fill: parent
                                        visible: entryRoot.isRadio
                                        radius: width / 2
                                        color: "transparent"
                                        border.width: Theme.borderWidth
                                        border.color: Theme.borderActive

                                        Rectangle {
                                            visible: entryRoot.checked
                                            anchors.centerIn: parent
                                            width: 6
                                            height: 6
                                            radius: width / 2
                                            color: Theme.fg
                                        }
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: entryRoot.item.text
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeLauncher
                                    color: entryRoot.item.enabled ? Theme.fg : Theme.fgDim
                                    elide: Text.ElideRight
                                }

                                Text {
                                    visible: entryRoot.hasSubmenu
                                    text: Icons.chevronRight
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.fgMuted
                                }
                            }
                        }
                    }
                }
            }

            // back row when inside a submenu (mouse way back up the stack)
            Rectangle {
                width: root.menuWidth
                height: root.menuStack.length > 0 ? 26 : 0
                visible: root.menuStack.length > 0
                radius: Theme.roundingMenu
                color: backMA.containsMouse ? Theme.bgBarAlt : "transparent"

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.padM
                    anchors.rightMargin: Theme.padM
                    spacing: Theme.gapS

                    Text {
                        text: Icons.chevronLeft
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.fgMuted
                    }
                    Text {
                        text: "back"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSmall
                        font.italic: true
                        color: Theme.fgMuted
                    }
                }
                MouseArea {
                    id: backMA
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.menuStack = root.menuStack.slice(0, -1)
                }
            }
        }
    }
}
