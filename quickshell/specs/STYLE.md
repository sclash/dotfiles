# Style Guide — Quickshell Desktop Environment

> Single source of truth for all bar + launcher styling.
> Derived from **Waybar legacy** (`waybar/style.css`, `waybar/config.jsonc`) and
> **Omarchy** iconography. Dark, minimal, meaningful — not strictly bound to either.

---

## 1. Design Principles

* **Dark & low-chrome.** The shell should recede; content stays primary.
* **Icons carry meaning; colour carries state.** Idle/muted is desaturated; active/warning/critical uses colour.
* **Rounded but restrained.** Bar pill + launcher card share one rounding scale.
* **Keyboard-first.** Every interactive surface has a visible focus ring.

---

## 2. Tokens — `theme/Theme.qml`

Implement as a QML singleton (`pragma Singleton`) with these properties:

### 2.1 Colours

Waybar uses `rgba(0,0,0,0.6)` pills with `@color7` / `@background` from Omarchy's
pywal-derived palette. Quickshell should expose explicit tokens rather than
relying on `pywal` colours at runtime (optional `pywal` integration later).

```qml
// theme/Theme.qml — colours
property color bgBar:           "#00000099"   // rgba(0,0,0,0.60) — bar pill
property color bgLauncher:      "#121212"  // same as bgBar
property color bgHover:         "#1e1e1e"
property color bgActive:        "#2a2a2a"
property color bgSelected:      "#2e2e2e"   // selected rows — dark, subtle
property color borderSelected:  "#4a4a4a"   // selected outline — muted grey
property color bgCritical:      "#f53c3c1a"  // critical wash

property color fg:              "#fAfBfC"    // primary text (waybar @color7)
property color fgMuted:         "#9aa0a6"    // secondary / inactive
property color fgDim:           "#595959aa"  // inactive workspace dot — waybar #595959aa

property color accent:          "#eaeaea"    // white — active/focus states
property color accentAlt:       "#8a8a8d"    // grey — secondary active
property color success:         "#eaeaea"    // white — on/connected
property color warning:         "#c63d3d"    // red — warning states
property color critical:        "#D35F5F"    // red — critical states
property color border:          "#59595955"  // subtle outline
property color borderActive:    "#ffffff1a"
property color shadow:          "#1a1a1aee"
```

**Mapping from Waybar:**

| Waybar token | Theme token |
|---|---|
| `@background` / `rgba(0,0,0,0.6)` | `bgBar` |
| `@color7` (`#fAfBfC`-ish) | `fg` |
| `rgba(89,89,89,0.67)` (inactive dot) | `fgDim` |
| `#ffffff` (active dot) | `fg` |
| `#eaeaea` (charging) | `success` |
| `#c63d3d` (warning) | `warning` |
| `#D35F5F` (critical/blink) | `critical` |
| `#eaeaea` (active/focus) | `accent` |

Provide a `QPalette` / `ThemeDerivation` hook for Omarchy themes that publish
`~/.cache/wal/colors-waybar.css` later — if `@background`/`@color7` exist, blend
them at 0.85 weight.

### 2.2 Rounding & Elevation

```qml
property int roundingBar:       10    // waybar: 10px on .modules-*
property int roundingLauncher:  12    // launchers slightly larger
property int roundingItem:       8
property int borderWidth:        1
property int shadowRange:        4
property int shadowPower:        3
property real barOpacity:        0.60
```

* Bar pill shadow: `range: 4, render_power: 3, color: shadow` (match `hyprland.lua` decoration).
* Launcher card: blur `size: 3, passes: 1` is compositor-level; QML card shadow `range: 12, color: #00000066`.

### 2.3 Spacing

```qml
property int padXS:  4
property int padS:   5   // waybar modules padding: 0 5px
property int padM:   7   // waybar modules-left padding: 7px
property int padL:  10   // bar outer margins: 10px
property int gapS:   4
property int gapM:   8
property int gapL:  12
property int barHeight: 30  // Bar.qml implicitHeight — keep
```

Bar outer margins: `margin: 10px 0 5px 10/0px` per Waybar `.modules-left/center/right`.

### 2.4 Typography

```qml
property string fontFamily: "JetBrainsMonoNL Nerd Font Mono"
property string fontFamilyFallback: "JetBrains Mono"
property int fontSizeBar:       14   // waybar: 14px
property int fontSizeLauncher:  13
property int fontSizeSmall:     11
property int fontWeightNormal:  400
property int fontWeightMedium:  500
```

* Icons are Nerd Font glyphs at the same `fontSize` as text — no separate icon font.

### 2.5 Motion

Match `hyprland.lua` curves. Reuse for drawer / launcher open.

```qml
property int durationFast:     150
property int durationNormal:   300   // waybar hover: 0.3s
property int durationDrawer:   600   // waybar group/expand: 600ms
property string easingStandard: "easeOutQuint"  // 0.23,1,0.32,1
property string easingEmphasis: "easeInOutCubic"
```

---

## 3. Icons — `theme/Icons.qml`

Central glyph map (Nerd Fonts + Waybar config). Builders import `Icons` and never hard-code glyphs.

