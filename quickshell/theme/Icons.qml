pragma Singleton
import QtQuick

QtObject {
    // Wifi / Network — waybar/config.jsonc parity
    property string wifiConnected:    ""
    property string wifiEthernet:     ""
    property string wifiDisconnected: ""
    // Bluetooth — waybar parity
    property string bluetoothOn:      "󰂯"
    property string bluetoothOff:     "󰂲"
    // Audio — wireplumber
    property string audioVolume:      ""
    property string audioMuted:       "🔇"
    property string audioLow:         ""
    property string audioHigh:        ""
    // Keyboard
    property string keyboard:         "⌨"
    // Notification
    property string notification:     ""
    property string notificationMuted:"󰂛"
    // Battery
    property string batteryCharging:  "󰂄"
    property string batteryLevels:    "󰁻󰁼󰁾󰂀󰂂󰁹"
    // Workspaces
    property string workspaceDot:     ""
    // Perf
    property string cpu:              "󰻠"
    property string memory:           ""
    property string disk:             "💿"
    property string temp:             ""
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
    property string lock:             ""
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
