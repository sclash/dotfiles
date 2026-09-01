pragma Singleton
import QtQuick

QtObject {
    // Omarchy matte-black inspired — dark, warm accent, low chrome
    // Derived from themes/matte-black/colors.toml + shell/commons
    property color bgBar:           "#121212"      // background
    property color bgBarAlt:        "#1e1e1e"      // lighter_background
    property color bgLauncher:      "#1a1a1a"      // slightly lighter than bar for contrast
    property color bgHover:         "#2a2a2a"      // selection
    property color bgActive:        "#333333"      // muted
    property color bgCritical:      "#631e1e"      // muted red wash

    property color fg:              "#bebebe"      // foreground
    property color fgMuted:         "#8a8a8d"      // light_foreground
    property color fgDim:           "#555555"      // dark_foreground
    property color fgBright:        "#eaeaea"

    property color accent:          "#e68e0d"      // accent (orange)
    property color accentAlt:       "#f59e0b"      // bright_blue
    property color success:         "#FFC107"      // green
    property color warning:         "#c63d3d"      // orange
    property color critical:        "#D35F5F"      // red
    property color border:          "#2a2a2a"
    property color borderActive:    "#3a3a3a"
    property color shadow:          "#0a0a0a"
    property color overlay:         "#00000099"    // dim overlay

    // Rounding — Omarchy uses Style.cornerRadius (Hyprland rounding 7) but bar is flat
    property int roundingBar:       0             // flat top bar, no pill
    property int roundingLauncher:  16            // more rounded for floating cards
    property int roundingItem:      10
    property int borderWidth:       1
    property int shadowRange:       16
    property int shadowPower:       3
    property real barOpacity:       1.0

    // Spacing — Omarchy Style.spacing scale
    property int padXS:  4
    property int padS:   6
    property int padM:   10
    property int padL:   16
    property int gapS:   6
    property int gapM:   10
    property int gapL:   16
    property int barHeight: 32
    property int barIconSlot: 32
    property int barIconSize: 18

    // Typography — Omarchy Style.font, JetBrainsMono
    property string fontFamily: "JetBrainsMono Nerd Font"
    property string fontFamilyFallback: "JetBrains Mono"
    property int fontSizeBar:       15
    property int fontSizeBarIcon:   18
    property int fontSizeLauncher:  14
    property int fontSizeSmall:     11
    property int fontWeightNormal:  400
    property int fontWeightMedium:  600
    property string dateFormat:     "ddd MMM dd  hh:mm:ss"

    // Motion
    property int durationFast:     120
    property int durationNormal:   220
    property int durationDrawer:   400
    property string easingStandard: "easeOutCubic"
    property string easingEmphasis: "easeInOutCubic"
}
