pragma Singleton
import QtQuick

QtObject {
    // Omarchy matte-black inspired — dark, monochrome white/grey, low chrome
    // Derived from themes/matte-black/colors.toml + shell/commons
    // property color bgBar:           "#121212"      // background
    property color bgBar:           "#000000"      // background
    property color bgBarAlt:        "#1e1e1e"      // lighter_background
    // property color bgLauncher:      "#121212"      // same as bgBar
    property color bgLauncher:      "#000000"      // same as bgBar
    // property color bgHover:         "#2a2a2a"      // selection
    // property color bgActive:        "#333333"      // muted
    // property color bgSelected:      "#2e2e2e"      // selected rows — dark, subtle
    property color bgCritical:      "#631e1e"      // muted red wash
    
    property color bgHover:         "#000000"      // selection
    property color bgActive:        "#000000"      // muted
    property color bgSelected:      "#000000"      // selected rows — dark, subtle

    property color fg:              "#bebebe"      // foreground
    property color fgMuted:         "#8a8a8d"      // light_foreground
    property color fgDim:           "#555555"      // dark_foreground
    property color fgBright:        "#eaeaea"

    property color accent:          "#eaeaea"      // white — active/focus states
    property color accentAlt:       "#8a8a8d"      // grey — secondary active
    property color success:         "#eaeaea"      // white — on/connected
    property color warning:         "#c63d3d"      // red — warning states
    property color critical:        "#D35F5F"      // red — critical states
    property color border:          "#2a2a2a"
    property color borderActive:    "#3a3a3a"
    property color borderSelected:  "#4a4a4a"      // selected outline — muted grey
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
    property int wsAppIcon: 32       // per-workspace tray icon slot (AppTray parity)
    property int wsAppIconGlyph: 20  // icon glyph inside the slot
    property int wsAppIconMax: 3     // max inline icons per workspace (overflow → +n)

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
