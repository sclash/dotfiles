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

    // two-step quit (x): first press arms, second press executes. Never quits
    // on a single press — a stray x only shows the confirm hint.
    property string confirmQuitId: ""
    property string quitNote: ""
    property bool quitBusy: false

    function resetView() {
        root.view = 0;
        root.selectedItem = null;
        root.appsIndex = 0;
        root.menuIndex = 0;
        root.confirmQuitId = "";
        root.quitNote = "";
        filterBar.visible = false;
        filterField.text = "";
        root.refreshApps();
    }

    function disarmQuit() {
        root.confirmQuitId = "";
    }

    function currentQuitApp() {
        const idx = root.appRows.length ? Math.min(Math.max(root.appsIndex, 0), root.appRows.length - 1) : -1;
        return idx >= 0 ? root.appRows[idx] : null;
    }

    // x / Delete in apps view: arm on first press, execute on second.
    function requestQuitCurrent() {
        if (root.quitBusy)
            return;
        const it = root.currentQuitApp();
        if (!it || !it.id)
            return;
        if (root.confirmQuitId !== it.id) {
            root.confirmQuitId = it.id;
            root.quitNote = "";
            return;
        }
        root.confirmQuitId = "";
        root.quitBusy = true;
        root.quitNote = "Quitting " + root.appLabel(it) + "…";
        quitClient.quitAppById(it.id);
    }

    function appLabel(item) {
        return (item && item.tooltipTitle) ? item.tooltipTitle : (item && item.id ? item.id : "");
    }

    function refreshApps() {
        const q = filterField.text.toLowerCase();
        const src = root.trayItems;
        root.appRows = q ? src.filter(it => root.appLabel(it).toLowerCase().indexOf(q) !== -1) : src;
        // clamp BOTH sides — a model swap resets ListView.currentIndex to -1,
        // which left appsIndex at -1 and made l/Enter silently no-op after filtering
        root.appsIndex = Math.min(Math.max(root.appsIndex, 0), Math.max(0, root.appRows.length - 1));
        // the list changed under us — a stale arm could quit the wrong app
        root.confirmQuitId = "";
    }

    function refreshMenu() {
        const q = filterField.text.toLowerCase();
        const src = menuClient.entries;
        root.menuRows = q ? src.filter(e => e.label.toLowerCase().indexOf(q) !== -1) : src;
        root.menuIndex = Math.min(Math.max(root.menuIndex, 0), Math.max(0, root.menuRows.length - 1));
    }

    function backToApps() {
        root.view = 0;
        root.selectedItem = null;
        filterBar.visible = false;
        filterField.text = "";
        root.refreshApps();
        card.forceActiveFocus(); // key handling lives on the card — never park focus on the list
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
        const idx = root.appRows.length ? Math.min(Math.max(root.appsIndex, 0), root.appRows.length - 1) : -1;
        root.appsIndex = idx;
        const it = idx >= 0 ? root.appRows[idx] : null;
        if (it)
            it.activate();
    }

    // apps view: drill into the app's SNI menu (same as right-click on the icon)
    function openOptions() {
        const idx = root.appRows.length ? Math.min(Math.max(root.appsIndex, 0), root.appRows.length - 1) : -1;
        root.appsIndex = idx;
        const it = idx >= 0 ? root.appRows[idx] : null;
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
        const idx = root.menuRows.length ? Math.min(Math.max(root.menuIndex, 0), root.menuRows.length - 1) : -1;
        root.menuIndex = idx;
        const e = idx >= 0 ? root.menuRows[idx] : null;
        if (!e || e.isSeparator || !e.enabled)
            return;
        if (e.hasChildren) {
            root.drillIntoCurrent(); // stack-model drill (accordion is TrayMenu-only)
            return;
        }
        menuClient.triggerEntry(e); // leaf → fires + refetches toggles
        root.backToApps(); // spec: back to list, manager stays open
    }

    // options view: drill into a submenu (l) — never triggers
    function drillIntoCurrent() {
        const idx = root.menuRows.length ? Math.min(Math.max(root.menuIndex, 0), root.menuRows.length - 1) : -1;
        root.menuIndex = idx;
        const e = idx >= 0 ? root.menuRows[idx] : null;
        // the filter belongs to the level it was typed on — a stale parent
        // filter (e.g. "netw") would hide every child (wifi names don't match)
        filterField.text = "";
        menuClient.drillEntry(e);
    }

    // options view: pop a submenu level, or return to the apps list
    function backOneLevel() {
        if (menuClient.back()) {
            filterField.text = ""; // level changed → filter does not carry over
        } else {
            root.backToApps();
        }
    }

    function showFilter() {
        filterBar.visible = true;
        Qt.callLater(() => filterField.forceActiveFocus());
    }

    function hideFilter() {
        // Esc convention: keep the applied filter — only an empty field hides the bar
        if (filterField.text.length > 0) {
            card.forceActiveFocus();
        } else {
            filterBar.visible = false;
            card.forceActiveFocus();
        }
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

    // dedicated client for x-quit so a quit never clobbers the options view
    DBusMenuClient {
        id: quitClient

        onQuitFinished: (outcome) => {
            root.quitBusy = false;
            const it = root.currentQuitApp();
            const label = it ? root.appLabel(it) : "";
            if (outcome.startsWith("OK menu"))
                root.quitNote = "Quit " + label;
            else if (outcome.startsWith("OK term"))
                root.quitNote = "Terminated " + label + " (no Quit action — process " + outcome.split(" ").pop() + ")";
            else
                root.quitNote = "Quit failed (" + outcome.replace(/^FAIL\s*/, "") + ")";
            root.refreshApps();
        }
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
        Behavior on height {
            NumberAnimation {
                duration: Theme.durationNormal
                easing.type: Easing.OutCubic
            }
        }
        anchors.centerIn: parent
        radius: Theme.roundingManager
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
                if (inApps)
                    root.disarmQuit(); // moving away cancels a pending quit arm
                root.moveSelection(list, idxProp, 1);
                e.accepted = true;
            } else if (e.key === Qt.Key_K || e.key === Qt.Key_Up) {
                if (inApps)
                    root.disarmQuit();
                root.moveSelection(list, idxProp, -1);
                e.accepted = true;
            } else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                if (inApps)
                    root.activateCurrent();
                else
                    root.activateMenuEntry();
                e.accepted = true;
            } else if (inApps && (e.key === Qt.Key_X || e.key === Qt.Key_Delete)) {
                root.requestQuitCurrent(); // first x arms, second x quits
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
                } else if (root.confirmQuitId !== "") {
                    root.disarmQuit(); // Esc cancels the arm before anything else
                    root.quitNote = "";
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

            // filter bar — hidden until `/` (NetworkCenter parity)
            Rectangle {
                id: filterBar

                visible: false
                Layout.fillWidth: true
                Layout.preferredHeight: 36
                radius: Theme.roundingItem
                color: Theme.bgActive
                border.color: filterField.activeFocus ? Theme.borderSelected : Theme.border
                border.width: 1

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.padM
                    anchors.rightMargin: Theme.padM
                    spacing: Theme.gapM

                    Text {
                        text: Icons.search
                        font.family: Theme.fontFamily
                        font.pixelSize: 14
                        color: Theme.fgMuted
                    }
                    TextField {
                        id: filterField

                        Layout.fillWidth: true
                        placeholderText: root.view === 0 ? "Filter tray apps…" : "Filter options…"
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                        color: Theme.fg
                        placeholderTextColor: Theme.fgDim
                        background: null
                        cursorDelegate: Rectangle {
                            width: Math.max(6, Math.round(parent.font.pixelSize * 0.65))
                            height: Math.round(parent.font.pixelSize * 1.5)
                            color: Theme.fg
                        }
                        onTextChanged: {
                            if (root.view === 0)
                                root.refreshApps();
                            else
                                root.refreshMenu();
                        }
                        // environment convention: Esc keeps the filter (so the
                        // filtered results stay navigable) unless the field is empty
                        Keys.onEscapePressed: {
                            if (text.length > 0) {
                                card.forceActiveFocus();
                            } else {
                                filterBar.visible = false;
                                card.forceActiveFocus();
                            }
                        }
                        onAccepted: {
                            filterBar.visible = false; // apply + hide, filter stays active
                            card.forceActiveFocus();
                        }
                    }
                }
            }

            // view area — both views overlap here; level-based parking spots
            // (apps left, options right) make forward/back slides direction-correct
            Item {
                id: viewArea

                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(root.view === 0 ? appsList.contentHeight : menuList.contentHeight, 360)
                Layout.fillHeight: true
                clip: true

                // apps view
                ListView {
                    id: appsList

                    anchors.fill: parent
                    opacity: root.view === 0 ? 1 : 0
                    x: root.view === 0 ? 0 : -60
                    visible: opacity > 0.01
                    enabled: root.view === 0
                    model: root.appRows
                    currentIndex: root.appsIndex
                    onCurrentIndexChanged: root.appsIndex = currentIndex
                    interactive: false
                    clip: true

                    Behavior on opacity {
                        NumberAnimation {
                            duration: Theme.durationNormal
                            easing.type: Easing.OutCubic
                        }
                    }

                    Behavior on x {
                        NumberAnimation {
                            duration: Theme.durationNormal
                            easing.type: Easing.OutCubic
                        }
                    }

                    delegate: Rectangle {
                        id: appRow

                        required property var modelData

                        width: appsList.width
                        height: 38
                        radius: Theme.roundingMenu
                        // environment selection style (NetworkCenter parity):
                        // bgSelected bg + borderSelected border; hover = bgHover.
                        // an armed quit row gets the warning border instead.
                        readonly property bool quitArmed: root.confirmQuitId !== "" && appRow.modelData.id === root.confirmQuitId
                        color: appRow.quitArmed ? Theme.bgHover : (appRow.ListView.isCurrentItem || rowMA.containsMouse ? Theme.bgSelected : Theme.bgHover)
                        border.width: Theme.borderWidth
                        border.color: appRow.quitArmed ? Theme.warning : (appRow.ListView.isCurrentItem ? Theme.borderSelected : "transparent")

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
                            color: Theme.fg
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
                anchors.centerIn: parent
                visible: root.view === 0 && root.appRows.length === 0
                text: filterBar.visible ? "no matches" : "no tray apps registered"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.fgMuted
            }

                // options view
                ListView {
                    id: menuList

                    anchors.fill: parent
                    opacity: root.view === 1 ? 1 : 0
                    x: root.view === 1 ? 0 : 60
                    visible: opacity > 0.01
                    enabled: root.view === 1
                    model: root.menuRows
                    currentIndex: root.menuIndex
                    onCurrentIndexChanged: root.menuIndex = currentIndex
                    interactive: false
                    clip: true

                    Behavior on opacity {
                        NumberAnimation {
                            duration: Theme.durationNormal
                            easing.type: Easing.OutCubic
                        }
                    }

                    Behavior on x {
                        NumberAnimation {
                            duration: Theme.durationNormal
                            easing.type: Easing.OutCubic
                        }
                    }

                    delegate: Rectangle {
                    id: menuRow

                    required property var modelData

                    width: menuList.width
                    height: modelData.isSeparator ? 1 + Theme.padS : 30
                    radius: Theme.roundingMenu
                    // environment selection style (NetworkCenter parity)
                    color: !modelData.isSeparator && (menuRow.ListView.isCurrentItem || rowMA2.containsMouse) ? Theme.bgSelected : Theme.bgHover
                    border.width: Theme.borderWidth
                    border.color: !modelData.isSeparator && menuRow.ListView.isCurrentItem ? Theme.borderSelected : "transparent"
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
                            color: menuRow.modelData.enabled ? Theme.fg : Theme.fgDim
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
                anchors.centerIn: parent
                visible: root.view === 1 && root.menuRows.length === 0
                text: menuClient.busy ? "loading menu…" : (filterBar.visible ? "no matches" : "no options available")
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.fgMuted
            }
        }

            // quit confirm / status line (apps view only)
            Text {
                visible: root.view === 0 && (root.confirmQuitId !== "" || root.quitNote !== "")
                text: root.confirmQuitId !== "" ? "press x again to quit — Esc cancels" : root.quitNote
                font.family: Theme.fontFamily
                font.pixelSize: 10
                font.italic: true
                color: root.confirmQuitId !== "" ? Theme.warning : Theme.fgMuted
                Layout.alignment: Qt.AlignHCenter
            }

            // footer hints
            Text {
                text: "enter open/trigger · l forward · h back · j/k navigate · x quit · / filter"
                font.family: Theme.fontFamily
                font.pixelSize: 10
                font.italic: true
                color: Theme.fgDim
                Layout.alignment: Qt.AlignHCenter
            }
        }
    }
}
