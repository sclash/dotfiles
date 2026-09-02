# Style Guide — Quickshell Desktop Environment

> Single source of truth for all bar + launcher styling.
> Derived from **Omarchy matte-black** palette (`themes/matte-black/colors.toml`),
> **Waybar legacy** behaviour, and **Nerd Font** iconography.
> Dark, minimal, flat bar + rounded floating cards.

---

## 1. Design Principles

* **Dark & low-chrome.** The shell should recede; content stays primary.
* **Icons carry meaning; colour carries state.** Idle/muted is desaturated white/grey; warning/critical uses red.
* **Flat bar, rounded cards.** Bar is a flat strip (`roundingBar: 0`); launchers and toasts are floating cards (`roundingLauncher` / `roundingItem`).
* **Keyboard-first.** Every interactive surface has a visible selection ring (border, not background — see §6).

---

## 2. Tokens — `theme/Theme.qml`

Implement as a QML singleton (`pragma Singleton`) with these properties:

### 2.1 Colours

Omarchy matte-black derived — monochrome white/grey, low chrome. Quickshell
exposes explicit tokens rather than reading pywal colours at runtime.

```qml
// theme/Theme.qml — colours
property color bgBar:           "#000000"      // background — flat bar, toasts, icon chips
property color bgBarAlt:        "#1e1e1e"      // lighter_background — alternate surfaces
property color bgLauncher:      "#000000"      // same as bgBar
property color bgHover:         "#000000"      // hover keeps bg — border signals hover
property color bgActive:        "#000000"      // muted surface (fields, chips)
property color bgSelected:      "#000000"      // selected rows — border carries selection
property color bgCritical:      "#631e1e"      // critical wash (muted red)

property color fg:              "#bebebe"      // foreground
property color fgMuted:         "#8a8a8d"      // secondary / meta
property color fgDim:           "#555555"      // tertiary / footer hints
property color fgBright:        "#eaeaea"      // emphasis

property color accent:          "#eaeaea"      // white — active/focus states
property color accentAlt:       "#8a8a8d"      // grey — secondary active
property color success:         "#eaeaea"      // white — on/connected
property color warning:         "#c63d3d"      // red — warning states
property color critical:        "#D35F5F"      // red — critical states
property color border:          "#2a2a2a"      // subtle outline
property color borderActive:    "#3a3a3a"      // card outline
property color borderSelected:  "#4a4a4a"      // selected outline — muted grey
property color shadow:          "#0a0a0a"
property color overlay:         "#00000099"    // full-screen dim behind launchers
```

**State is conveyed by borders, not backgrounds.** `bgHover`/`bgActive`/`bgSelected`
all equal `bgLauncher` (`#000000`), so rows render `transparent` and switch border:

* selected → `borderSelected`, 2 px
* hover → `border`, 1 px
* idle → `border`, 1 px

**Mapping from Omarchy `matte-black/colors.toml`:**

| Omarchy token | Theme token |
|---|---|
| `background` | `bgBar` / `bgLauncher` |
| `lighter_background` | `bgBarAlt` |
| `muted` | `bgActive` |
| `foreground` | `fg` |
| `light_foreground` | `fgMuted` |
| `dark_foreground` | `fgDim` |
| `muted red` | `bgCritical` |

### 2.2 Rounding & Elevation

```qml
property int roundingBar:       0     // flat top bar — no pill
property int roundingLauncher:  16    // floating cards
property int roundingItem:      10    // rows, tiles, fields, toasts
property int borderWidth:       1
property int shadowRange:       16
property int shadowPower:       3
property real barOpacity:       1.0
```

### 2.3 Spacing

```qml
property int padXS:  4
property int padS:   6
property int padM:   10
property int padL:   16
property int gapS:   6
property int gapM:   10
property int gapL:   16
property int barHeight: 32        // Bar.qml implicitHeight
property int barIconSlot: 32      // bar icon slot (square)
property int barIconSize: 18      // bar glyph size
// Workspace tray (AppTray parity): wsAppIcon 32, wsAppIconGlyph 20, wsAppIconMax 3
```

### 2.4 Typography

```qml
property string fontFamily: "JetBrainsMono Nerd Font"
property string fontFamilyFallback: "JetBrains Mono"
property int fontSizeBar:       15
property int fontSizeBarIcon:   18
property int fontSizeLauncher:  14
property int fontSizeSmall:     11
property int fontWeightNormal:  400
property int fontWeightMedium:  600
property string dateFormat: "ddd MMM dd  hh:mm:ss"
```

* Icons are Nerd Font glyphs at text-appropriate sizes — no separate icon font.

### 2.5 Motion

```qml
property int durationFast:     120
property int durationNormal:   220
property int durationDrawer:   400
property string easingStandard: "easeOutCubic"
property string easingEmphasis: "easeInOutCubic"
```

---

## 3. Icons — `theme/Icons.qml`

Central glyph map (Nerd Fonts). Builders import `Icons` and never hard-code glyphs.

