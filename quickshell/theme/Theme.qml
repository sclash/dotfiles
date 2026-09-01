pragma Singleton
import QtQuick

QtObject {
    // STYLE.md single source of truth — Waybar legacy + Omarchy icons
    // Derived from waybar/style.css rgba(0,0,0,0.6) pills — see STYLE.md:29
    property color bgBar:           "#00000099"   // rgba(0,0,0,0.60) — bar pill (STYLE 2.1)
    property color bgBarAlt:        "#1e1e1e"
    property color bgLauncher:      "#0f0f0fcc"  // STYLE 2.1
    property color bgHover:         "#1e1e1e"
    property color bgActive:        "#2a2a2a"
    property color bgCritical:      "#f53c3c1a"  // critical wash

    property color fg:              "#fafbfc"    // primary (STYLE fg)
    property color fgMuted:         "#9aa0a6"
    property color fgDim:           "#595959aa"  // inactive dot 0.67
    property color fgBright:        "#eaeaea"

    property color accent:          "#1189f2"    // temperature / links (STYLE accent)
    property color accentAlt:       "#f59e0b"
    property color success:         "#26A65B"   // charging / connected
    property color warning:         "#ffbe61"   // 30-60% load
    property color critical:        "#f53c3c"
    property color border:          "#59595955"
    property color borderActive:    "#ffffff1a"
    property color shadow:          "#1a1a1aee"
    property color overlay:         "#00000099"    // dim overlay for launchers

    // Rounding & elevation — STYLE 2.2
    property int roundingBar:       10            // waybar: 10px on .modules-*
    property int roundingLauncher:  12
    property int roundingItem:       8
    property int borderWidth:        1
    property int shadowRange:        4
    property int shadowPower:        3
    property real barOpacity:        0.60

    // Spacing — STYLE 2.3 (waybar modules padding/margins)
    property int padXS:  4
    property int padS:   5   // waybar modules padding: 0 5px
    property int padM:   7   // waybar modules-left padding: 7px
    property int padL:  10   // bar outer margins: 10px
    property int gapS:   4
    property int gapM:   8
    property int gapL:  12
    property int barHeight: 30
    property int barIconSlot: 28
    property int barIconSize: 16

    // Typography — STYLE 2.4
    property string fontFamily: "JetBrainsMonoNL Nerd Font Mono"
    property string fontFamilyFallback: "JetBrains Mono"
    property int fontSizeBar:       14   // waybar: 14px
    property int fontSizeBarIcon:   16
    property int fontSizeLauncher:  13
    property int fontSizeSmall:     11
    property int fontWeightNormal:  400
    property int fontWeightMedium:  500
    property string dateFormat:     "ddd MMM dd  hh:mm:ss"

    // Motion — STYLE 2.5
    property int durationFast:     150
    property int durationNormal:   300   // waybar hover: 0.3s
    property int durationDrawer:   600   // waybar group/expand: 600ms
    property string easingStandard: "easeOutQuint"  // 0.23,1,0.32,1
    property string easingEmphasis: "easeInOutCubic"
}
