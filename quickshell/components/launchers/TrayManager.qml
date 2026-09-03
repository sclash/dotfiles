import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.SystemTray
import "../../theme"

// Tray-Manager (SUPER+t) — specs/launchers/Tray-Manager.md
// Lists SystemTray items; l opens the app's SNI menu (same entries as
// right-clicking its bar icon) in an in-card options view, backed by
// DBusMenuClient (quickshell 0.3.0 cannot open submenu handles natively).
// Shared launcher chrome: Esc hierarchy, vim nav, `/` filter, dim overlay.
WlrLayershell {
    id: root

    property bool isOpen: false

    function open() {
        root.resetView();
        isOpen = true;
        visible = true;
    }
    function close() {
        isOpen = false;
        visible = false;
    }
    function toggle() { if (isOpen) close(); else open() }

    // --- state ---------------------------------------------------------
    // view: 0 = apps list, 1 = options (menu) of selectedItem
    property int view: 0
    property var selectedItem: null
    property int appsIndex: 0
    property int menuIndex: 0
    property var appRows: []
    property var menuRows: []

    // tray items snapshot (reactive — .values is a notifying property)
    readonly property var trayItems: SystemTray.items ? SystemTray.items.values : []

    function resetView() {
        root.view = 0;
        root.selectedItem = null;
        root.appsIndex = 0;
        root.menuIndex = 0;
        filterBar.visible = false;
        filterField.text = "";
        root.refreshApps();
    }

    function appLabel(item) {
        return (item && item.tooltipTitle) ? item.tooltipTitle : (item && item.id ? item.id : "");
    }

    function refreshApps() {
        const q = filterField.text.toLowerCase();
        const src = root.trayItems;
        root.appRows = q ? src.filter(it => root.appLabel(it).toLowerCase().indexOf(q) !== -1) : src;
        if (root.appsIndex >= root.appRows.length)
            root.appsIndex = Math.max(0, root.appRows.length - 1);
    }

    function refreshMenu() {
        const q = filterField.text.toLowerCase();
        const src = menuClient.entries;
        root.menuRows = q ? src.filter(e => e.label.toLowerCase().indexOf(q) !== -1) : src;
        if (root.menuIndex >= root.menuRows.length)
            root.menuIndex = Math.max(0, root.menuRows.length - 1);
    }

    function backToApps() {
        root.view = 0;
        root.selectedItem = null;
        filterBar.visible = false;
        filterField.text = "";
        root.refreshApps();
        appsList.forceActiveFocus();
    }

    function moveSelection(list, indexProp, step) {
        // step selection, skipping separator rows
        let i = root[indexProp];
        let guard = 0;
        do {
            i += step;
            guard++;
        } while (guard < 64 && i >= 0 && i < list.length && list[i] && list[i].isSeparator);
        if (i >= 0 && i < list.length) {
            root[indexProp] = i;
            return true;
        }
        return false;
    }

    // apps view: open the app itself (same as left-click on its bar icon)
    function activateCurrent() {
        const it = root.appRows[root.appsIndex];
        if (it)
            it.activate();
    }

    // apps view: drill into the app's SNI menu (same as right-click on the icon)
    function openOptions() {
        const it = root.appRows[root.appsIndex];
        if (!it)
            return;
        if (it.hasMenu) {
            root.selectedItem = it;
            root.menuIndex = 0;
            root.view = 1;
            filterBar.visible = false;
            filterField.text = "";
            menuClient.openForItem(it);
        } else {
            it.secondaryActivate();
        }
    }

    // options view: trigger focused entry (Enter)
    function activateMenuEntry() {
        const e = root.menuRows[root.menuIndex];
        if (!e || e.isSeparator || !e.enabled)
            return;
        menuClient.trigger(root.menuIndex); // submenu → drills; leaf → fires + refetches toggles
        if (!e.hasChildren)
            root.backToApps(); // spec: back to list, manager stays open
    }

    // options view: drill into a submenu (l) — never triggers
    function drillIntoCurrent() {
        menuClient.drill(root.menuIndex);
    }

    // options view: pop a submenu level, or return to the apps list
    function backOneLevel() {
        if (!menuClient.back())
            root.backToApps();
    }

    function showFilter() {
        filterBar.visible = true;
        Qt.callLater(() => filterField.forceActiveFocus());
    }

    function hideFilter() {
        filterBar.visible = false;
        filterField.text = "";
        if (root.view === 0)
            appsList.forceActiveFocus();
        else
            menuList.forceActiveFocus();
    }

    onIsOpenChanged: if (isOpen) Qt.callLater(() => card.forceActiveFocus())
    onVisibleChanged: if (!visible) root.resetView()

    // keep rows in sync with async D-Bus updates
    Connections {
        target: SystemTray.items
        function onValuesChanged() {
            if (root.isOpen)
                root.refreshApps();
        }
    }

    // stale selection guard (tray item vanished while manager open)
    onTrayItemsChanged: {
        if (root.view === 1 && root.selectedItem && root.trayItems.indexOf(root.selectedItem) === -1)
            root.backToApps();
    }

    DBusMenuClient {
        id: menuClient

        onEntriesChanged: root.refreshMenu()
    }

    // --- chrome ----------------------------------------------------------
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    exclusionMode: ExclusionMode.Ignore
    keyboardFocus: WlrKeyboardFocus.Exclusive
    color: "transparent"
    visible: isOpen

    Rectangle {
        anchors.fill: parent
        color: Theme.overlay
        MouseArea {
            anchors.fill: parent
            onClicked: root.close()
        }
    }

    Rectangle {
        id: card

        width: 560
        height: Math.min(480, col.implicitHeight + Theme.padL * 2)
        anchors.centerIn: parent
        radius: Theme.roundingLauncher
        color: Theme.bgLauncher
        border.width: Theme.borderWidth
        border.color: Theme.borderActive
        clip: true
        focus: true

        Keys.onPressed: (e) => {
            const inApps = root.view === 0;
            const list = inApps ? root.appRows : root.menuRows;
            const idxProp = inApps ? "appsIndex" : "menuIndex";
            if (e.key === Qt.Key_J || e.key === Qt.Key_Down) {
                root.moveSelection(list, idxProp, 1);
                e.accepted = true;
            } else if (e.key === Qt.Key_K || e.key === Qt.Key_Up) {
                root.moveSelection(list, idxProp, -1);
                e.accepted = true;
            } else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                if (inApps)
                    root.activateCurrent();
                else
                    root.activateMenuEntry();
                e.accepted = true;
            } else if (inApps && (e.key === Qt.Key_L || e.key === Qt.Key_Right)) {
                root.openOptions(); // l = see the app's options
                e.accepted = true;
            } else if (!inApps && (e.key === Qt.Key_L || e.key === Qt.Key_Right)) {
                root.drillIntoCurrent(); // l = forward into suboptions
                e.accepted = true;
            } else if (!inApps && (e.key === Qt.Key_H || e.key === Qt.Key_Left)) {
                root.backOneLevel(); // h = back one level
                e.accepted = true;
            } else if (e.key === Qt.Key_Escape) {
                if (filterBar.visible) {
                    root.hideFilter();
                } else if (root.view === 1) {
                    root.backOneLevel();
                } else {
                    root.close();
                }
                e.accepted = true;
            } else if (e.text === "/") {
                root.showFilter();
                e.accepted = true;
            }
        }

        ColumnLayout {
            id: col

            anchors.fill: parent
            anchors.margins: Theme.padL
            spacing: Theme.gapM

            // header / breadcrumb
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.gapS

                Text {
                    Layout.fillWidth: true
                    text: root.view === 0 ? "Tray Manager" : root.appLabel(root.selectedItem) + (menuClient.breadcrumb !== "" ? " › " + menuClient.breadcrumb : "")
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.fgMuted
                    font.capitalization: Font.AllUppercase
                    font.letterSpacing: 1.2
                    elide: Text.ElideRight
                }
                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: Theme.border
                }
            }

            // filter bar — hidden until `/`
            RowLayout {
                id: filterBar

                visible: false
                Layout.fillWidth: true
                spacing: Theme.gapS

                Text {
                    text: Icons.search
                    font.family: Theme.fontFamily
                    font.pixelSize: 16
                    color: Theme.fgMuted
                }
                TextField {
                    id: filterField

                    Layout.fillWidth: true
                    placeholderText: root.view === 0 ? "Filter tray apps…" : "Filter options…"
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                    color: Theme.fg
                    onTextChanged: {
                        if (root.view === 0)
                            root.refreshApps();
                        else
                            root.refreshMenu();
                    }
                    Keys.onEscapePressed: root.hideFilter()
                }
            }

            // apps view
            ListView {
                id: appsList

                visible: root.view === 0
                Layout.fillWidth: true
                // content-based height so all rows render at once, capped with scroll
                Layout.preferredHeight: Math.min(contentHeight, 360)
                Layout.fillHeight: true
                model: root.appRows
                currentIndex: root.appsIndex
                onCurrentIndexChanged: root.appsIndex = currentIndex
                interactive: false
                clip: true
                delegate: Rectangle {
                    id: appRow

                    required property var modelData

                    width: appsList.width
                    height: 38
                    radius: Theme.roundingMenu
                    // bgSelected token equals the card background on this theme —
                    // use bgBarAlt + bright medium-weight text for visibility
                    color: appRow.ListView.isCurrentItem || rowMA.containsMouse ? Theme.bgBarAlt : "transparent"

                    MouseArea {
                        id: rowMA

                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        cursorShape: Qt.PointingHandCursor
                        onClicked: (mouse) => {
                            appsList.currentIndex = index;
                            if (mouse.button === Qt.RightButton)
                                root.openOptions(); // right-click parity with the bar icon
                            else
                                root.activateCurrent(); // left-click opens the app
                        }
                    }
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.padM
                        anchors.rightMargin: Theme.padM
                        spacing: Theme.gapM

                        Image {
                            Layout.preferredWidth: 20
                            Layout.preferredHeight: 20
                            Layout.alignment: Qt.AlignVCenter
                            source: appRow.modelData.icon
                            smooth: true
                            asynchronous: true
                            sourceSize: Qt.size(20, 20)
                        }
                        Text {
                            Layout.fillWidth: true
                            text: root.appLabel(appRow.modelData)
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeLauncher
                            font.weight: appRow.ListView.isCurrentItem ? Theme.fontWeightMedium : Theme.fontWeightNormal
                            color: appRow.ListView.isCurrentItem ? Theme.fgBright : Theme.fg
                            elide: Text.ElideRight
                        }
                        Text {
                            visible: !appRow.modelData.hasMenu
                            text: "no menu"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSmall
                            font.italic: true
                            color: Theme.fgDim
                        }
                    }
                }
            }

            // empty state (apps)
            Text {
                visible: root.view === 0 && root.appRows.length === 0
                text: filterBar.visible ? "no matches" : "no tray apps registered"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.fgMuted
                Layout.alignment: Qt.AlignHCenter
            }

            // options view
            ListView {
                id: menuList

                visible: root.view === 1
                Layout.fillWidth: true
                // content-based height so all options render at once, capped with scroll
                Layout.preferredHeight: Math.min(contentHeight, 360)
                Layout.fillHeight: true
                model: root.menuRows
                currentIndex: root.menuIndex
                onCurrentIndexChanged: root.menuIndex = currentIndex
                interactive: false
                clip: true
                delegate: Rectangle {
                    id: menuRow

                    required property var modelData

                    width: menuList.width
                    height: modelData.isSeparator ? 1 + Theme.padS : 30
                    radius: Theme.roundingMenu
                    // selection visible: bgBarAlt + bright medium-weight text
                    // (bgSelected token equals the card background on this theme)
                    color: !modelData.isSeparator && (menuRow.ListView.isCurrentItem || rowMA2.containsMouse) ? Theme.bgBarAlt : "transparent"
                    opacity: modelData.isSeparator || modelData.enabled ? 1.0 : 0.5

                    MouseArea {
                        id: rowMA2

                        anchors.fill: parent
                        enabled: !menuRow.modelData.isSeparator
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            menuList.currentIndex = index;
                            root.activateMenuEntry();
                        }
                    }
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.padM
                        anchors.rightMargin: Theme.padM
                        spacing: Theme.gapS

                        // separators render as a hairline
                        Rectangle {
                            visible: menuRow.modelData.isSeparator
                            Layout.fillWidth: true
                            height: 1
                            color: Theme.border
                        }

                        // checkbox / radio indicator
                        Item {
                            Layout.preferredWidth: 14
                            Layout.preferredHeight: 14
                            Layout.alignment: Qt.AlignVCenter
                            visible: !menuRow.modelData.isSeparator && menuRow.modelData.toggleType !== ""

                            Rectangle {
                                anchors.fill: parent
                                visible: menuRow.modelData.toggleType === "checkbox"
                                radius: Theme.padXS
                                color: menuRow.modelData.toggleState === 1 ? Theme.fg : (menuRow.modelData.toggleState === 2 ? Theme.fgDim : "transparent")
                                border.width: Theme.borderWidth
                                border.color: Theme.borderActive

                                Text {
                                    visible: menuRow.modelData.toggleState === 1
                                    anchors.centerIn: parent
                                    text: Icons.check
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 10
                                    color: Theme.bgBar
                                }
                            }
                            Rectangle {
                                anchors.fill: parent
                                visible: menuRow.modelData.toggleType === "radio"
                                radius: width / 2
                                color: "transparent"
                                border.width: Theme.borderWidth
                                border.color: Theme.borderActive

                                Rectangle {
                                    visible: menuRow.modelData.toggleState === 1
                                    anchors.centerIn: parent
                                    width: 6
                                    height: 6
                                    radius: width / 2
                                    color: Theme.fg
                                }
                            }
                        }

                        Text {
                            visible: !menuRow.modelData.isSeparator
                            Layout.fillWidth: true
                            text: menuRow.modelData.label
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeLauncher
                            font.weight: menuRow.ListView.isCurrentItem ? Theme.fontWeightMedium : Theme.fontWeightNormal
                            color: menuRow.ListView.isCurrentItem ? Theme.fgBright : (menuRow.modelData.enabled ? Theme.fg : Theme.fgDim)
                            elide: Text.ElideRight
                        }
                        Text {
                            visible: !menuRow.modelData.isSeparator && menuRow.modelData.hasChildren
                            text: Icons.collapse
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.fgMuted
                        }
                    }
                }
            }

            // empty / loading state (options)
            Text {
                visible: root.view === 1 && root.menuRows.length === 0
                text: menuClient.busy ? "loading menu…" : (filterBar.visible ? "no matches" : "no options available")
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.fgMuted
                Layout.alignment: Qt.AlignHCenter
            }

            // footer hints
            Text {
                text: "enter open/trigger · l forward · h back · j/k navigate · / filter"
                font.family: Theme.fontFamily
                font.pixelSize: 10
                font.italic: true
                color: Theme.fgDim
                Layout.alignment: Qt.AlignHCenter
            }
        }
    }
}
