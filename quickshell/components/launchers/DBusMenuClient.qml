import QtQuick
import Quickshell.Io

// DBusMenu client backed by busctl. Required because quickshell 0.3.0 cannot
// assign a DBusMenu submenu handle to QsMenuOpener.menu ("Unable to assign
// qs::dbus::dbusmenu::DBusMenu to qs::menu::QsMenuHandle") — submenus never
// rendered. This client speaks org.canonical.dbusmenu directly:
// resolve SNI endpoints → AboutToShow (lazy menus) → GetLayout → parse.
Item {
    id: root

    property string itemId: ""
    property string svc: ""
    property string menuPath: ""
    property int currentId: 0
    property string currentLabel: ""
    property var entries: [] // [{ id, label, enabled, isSeparator, hasChildren, toggleType, toggleState }]
    property var stack: [] // [{ id, label }] — submenu navigation history (TrayManager)
    property bool busy: false
    // accordion expansion (TrayMenu): children of one expanded parent
    property var childEntries: []
    property int expandedId: -1
    property string expandedLabel: ""
    property bool childBusy: false
    property string fetchMode: "replace"
    readonly property bool canGoBack: root.stack.length > 0
    readonly property string breadcrumb: {
        let parts = [];
        for (let i = 0; i < root.stack.length; i++)
            if (root.stack[i].label)
                parts.push(root.stack[i].label);
        if (root.currentLabel)
            parts.push(root.currentLabel);
        return parts.join(" › ");
    }

    function openForItem(item) {
        root.itemId = item ? item.id : "";
        root.svc = "";
        root.menuPath = "";
        root.stack = [];
        root.currentId = 0;
        root.currentLabel = "";
        root.entries = [];
        // reset accordion state — otherwise expandEntry()'s guard refuses to
        // re-expand the same parent after the popup was closed and reopened
        root.expandedId = -1;
        root.expandedLabel = "";
        root.childEntries = [];
        root.childBusy = false;
        root.fetchMode = "replace";
        if (root.itemId !== "") {
            root.busy = true;
            resolveProc.command = ["sh", "-c", root.resolveScript];
            resolveProc.running = true;
        }
    }

    function drill(index) {
        const e = root.entries[index];
        if (!e || !e.hasChildren)
            return;
        root.stack = root.stack.concat([{
            "id": root.currentId,
            "label": root.currentLabel
        }]);
        root.currentId = e.id;
        root.currentLabel = e.label;
        root.entries = [];
        root.fetch(e.id);
    }

    function back() {
        if (root.stack.length === 0)
            return false;
        const top = root.stack[root.stack.length - 1];
        root.stack = root.stack.slice(0, -1);
        root.currentId = top.id;
        root.currentLabel = top.label;
        root.fetch(top.id); // refetch — toggle states may have changed
        return true;
    }

    // accordion API (TrayMenu): expand children of one parent in place
    function expandEntry(e) {
        if (!e || !e.hasChildren)
            return;
        if (root.expandedId === e.id)
            return;
        root.expandedId = e.id;
        root.expandedLabel = e.label;
        root.childEntries = [];
        root.childBusy = true;
        root.fetch(e.id, "expand");
    }

    function collapseExpanded() {
        root.expandedId = -1;
        root.expandedLabel = "";
        root.childEntries = [];
        root.childBusy = false;
    }

    function trigger(index) {
        root.triggerEntry(root.entries[index]);
    }

    function triggerEntry(e) {
        if (!e || e.isSeparator || !e.enabled)
            return;
        if (e.hasChildren) {
            root.expandEntry(e);
            return;
        }
        root.busy = true;
        root.pendingRefetch = true;
        eventProc.command = ["sh", "-c", "timeout 3 busctl --user call " + root.svc + " " + root.menuPath + " com.canonical.dbusmenu Event isvu " + e.id + " clicked v s '' 0 2>/dev/null"];
        eventProc.running = true;
    }

    function fetch(id, mode) {
        root.fetchMode = mode || "replace";
        root.busy = true;
        fetchProc.command = ["sh", "-c", "busctl --user call " + root.svc + " " + root.menuPath + " com.canonical.dbusmenu AboutToShow i " + id + " >/dev/null 2>&1; sleep 0.12; timeout 3 busctl --user call " + root.svc + " " + root.menuPath + " com.canonical.dbusmenu GetLayout iias " + id + " 1 6 label enabled children-display type toggle-type toggle-state 2>/dev/null"];
        fetchProc.running = true;
    }

    function refresh() {
        root.fetch(root.currentId);
    }

    // --- internals ------------------------------------------------------
    property bool pendingRefetch: false

    readonly property string resolveScript: "items=$(busctl --user call org.kde.StatusNotifierWatcher /StatusNotifierWatcher org.freedesktop.DBus.Properties Get ss org.kde.StatusNotifierWatcher RegisteredStatusNotifierItems 2>/dev/null | tr -d '\"')\n" + "for sp in $items; do\n" + "  svc=${sp%%/*}; path=/${sp#*/}\n" + "  id=$(timeout 3 busctl --user call \"$svc\" \"$path\" org.freedesktop.DBus.Properties Get ss org.kde.StatusNotifierItem Id 2>/dev/null | tr -d '\"' | awk '{print $NF}')\n" + "  if [ \"$id\" = \"" + root.itemId + "\" ]; then\n" + "    menu=$(timeout 3 busctl --user call \"$svc\" \"$path\" org.freedesktop.DBus.Properties Get ss org.kde.StatusNotifierItem Menu 2>/dev/null | tr -d '\"' | awk '{print $NF}')\n" + "    echo \"$svc $menu\"\n" + "    exit 0\n" + "  fi\n" + "done\n";

    function unescapeValue(s) {
        // busctl escapes non-ASCII as \NNN octal (UTF-8 bytes) and \" \\ \n
        let out = "";
        let bytes = [];
        let i = 0;
        while (i < s.length) {
            const c = s.charAt(i);
            if (c === "\\" && i + 1 < s.length) {
                const n = s.charAt(i + 1);
                if (n >= "0" && n <= "7") {
                    bytes.push(parseInt(s.substr(i + 1, 3), 8));
                    i += 4;
                    continue;
                }
                if (n === "\\") {
                    if (bytes.length) {
                        out += utf8Decode(bytes);
                        bytes = [];
                    }
                    out += "\\";
                    i += 2;
                    continue;
                }
                if (n === "\"" || n === "n") {
                    if (bytes.length) {
                        out += utf8Decode(bytes);
                        bytes = [];
                    }
                    out += (n === "n" ? "\n" : "\"");
                    i += 2;
                    continue;
                }
            }
            if (bytes.length) {
                out += utf8Decode(bytes);
                bytes = [];
            }
            out += c;
            i++;
        }
        if (bytes.length)
            out += utf8Decode(bytes);
        // strip libdbusmenu mnemonic underscores ("__" = literal underscore)
        return out.replace(/_([^_])/g, "$1").replace(/__/g, "_");
    }

    function utf8Decode(bytes) {
        let out = "";
        let i = 0;
        while (i < bytes.length) {
            const b = bytes[i];
            if (b < 0x80) {
                out += String.fromCharCode(b);
                i += 1;
            } else if (b < 0xE0) {
                out += String.fromCharCode(((b & 0x1F) << 6) | (bytes[i + 1] & 0x3F));
                i += 2;
            } else if (b < 0xF0) {
                out += String.fromCharCode(((b & 0x0F) << 12) | ((bytes[i + 1] & 0x3F) << 6) | (bytes[i + 2] & 0x3F));
                i += 3;
            } else {
                out += String.fromCharCode(((b & 0x07) << 18) | ((bytes[i + 1] & 0x3F) << 12) | ((bytes[i + 2] & 0x3F) << 6) | (bytes[i + 3] & 0x3F));
                i += 4;
            }
        }
        return out;
    }

    function parseLayout(text) {
        const rows = [];
        if (!text)
            return rows;
        const segs = text.split("(ia{sv}av)");
        // segs[0] = "u<revision>"; segs[1] = the ROOT tuple (the menu itself) —
        // parsing it produced a blank row at the top of every menu.
        // Real child tuples start at segs[2].
        for (let i = 2; i < segs.length; i++) {
            const s = segs[i].trim();
            const idm = s.match(/^(\d+)\s+/);
            if (!idm)
                continue;
            const id = parseInt(idm[1]);
            if (id === 0)
                continue; // defensive: never render the root
            const e = {
                "id": id,
                "label": "",
                "enabled": true,
                "isSeparator": false,
                "hasChildren": false,
                "toggleType": "",
                "toggleState": 0
            };
            let rest = s.slice(idm[0].length);
            // consume the property-count integer before the first key
            const cm = rest.match(/^(\d+)\s+/);
            if (!cm)
                continue;
            rest = rest.slice(cm[0].length);
            for (;;) {
                rest = rest.replace(/^\s+/, "");
                const km = rest.match(/^"((?:[^"\\]|\\.)*)"\s+(s|b|i|u|v)\s+/);
                if (!km)
                    break;
                const key = km[1];
                rest = rest.slice(km[0].length);
                let vm;
                if (km[2] === "s") {
                    vm = rest.match(/^"((?:[^"\\]|\\.)*)"\s*/);
                    if (!vm)
                        break;
                    const v = root.unescapeValue(vm[1]);
                    if (key === "label")
                        e.label = v;
                    else if (key === "type")
                        e.type = v;
                    else if (key === "children-display")
                        e.childrenDisplay = v;
                    else if (key === "toggle-type")
                        e.toggleType = v;
                    rest = rest.slice(vm[0].length);
                } else if (km[2] === "b") {
                    vm = rest.match(/^(true|false)\s*/);
                    if (!vm)
                        break;
                    if (key === "enabled")
                        e.enabled = vm[1] === "true";
                    rest = rest.slice(vm[0].length);
                } else if (km[2] === "i" || km[2] === "u") {
                    vm = rest.match(/^(-?\d+)\s*/);
                    if (!vm)
                        break;
                    if (key === "toggle-state")
                        e.toggleState = parseInt(vm[1]);
                    rest = rest.slice(vm[0].length);
                } else {
                    vm = rest.match(/^<[^<>]*>\s*/);
                    rest = vm ? rest.slice(vm[0].length) : "";
                }
            }
            e.isSeparator = e.type === "separator";
            e.hasChildren = e.childrenDisplay === "submenu";
            rows.push(e);
        }
        return rows;
    }

    function onResolve(text) {
        const line = (text || "").trim();
        const sp = line.indexOf(" ");
        if (sp === -1) {
            root.busy = false;
            return;
        }
        root.svc = line.slice(0, sp);
        root.menuPath = line.slice(sp + 1);
        root.currentId = 0;
        root.currentLabel = "";
        root.fetch(0);
    }

    function onFetch(text) {
        const rows = root.parseLayout(text.trim());
        if (root.fetchMode === "expand") {
            root.childEntries = rows;
            root.childBusy = false;
        } else {
            root.entries = rows;
            root.busy = false;
        }
    }

    function onEvent() {
        if (root.pendingRefetch) {
            root.pendingRefetch = false;
            root.fetch(root.currentId);
        } else {
            root.busy = false;
        }
    }

    Process {
        id: resolveProc

        stdout: StdioCollector {
            onStreamFinished: root.onResolve(text)
        }
        onExited: function (exitCode) {
            if (exitCode !== 0)
                root.busy = false;
        }
    }

    Process {
        id: fetchProc

        stdout: StdioCollector {
            onStreamFinished: root.onFetch(text)
        }
        onExited: function (exitCode) {
            if (exitCode !== 0) {
                if (root.fetchMode === "expand") {
                    root.childEntries = [];
                    root.childBusy = false;
                } else {
                    root.entries = [];
                    root.busy = false;
                }
            }
        }
    }

    Process {
        id: eventProc

        onExited: root.onEvent()
    }
}
