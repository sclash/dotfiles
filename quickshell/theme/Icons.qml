pragma Singleton
import QtQuick

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
    property string batteryCharging:  "󰂄"
    property string batteryPlugged:   "󰚥"
    property string batteryLevels:    "󰁻󰁼󰁾󰂀󰂂󰁹"
    // USB
    property string usb:              "\uf0553"
    property string usbDrive:         "\uf129e"
    property string usbPort:          "\uf11f0"
    property string eject:            "\uf01ea"
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
    // Common
    property string search:           ""
    property string close:            ""
    property string check:            ""
    property string warning:          ""
    property string display:          "󰍹"
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
}