```qml
// theme/Icons.qml — excerpt (glyphs from waybar/config.jsonc)
property string wifiConnected:    ""
property string wifiEthernet:     ""
property string wifiDisconnected: ""
property string bluetoothOn:      "󰂯"
property string bluetoothOff:     "󰂲"
property string audioVolume:      ""
property string audioMuted:       "🔇"
property string keyboard:         "⌨"
property string notification:     ""
property string batteryCharging:  "󰂄"
property string batteryPlugged:   "󰚥" // nf-md-power_plug — AC connected
property string notificationDnd:  "󰂠" // nf-md-bell_sleep — bell with zzz
property string batteryLevels:    "󰁻󰁼󰁾󰂀󰂂󰁹" // index by capacity tier
property string workspaceDot:     ""
property string cpu:              "󰻠"
property string memory:           ""
property string disk:             "💿"
property string temp:             ""
property string expand:           ""
property string collapse:         ""
property string vpn:              "󰖂"
property string search:           ""
property string close:            ""
property string check:            ""
property string warning:          ""
```

---

## 4. Bar Styling

* **Container:** `PanelWindow { color: "transparent" }` containing a `Rectangle` pill:
  `color: Theme.bgBar, radius: Theme.roundingBar, border { width: 1, color: Theme.border }`.
* **Left / Center / Right groups:** each is a `RowLayout` inside the pill with the same pill metrics Waybar uses:
  `padding: Theme.padM`, `spacing: Theme.gapS`.
* **Workspace dots:** `Text { text: Icons.workspaceDot, color: isActive ? Theme.fg : Theme.fgDim, font.pixelSize: 10 }`.
  Active dot full white; inactive `fgDim`; empty-but-persistent still `fgDim` (Waybar semantics).
* **Hover:** `color: Theme.fg` → on hover `color: Qt.rgba(1,1,1,0.7)` with `Behavior on color { ColorAnimation { duration: Theme.durationNormal } }`.
* **Critical blink:** `SequentialAnimation on color { loops: Animation.Infinite; ColorAnimation { to: Theme.critical; duration: 250 } ... }` (Waybar `@keyframes blink`).

---

## 5. Launcher Styling

* **Window:** `PopupWindow` or `PanelWindow { exclusionMode: ExclusionMode.Ignore, focusable: true }` centered via `anchors.centerIn: parent` on the screen.
* **Card:** `Rectangle { width: 560-640, radius: Theme.roundingLauncher, color: Theme.bgLauncher, border.color: Theme.borderActive, border.width: 1 }` with layer shadow.
* **Rows:** `radius: Theme.roundingItem`, hover `Theme.bgHover`, selected `Theme.bgSelected`, critical wash `Theme.bgCritical`.
* **Section headers:** `font.pixelSize: Theme.fontSizeSmall, color: Theme.fgMuted, textTransform: uppercase`.
* **Search/filter field:** rounded input, `placeholderTextColor: Theme.fgMuted`, focus ring `border.color: Theme.borderSelected`.
* **Focus ring:** `Rectangle { border.color: Theme.borderSelected; border.width: 1; visible: parent.activeFocus }`.
* **Scrollbar:** thin, `Theme.fgMuted` at 0.3 opacity, no arrows.
* **Icons per row:** left-aligned Nerd glyph + label; right-aligned status/meta (signal %, address, etc.) in `fgMuted`.

---

## 6. States

| State | FG | BG | Notes |
|---|---|---|---|
| Idle | `fg` | `bgBar`/`bgLauncher` | default |
| Hover | `fg` (brighter) | `bgHover` | 300ms transition |
| Active/selected | `fg` | `bgSelected` | vim cursor row |
| Good (<30% load) | `fg` | — | no tint |
| Warning (30–80%) | `warning` | — | Waybar thresholds |
| Critical (>80%, battery<20%) | `critical` | `bgCritical` wash | blink if bar perf, solid if launcher |
| Disabled / unavailable | `fgDim` | — | e.g., no Bluetooth adapter |
| Charging | `success` | — | battery only |
| Plugged (AC, not charging) | `fg` | — | battery only — plug glyph, no percent |

---

## 7. Dark-Mode Contract

* Default is dark. `Theme` does **not** switch to light automatically.
* GTK theming (`gsettings ... prefer-dark`, `adw-gtk3-dark` in `hyprland.lua`) is independent; Quickshell tokens stay dark regardless.
* If Omarchy/pywal palette is present, overlay it at low weight — never invert to light.

---

## 8. Do / Do Not

* **Do** use `Theme.*` tokens everywhere — no hard-coded colours in component files.
* **Do** use Nerd glyphs via `Icons.*` — no SVG/PNG icons.
* **Do** keep Waybar's minimal density — 14px bar, 13px launchers, no oversized chrome.
* **Do not** add light-theme variants or per-component colour overrides without updating `Theme.qml`.
* **Do not** copy Waybar CSS verbatim; translate semantics to QML properties.

---

## 9. Verification

* Visual: screenshots at 1920×1080, bar pill at top, launcher centered — compare to Waybar reference (`waybar/style.css`).
* Contrast: `fg` on `bgBar` ≥ 7:1 (AAA for 14px).
* No hard-coded hex outside `theme/Theme.qml` (grep check).
