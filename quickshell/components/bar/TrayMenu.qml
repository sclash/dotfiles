import QtQuick
import QtQuick.Layouts
import Quickshell
import "../launchers"
import "../../theme"

// Themed replacement for the native QsMenuAnchor popup (Bar-App-Tray.md §3):
// tray context menus rendered with Theme tokens instead of the Qt platform
// palette. Backed by DBusMenuClient — quickshell 0.3.0 cannot open submenu
// handles via QsMenuOpener, so this client speaks DBusMenu over busctl.
// Suboptions expand IN PLACE (accordion) under their parent on hover —
// no navigation stack, no back row.
PopupWindow {
    id: root

    // --- public API -------------------------------------------------
    property var trayItem: null // SystemTrayItem whose menu to show
    property Item anchorItem: null // tray slot to attach below
    readonly property bool isOpen: visible

    function openFor(item, anchorItem) {
        root.trayItem = item;
        root.anchorItem = anchorItem;
        menuClient.openForItem(item);
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

    onVisibleChanged: if (!visible)
        menuClient.openForItem(null)

    DBusMenuClient {
        id: menuClient
    }

    // flat display model: root entries with expanded children inline
    readonly property var rows: {
        const out = [];
        const entries = menuClient.entries;
        for (let i = 0; i < entries.length; i++) {
            const e = entries[i];
            out.push({
                "entry": e,
                "depth": 0
            });
            if (menuClient.expandedId === e.id) {
                const kids = menuClient.childEntries;
                for (let j = 0; j < kids.length; j++)
                    out.push({
                        "entry": kids[j],
                        "depth": 1
                    });
            }
        }
        return out;
    }

    // --- card ----------------------------------------------------------
    Rectangle {
        anchors.fill: parent
        radius: Theme.roundingMenu
        color: Theme.bgLauncher
        border.width: Theme.borderWidth
        border.color: Theme.borderActive

        Keys.onEscapePressed: {
            if (menuClient.expandedId !== -1)
                menuClient.collapseExpanded();
            else
                root.close();
        }

        Column {
            id: menuCol

            anchors.centerIn: parent
            spacing: 0

            Repeater {
                model: root.rows

                delegate: Loader {
                    id: entryLoader

                    required property var modelData

                    sourceComponent: entryLoader.modelData.entry.isSeparator ? separatorComp : entryComp

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

                            readonly property var item: entryLoader.modelData.entry
                            readonly property int depth: entryLoader.modelData.depth

                            width: root.menuWidth
                            height: 30
                            radius: Theme.roundingMenu
                            color: entryMA.containsMouse && item.enabled ? Theme.bgBarAlt : "transparent"
                            opacity: item.enabled ? 1.0 : 0.5

                            // click-to-open: submenu parents toggle on click
                            MouseArea {
                                id: entryMA

                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (!entryRoot.item.enabled)
                                        return;
                                    if (entryRoot.item.hasChildren) {
                                        // toggle: click an expanded parent to collapse it
                                        if (menuClient.expandedId === entryRoot.item.id)
                                            menuClient.collapseExpanded();
                                        else
                                            menuClient.expandEntry(entryRoot.item);
                                    } else {
                                        menuClient.triggerEntry(entryRoot.item);
                                        root.close();
                                    }
                                }
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: Theme.padM + entryRoot.depth * Theme.padL
                                anchors.rightMargin: Theme.padM
                                spacing: Theme.gapS

                                // checkbox / radio indicator (hidden for plain actions)
                                Item {
                                    Layout.preferredWidth: 14
                                    Layout.preferredHeight: 14
                                    Layout.alignment: Qt.AlignVCenter
                                    visible: entryRoot.item.toggleType !== ""

                                    Rectangle {
                                        anchors.fill: parent
                                        visible: entryRoot.item.toggleType === "checkbox"
                                        radius: Theme.padXS
                                        color: entryRoot.item.toggleState === 1 ? Theme.fg : (entryRoot.item.toggleState === 2 ? Theme.fgDim : "transparent")
                                        border.width: Theme.borderWidth
                                        border.color: Theme.borderActive

                                        Text {
                                            visible: entryRoot.item.toggleState === 1
                                            anchors.centerIn: parent
                                            text: Icons.check
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 10
                                            color: Theme.bgBar
                                        }
                                    }

                                    Rectangle {
                                        anchors.fill: parent
                                        visible: entryRoot.item.toggleType === "radio"
                                        radius: width / 2
                                        color: "transparent"
                                        border.width: Theme.borderWidth
                                        border.color: Theme.borderActive

                                        Rectangle {
                                            visible: entryRoot.item.toggleState === 1
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
                                    text: entryRoot.item.label
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeLauncher
                                    color: entryRoot.item.enabled ? Theme.fg : Theme.fgDim
                                    elide: Text.ElideRight
                                }

                                Text {
                                    visible: entryRoot.item.hasChildren
                                    text: menuClient.expandedId === entryRoot.item.id ? Icons.expand : Icons.collapse
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.fgMuted
                                }
                            }
                        }
                    }
                }
            }

            // empty / loading state
            Text {
                visible: menuClient.entries.length === 0
                text: menuClient.busy ? "loading menu…" : "no options available"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.fgMuted
            }
        }
    }
}