```qml
// theme/Icons.qml — full list
// Wifi / Network
property string wifiConnected:    "󰤨"
property string wifiSignal4:      "󰤨"
property string wifiSignal3:      "󰤥"
property string wifiSignal2:      "󰤢"
property string wifiSignal1:      "󰤟"
property string wifiEthernet:     "󰈀"
property string wifiDisconnected: "󰤭"
// Bluetooth
property string bluetoothOn:      "󰂯"
property string bluetoothOff:     "󰂲"
// Audio — intensity tiers
property string audioVolume:      "󰕾"
property string audioHigh:        "󰕾"
property string audioMedium:      "󰖀"
property string audioLow:         "󰕿"
property string audioMuted:       "󰖁"
// Keyboard / Notification / Battery
property string keyboard:         "󰌌"
property string notification:     ""
property string notificationDnd:  "󰂠"
property string notificationMuted:"󰂛"
property string batteryCharging:  "󰂄"
property string batteryPlugged:   "󰚥"
property string batteryLevels:    "󰁻󰁼󰁾󰂀󰂂󰁹"
// Workspaces / Perf
property string workspaceDot:     ""
property string window:           "󰘔"
property string cpu:              "󰻠"
property string memory:           "󰍛"
property string disk:             "󰋊"
property string temp:             "󰔏"
property string expand:           ""
property string collapse:         ""
// VPN / Common
property string vpn:              "󰖂"
property string search:           ""
property string close:            ""
property string check:            ""
property string warning:          ""
// Launcher targets
property string network:          ""
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
property string bluetooth:        "󰂯"
property string audio:            ""
property string app:              ""
property string shade:            "󰖂"
property string monitor:          "󰍹"
property string bell:             ""
property string keys:             ""
property string shutdown:         ""
property string control:          "󰀻"
```

* Per-app SVG overrides (`appGhostty`, `appChrome` + `appIconOverride(appId)`) exist
  for workspace-tray icons only — launchers stay Nerd-glyph-only.

---

## 4. Bar Styling

* **Container:** `PanelWindow { color: "transparent" }` with a flat strip:
  `color: Theme.bgBar, height: Theme.barHeight` (no pill radius — `roundingBar: 0`).
* **Left / Center / Right groups:** `RowLayout`s inside the strip:
  `padding: Theme.padM`, `spacing: Theme.gapS`.
* **Icon slots:** `barIconSlot × barIconSlot` squares, glyph `barIconSize` px.
* **Workspace dots:** `Text { text: Icons.workspaceDot, color: isActive ? Theme.fg : Theme.fgDim }`;
  per-workspace tray icons use `wsAppIcon` slots, `wsAppIconGlyph` glyphs,
  `wsAppIconMax` inline (overflow → `+n`).
* **Hover:** brighten to `Theme.fgBright` over `Theme.durationNormal`.
* **Critical blink:** `SequentialAnimation on color { loops: Animation.Infinite; ColorAnimation { to: Theme.critical; duration: 250 } ... }` (Waybar `@keyframes blink`).

---

## 5. Launcher Styling

### 5.1 Window & chrome

* **Window:** full-screen `WlrLayershell` — `anchors` all edges, `color: "transparent"`,
  `keyboardFocus: WlrKeyboardFocus.Exclusive`, `exclusionMode: ExclusionMode.Ignore`.
* **Dim overlay:** `Rectangle { anchors.fill: parent, color: Theme.overlay }` with a
  `MouseArea` that closes on click.
* **Card:** centered `Rectangle { radius: Theme.roundingLauncher, color: Theme.bgLauncher,
  border { width: 1, color: Theme.borderActive }, clip: true }`.
* **`LauncherBase.qml`** provides overlay + card + `Esc` close + focus-on-open
  (`card.forceActiveFocus()`); default `cardWidth: 600`, content `ColumnLayout`
  with `margins: Theme.padM, spacing: Theme.gapM`. Some launchers
  (ControlCenter, NotificationToast) inline the same chrome instead.
* **Card widths by launcher:** ControlCenter 600 · AudioCenter / NotificationCenter /
  ShutdownLauncher 620 · KeyLauncher / DisplayManager / BluetoothCenter /
  NetworkCenter 640. Height is content-driven (ControlCenter caps at 560).

### 5.2 Card anatomy

1. **Header:** uppercase label — `font.pixelSize: Theme.fontSizeSmall`, `Theme.fgMuted`,
   `font.capitalization: Font.AllUppercase`, `letterSpacing: 1.2`.
2. **Divider:** `Rectangle { Layout.fillWidth: true, height: 1, color: Theme.border }`.
3. **Content:** rows / grid tiles / sliders (below).
4. **Footer hints:** 10–11 px `Theme.fgDim`, centered, e.g.
   `"j/k h/l move · Enter open · / filter · Esc close"`,
   `"Ctrl+s show/hide password · Enter connect · Esc cancel"`.

### 5.3 Rows & tiles

* **List row / tile:** `radius: Theme.roundingItem`, bg `transparent` (all bg tokens
  are `#000000`), `border.width: 2` + `border.color: Theme.borderSelected` when selected,
  else `border.width: 1` + `Theme.border`.
