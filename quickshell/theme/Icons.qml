pragma Singleton
import QtQuick
import Quickshell

QtObject {
    // Wifi / Network — waybar/config.jsonc parity
    property string wifiConnected:    "󰤨"
    property string wifiSignal4:      "󰤨"
    property string wifiSignal3:      "󰤥"
    property string wifiSignal2:      "󰤢"
    property string wifiSignal1:      "󰤟"
    property string wifiEthernet:     "󰈀"
    property string wifiDisconnected: "󰤭"
    // Bluetooth — waybar parity
    property string bluetoothOn:      "󰂯"
    property string bluetoothOff:     "󰂲"
    // Audio — intensity tiers
    property string audioVolume:      "󰕾"
    property string audioHigh:        "󰕾"
    property string audioMedium:      "󰖀"
    property string audioLow:         "󰕿"
    property string audioMuted:       "󰖁"
    // Keyboard
    property string keyboard:         "󰌌"
    // Notification
    property string notification:     ""
    property string notificationDnd:  "󰂠"
    property string notificationMuted:"󰂛"
    // Battery
    property string battery:          "󰁹"
    property string batteryCharging:  "󰂄"
    property string batteryPlugged:   "󰚥"
    property string batteryLevels:    "󰁻󰁼󰁾󰂀󰂂󰁹"
    // USB — MDI codepoints live above the BMP, and QML \u escapes consume
    // exactly 4 hex digits, so build them with String.fromCodePoint.
    property string usb:              String.fromCodePoint(0xF0553)   // nf-md-usb
    property string usbDrive:         String.fromCodePoint(0xF129E)   // nf-md-usb-flash-drive
    property string usbPort:          String.fromCodePoint(0xF11F0)   // nf-md-usb-port
    property string eject:            String.fromCodePoint(0xF01EA)   // nf-md-eject
    // Custom app icons — per-workspace tray overrides (see Workspaces.qml)
    property url appGhostty: Qt.resolvedUrl("../icons/ghostty-light.svg")
    property url appChrome: Qt.resolvedUrl("../icons/googlechrome-dark.svg")
    // Returns override url string for known appIds, else "" (caller falls back to theme lookup)
    function appIconOverride(appId) {
        var id = (appId || "").toLowerCase();
        if (id.indexOf("ghostty") !== -1 || id.indexOf("mitchellh") !== -1) return appGhostty;
        if (id.indexOf("chrome") !== -1 || id.indexOf("chromium") !== -1) return appChrome;
        return "";
    }

    // --- App icon resolution (see specs/bar/desktop-environnment/Bar-Desktop-Environment.md) ---
    //
    // A window's appId (xdg_toplevel.app_id / WM_CLASS) and its icon theme
    // name are *different namespaces* and often disagree — Tor Browser reports
    // "Tor Browser" but ships "tor-browser", ZenNotes reports "ZenNotes" but
    // ships "zennotes-desktop". Handing the raw appId to Quickshell.iconPath()
    // is therefore not enough: that function always returns a non-empty
    // "image://icon/<name>" url, and its provider paints a purple/black
    // placeholder rather than failing, so no Image ever errors out and no
    // fallback can trigger. Everything here returns "" instead of letting that
    // happen.

    // Desktop entries keyed by their declared StartupWMClass, which is the
    // spec-sanctioned bridge from a reported class to an Icon= name. Rebuilt by
    // QML binding whenever DesktopEntries rescans.
    readonly property var entryIcons: {
        const map = {};
        const apps = DesktopEntries.applications.values;
        for (let i = 0; i < apps.length; i++) {
            const e = apps[i];
            if (!e || !e.startupClass || !e.icon) continue;
            map[String(e.startupClass).toLowerCase()] = e.icon;
        }
        return map;
    }

    // appId -> resolved url (or "" for known-unresolvable). Mutated in place;
    // never bound to, so no invalidation needed.
    property var appIconCache: ({})

    // DesktopEntries scans asynchronously, so entryIcons is empty on the first
    // frame and filled in later. Drop the memo when that happens, otherwise the
    // negatives cached before the scan landed would stick for the session.
    onEntryIconsChanged: appIconCache = ({})

    // Theme names often differ from the appId by case/punctuation only
    // ("Tor Browser" -> "tor-browser"). Tried after the desktop-entry map.
    function appIconCandidates(id) {
        const low = String(id).toLowerCase();
        const dashed = low.replace(/[\s._]+/g, "-");
        return dashed === low ? [low] : [low, dashed];
    }

    // "" when the theme has no such icon, so callers can fall back. Passes
    // ready-made urls (the SVG overrides above) through untouched — note those
    // are `url` properties, so coerce to string before probing.
    function appIconUrl(icon) {
        if (icon === undefined || icon === null) return "";
        const s = String(icon);
        if (s === "") return "";
        if (s.indexOf("://") !== -1) return s;
        if (s.indexOf("/") === 0) return "file://" + s;
        return Quickshell.iconPath(s, true);
    }

    // Resolve a window's icon url, or "" to let the caller render its glyph.
    // `appId` is the Wayland app_id; `wmClass` the raw Hyprland WM_CLASS,
    // used for XWayland windows that expose no wayland handle.
    function appIconFor(appId, wmClass) {
        const ids = [appId, wmClass];
        for (let i = 0; i < ids.length; i++) {
            const raw = String(ids[i] || "");
            if (raw === "") continue;
            const key = raw.toLowerCase();

            const hit = Icons.appIconCache[key];
            if (hit !== undefined) {
                if (hit !== "") return hit;
                continue;
            }

            let icon = appIconOverride(raw);
            if (icon === "" && entryIcons[key] !== undefined)
                icon = entryIcons[key];
            if (icon === "") {
                const candidates = appIconCandidates(raw);
                for (let c = 0; c < candidates.length; c++) {
                    if (Quickshell.hasThemeIcon(candidates[c])) {
                        icon = candidates[c];
                        break;
                    }
                }
            }

            const url = appIconUrl(icon);
            Icons.appIconCache[key] = url;
            if (url !== "") return url;
        }
        return "";
    }
    // Menus (tray context menu) — MDI chevrons, see USB note above
    property string chevronLeft:      String.fromCodePoint(0xF0141)   // nf-md-chevron-left
    property string chevronRight:     String.fromCodePoint(0xF0142)   // nf-md-chevron-right
    // Workspaces
    property string workspaceDot:     ""
    property string window:           "󰘔"
    // Perf
    property string cpu:              "󰻠"
    property string memory:           "󰍛"
    property string disk:             "󰋊"
    property string temp:             "󰔏"
    property string expand:           ""
    property string collapse:         ""
    // VPN
    property string vpn:              "󰖂"
    // Network traffic
    property string download:         ""
    property string upload:           ""
    // Common
    property string search:           ""
    property string close:            ""
    property string check:            ""
    property string warning:          ""
    property string display:          "󰍹"
    property string laptop:           "󰌢"
    property string key:              ""
    property string power:            ""
    property string reboot:           "󰜉"
    property string sleep:            "󰒲"
    property string planeOn:          "󱤱"
    property string planeOff:         "󰀝"
    property string logout:           "󰍃"
    property string lock:             "󰌾"
    property string eye:              "\uf06e"
    property string eyeOff:           "\uf070"
    property string settings:         ""
    property string network:          ""
    property string bluetooth:        "󰂯"
    property string audio:            ""
    property string app:              ""
    property string shade:            "󰖂"
    property string monitor:          "󰍹"
    property string bell:             ""
    property string keys:             ""
    property string shutdown:         ""
    property string control:          "󰀻"
    property string calendar:         ""
}
