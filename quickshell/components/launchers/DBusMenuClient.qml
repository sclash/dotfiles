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
        root.drillEntry(root.entries[index]);
    }

    // object-based drill — REQUIRED when the caller navigates a filtered view:
    // filtered-row indices do not map onto root.entries indices
    function drillEntry(e) {
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

    // --- graceful quit --------------------------------------------------
    // outcome: "OK menu <entryId>" | "OK term <pid>" | "FAIL <reason>"
    signal quitFinished(string outcome)
    property string quitStatus: ""

    // python: stdin = GetLayout --json=short; stdout = quit entry id or NOQUIT.
    // prefers top-level Quit/Exit/Shutdown; falls back to a bare Close label;
    // separators, disabled and invisible entries never match.
    readonly property string quitPython: "import json,sys,re\nraw=sys.stdin.read()\ntry:\n  obj=json.loads(raw)\n  data=obj.get(\"data\",[])\n  layout=data[1] if len(data)>1 else None\n  kids=layout[2] if layout and len(layout)>2 else []\n  def lab(p):\n    l=(p.get(\"label\") or {}).get(\"data\",\"\") or \"\"\n    return re.sub(r\"_([^_])\",r\"\\1\",l).replace(\"__\",\"_\")\n  best=\"\"\n  fall=\"\"\n  for c in kids:\n    d=c.get(\"data\",[])\n    if len(d)<2:\n      continue\n    pr=d[1] or {}\n    if (pr.get(\"visible\") or {}).get(\"data\",True) is False:\n      continue\n    if (pr.get(\"enabled\") or {}).get(\"data\",True) is False:\n      continue\n    if (pr.get(\"type\") or {}).get(\"data\",\"\"):\n      continue\n    t=lab(pr).strip().lower()\n    if re.match(r\"^(quit|exit|shutdown)\\b\",t):\n      best=str(d[0])\n      break\n    if (not fall) and re.match(r\"^close\\b\",t):\n      fall=str(d[0])\n  print(best or fall or \"NOQUIT\")\nexcept Exception:\n  print(\"NOQUIT\")\n";

    function quitAppById(rawId) {
        const clean = ((rawId || "").toString()).replace(/[^A-Za-z0-9._-]/g, "");
        if (clean === "")
            return;
        root.quitStatus = "Quitting " + clean + "…";
        const script = "IID=\"" + clean + "\"\n"
            + "svc=\"\"; menu=\"\"\n"
            + "items=$(busctl --user call org.kde.StatusNotifierWatcher /StatusNotifierWatcher org.freedesktop.DBus.Properties Get ss org.kde.StatusNotifierWatcher RegisteredStatusNotifierItems 2>/dev/null | tr -d '\"')\n"
            + "for sp in $items; do\n"
            + "  case \"$sp\" in */*) ;;\n"
            + "    *) continue;;\n"
            + "  esac\n"
            + "  s=${sp%%/*}; p=/${sp#*/}\n"
            + "  id=$(timeout 3 busctl --user call \"$s\" \"$p\" org.freedesktop.DBus.Properties Get ss org.kde.StatusNotifierItem Id 2>/dev/null | sed -n 's/.*\"\\(.*\\)\"/\\1/p')\n"
            + "  if [ \"$id\" = \"$IID\" ]; then svc=\"$s\"; menu=$(timeout 3 busctl --user call \"$s\" \"$p\" org.freedesktop.DBus.Properties Get ss org.kde.StatusNotifierItem Menu 2>/dev/null | sed -n 's/.*\"\\(.*\\)\"/\\1/p'); break; fi\n"
            + "done\n"
            + "[ -z \"$svc\" ] && { echo \"FAIL noresolve\"; exit 0; }\n"
            + "busctl --user call \"$svc\" \"$menu\" com.canonical.dbusmenu AboutToShow i 0 >/dev/null 2>&1\n"
            + "qid=$(timeout 3 busctl --user --json=short call \"$svc\" \"$menu\" com.canonical.dbusmenu GetLayout iias 0 1 7 label enabled children-display type toggle-type toggle-state visible 2>/dev/null | python3 -c '" + root.quitPython + "')\n"
            + "if [ -n \"$qid\" ] && [ \"$qid\" != \"NOQUIT\" ]; then timeout 3 busctl --user call \"$svc\" \"$menu\" com.canonical.dbusmenu Event isvu \"$qid\" clicked v s '' 0 >/dev/null 2>&1; echo \"OK menu $qid\"; exit 0; fi\n"
            + "pid=$(busctl --user call org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus GetConnectionUnixProcessID s \"$svc\" 2>/dev/null | awk '{print $NF}')\n"
            + "case \"$pid\" in ''|*[!0-9]*) echo \"FAIL nopid\"; exit 0;; esac\n"
            + "if [ \"$pid\" = \"1\" ]; then echo \"FAIL refused\"; exit 0; fi\n"
            + "kill -TERM \"$pid\" 2>/dev/null && echo \"OK term $pid\" || echo \"FAIL kill\"\n";
        quitProc.command = ["sh", "-c", script];
        quitProc.running = true;
    }

    function onQuitOutput(text) {
        const line = (text || "").trim().split("\n")[0] || "";
        root.quitStatus = line;
        root.quitFinished(line);
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

    // JSON parser for GetLayout — VLC ships large `icon-data ay …` blobs that
    // break the legacy busctl-text parser (labels came back empty, so both
    // TrayMenu and TrayManager showed blank rows). --json=short + python3
    // decodes props natively; falls back to parseLayout() text parsing.
    readonly property string fetchPython: "import json,sys,re\nraw=sys.stdin.read()\ntry:\n  obj=json.loads(raw)\n  data=obj.get(\"data\",[])\n  layout=data[1] if len(data)>1 else None\n  children=layout[2] if layout and len(layout)>2 else []\n  out=[]\n  for c in children:\n    d=c.get(\"data\",[])\n    if len(d)<2:\n      continue\n    cid=d[0]\n    props=d[1] or {}\n    def get(k,default=None):\n      v=props.get(k)\n      return v.get(\"data\",default) if isinstance(v,dict) else default\n    label=get(\"label\",\"\") or \"\"\n    label=re.sub(r\"_([^_])\",r\"\\1\",label).replace(\"__\",\"_\")\n    enabled=get(\"enabled\",True)\n    if enabled is None:\n      enabled=True\n    typ=get(\"type\",\"\") or \"\"\n    cdisp=get(\"children-display\",\"\") or \"\"\n    ttype=get(\"toggle-type\",\"\") or \"\"\n    tstate=get(\"toggle-state\",0) or 0\n    vis=get(\"visible\",True)\n    if vis is None:\n      vis=True\n    out.append({\"id\":cid,\"label\":label,\"enabled\":bool(enabled),\"type\":typ,\"childrenDisplay\":cdisp,\"toggleType\":ttype,\"toggleState\":int(tstate) if isinstance(tstate,int) else 0,\"visible\":bool(vis)})\n  print(json.dumps(out))\nexcept Exception as e:\n  print(\"[]\")\n";

    function fetch(id, mode) {
        root.fetchMode = mode || "replace";
        root.busy = true;
        fetchProc.command = ["sh", "-c", "busctl --user call " + root.svc + " " + root.menuPath + " com.canonical.dbusmenu AboutToShow i " + id + " >/dev/null 2>&1; sleep 0.12; timeout 3 busctl --user --json=short call " + root.svc + " " + root.menuPath + " com.canonical.dbusmenu GetLayout iias " + id + " 1 7 label enabled children-display type toggle-type toggle-state visible 2>/dev/null | python3 -c '" + root.fetchPython + "'"];
        fetchProc.running = true;
    }

    function refresh() {
        root.fetch(root.currentId);
    }

    // --- internals ------------------------------------------------------
    property bool pendingRefetch: false

    readonly property string resolveScript: "items=$(busctl --user call org.kde.StatusNotifierWatcher /StatusNotifierWatcher org.freedesktop.DBus.Properties Get ss org.kde.StatusNotifierWatcher RegisteredStatusNotifierItems 2>/dev/null | tr -d '\"')\n" + "for sp in $items; do\n" + "  case \"$sp\" in */*) ;;\n" + "    *) continue;;\n" + "  esac\n" + "  svc=${sp%%/*}; path=/${sp#*/}\n" + "  id=$(timeout 3 busctl --user call \"$svc\" \"$path\" org.freedesktop.DBus.Properties Get ss org.kde.StatusNotifierItem Id 2>/dev/null | sed -n 's/.*\"\\(.*\\)\"/\\1/p')\n" + "  if [ \"$id\" = \"" + root.itemId + "\" ]; then\n" + "    menu=$(timeout 3 busctl --user call \"$svc\" \"$path\" org.freedesktop.DBus.Properties Get ss org.kde.StatusNotifierItem Menu 2>/dev/null | sed -n 's/.*\"\\(.*\\)\"/\\1/p')\n" + "    echo \"$svc $menu\"\n" + "    exit 0\n" + "  fi\n" + "done\n";

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
                // Legacy text fallback: skip array props (VLC `icon-data ay …`)
                // before the scalar parser — otherwise the loop breaks and the
                // entry's later `label` is never read (blank rows).
                const am = rest.match(/^"((?:[^"\\]|\\.)*)"\s+(a[A-Za-z{}()]*)\s+/);
                if (am) {
                    rest = rest.slice(am[0].length);
                    const at = am[2];
                    if (at === "ay" || at === "au" || at === "ai" || at === "ax" || at === "ayay") {
                        const cn = rest.match(/^(\d+)\s*/);
                        if (cn) {
                            rest = rest.slice(cn[0].length);
                            let n = parseInt(cn[1]);
                            while (n-- > 0) {
                                const nm = rest.match(/^(-?\d+)\s*/);
                                if (!nm)
                                    break;
                                rest = rest.slice(nm[0].length);
                            }
                        }
                    } else if (at === "as") {
                        const cn2 = rest.match(/^(\d+)\s*/);
                        if (cn2) {
                            rest = rest.slice(cn2[0].length);
                            let n2 = parseInt(cn2[1]);
                            while (n2-- > 0) {
                                const sm = rest.match(/^"((?:[^"\\]|\\.)*)"\s*/);
                                if (!sm)
                                    break;
                                rest = rest.slice(sm[0].length);
                            }
                        }
                    }
                    continue;
                }
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

    function fromJsonEntries(arr) {
        const rows = [];
        for (let i = 0; i < arr.length; i++) {
            const j = arr[i];
            if (j.visible === false)
                continue; // DBusMenu visible=false → hidden (VLC has none hidden now, others do)
            rows.push({
                "id": j.id,
                "label": j.label || "",
                "enabled": j.enabled !== false,
                "isSeparator": j.type === "separator",
                "hasChildren": j.childrenDisplay === "submenu",
                "toggleType": j.toggleType || "",
                "toggleState": j.toggleState || 0
            });
        }
        return rows;
    }

    function onFetch(text) {
        const t = (text || "").trim();
        // Preferred: JSON array from fetchPython. Fall back to legacy text parser.
        if (t.startsWith("[") || t.startsWith("{")) {
            try {
                const arr = JSON.parse(t);
                const rows = root.fromJsonEntries(Array.isArray(arr) ? arr : []);
                if (root.fetchMode === "expand") {
                    root.childEntries = rows;
                    root.childBusy = false;
                } else {
                    root.entries = rows;
                    root.busy = false;
                }
                return;
            } catch (e) {}
        }
        const rows = root.parseLayout(t);
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

    Process {
        id: quitProc

        stdout: StdioCollector {
            onStreamFinished: root.onQuitOutput(text)
        }
        onExited: function (exitCode) {
            if (exitCode !== 0 && root.quitStatus.startsWith("Quitting")) {
                root.onQuitOutput("FAIL quitproc");
            }
        }
    }
}