* **Row layout:** left Nerd glyph + label; right-aligned status/meta in `Theme.fgMuted`.
* **Shutdown tiles:** 26 px glyph, state-coloured — `warning` (reboot, logout),
  `critical` (power), `accent` (airplane on), else `fg`.
* **Control-center grid:** 2-column `GridView`, `cellHeight: 84`, tile
  `height: cellHeight - 10`, `width: cellWidth - Theme.gapM`. Icon chip:
  `40×40`, `radius: 8`, `color: Theme.bgBar`, 18 px glyph. Label
  `Theme.fontSizeLauncher` `Theme.fontWeightMedium`; key hint right-aligned
  `Theme.fontSizeSmall` `Theme.fgMuted`.

### 5.4 Inputs & gauges

* **Search/filter field:** container `radius: Theme.roundingItem`, `color: Theme.bgActive`,
  `border.color: field.activeFocus ? Theme.borderSelected : Theme.border`;
  leading `Icons.search` glyph 16 px `fgMuted`; `TextField` 13 px,
  `placeholderTextColor: Theme.fgDim`, `background: null`; custom cursor
  ~6 px wide, ~1.5 em tall, `Theme.fg`.
* **Volume sliders:** groove `implicitHeight: 4`, `radius: 2`, fill `Theme.fgMuted`,
  selected ring `Theme.borderSelected` 1 px; handle `12×12`, `radius: 6`, `Theme.fg`.
* **Signal bar (NetworkCenter):** `60×6`, `radius: 3`, bg `Theme.border`, fill
  `width: parent.width * signal/100`, colour `warning` when signal < 30 else `fg`.

### 5.5 Toasts (`NotificationToastCard.qml`)

* **Card:** `width: 360`, `radius: Theme.roundingItem`, `color: Theme.bgBar`,
  `margins: Theme.padM`, top margin `Theme.barHeight + Theme.padM`.
* **Row:** app icon 16 px `fgMuted` · app name `Theme.fontSizeSmall`
  `Theme.fontWeightMedium` `fgMuted` · timestamp `fgDim`.
* **Summary:** 12 px `Theme.fontWeightMedium` `fg` (wraps); **body:**
  `Theme.fontSizeSmall` `fgMuted`, single line, elided.
* **Motion:** fade in via `opacity` `Behavior` at `Theme.durationFast`.

### 5.6 Keyboard

* `Esc` closes; clicking the overlay closes; focus is forced to the card on open.
* Navigation: `j/k` (or arrows) move, `h/l` move (grid: left/right),
  `Home`/`End` jump, `Enter` activates, `/` opens the filter field.
* Every interactive surface has a visible selection ring (`borderSelected`).

---

## 6. States

| State | FG | Border | Notes |
|---|---|---|---|
| Idle | `fg` | `border` 1 px | default — bg is always `bgLauncher` (`#000000`) |
| Hover | `fg` | `border` 1 px | pointer cursor; bg unchanged |
| Selected | `fg` | `borderSelected` 2 px | vim cursor row |
| Good (<30% load) | `fg` | — | no tint |
| Warning (30–80%) | `warning` | — | e.g., signal < 30% |
| Critical (>80%, battery<20%) | `critical` | — | `bgCritical` wash on affected rows |
| Disabled / unavailable | `fgDim` | — | e.g., no Bluetooth adapter |
| Charging | `success` | — | battery only |
| Plugged (AC, not charging) | `fg` | — | battery only — plug glyph, no percent |

---

## 7. Dark-Mode Contract

* Default is dark. `Theme` does **not** switch to light automatically.
* GTK theming (`gsettings ... prefer-dark`, `adw-gtk3-dark` in `hyprland.lua`) is
  independent; Quickshell tokens stay dark regardless.
* Omarchy matte-black is the base palette — never invert to light.

---

## 8. Do / Do Not

* **Do** use `Theme.*` tokens everywhere — no hard-coded colours in component files.
* **Do** use Nerd glyphs via `Icons.*` — no SVG/PNG icons in launchers
  (SVG overrides are tray-only, defined inside `Icons.qml`).
* **Do** keep the launcher font scale: tokens 11/14 px; component-level 8–26 px
  for meta/hints/fields/icons/tiles as documented in §5.
* **Do not** add light-theme variants or per-component colour overrides without
  updating `Theme.qml`.
* **Do not** change selection to a background tint — selection is border-based (§2.1).

---

## 9. Verification

* Visual: screenshots at 1920×1080 — flat bar at top, launcher cards centered —
  compare to Waybar/Omarchy reference.
* Contrast: `fg` on `bgLauncher` ≥ 7:1.
* No hard-coded hex outside `theme/Theme.qml`:
  `grep -R "#[0-9a-fA-F]" --include="*.qml" components/ theme/ | grep -v "theme/Theme.qml"`
  (scan of `components/launchers/` is clean — 0 hard-coded hex / `Qt.rgba`).
* All glyphs resolve via `Icons.*` (no inline glyph literals in `text:`).
