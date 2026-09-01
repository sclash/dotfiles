# KeyBoard — Bar Icon — Refined Spec

> Parent: [`Bar.md`](./Bar.md) · Source: Hyprland IPC

---

## 1. Purpose

Glyph + layout code in the right group indicating the active `xkb_layout`.
`Alt+Shift` cycles layouts; the bar reflects the change. No launcher.

## 2. States & Glyphs

| Layout | Glyph | Text | Tooltip |
|---|---|---|---|
| `en` / `US` | `Icons.keyboard` (`⌨`) | `IT` is a mislabel — actually `US` | `"Keyboard: US — Alt+Shift to switch"` |
| `it` / `IT` | `⌨` | `IT` | `"Keyboard: IT — Alt+Shift to switch"` |
| Unknown | `⌨` | raw `layoutName` uppercased | same |

Format parity with Waybar `hyprland/language` (`config.jsonc:37-43`):

```json
"format-en": "|| ⌨ US 🇺🇸 || ",
"format-it": "|| ⌨ IT 🇮🇹 || ",
```

Quickshell renders:

```
|| ⌨ IT 🇮🇹 ||
|| ⌨ US 🇺🇸 ||
```

* Include the `||` separators — they double as visual group delimiters in the right pill (Waybar style). Spacing: single space between segments.
* Flag emoji (`🇺🇸`/`🇮🇹`) is optional; include if the Nerd Font renders it. Fallback to text-only `⌨ IT` / `⌨ US` if emoji fails to render.
* Font: `Theme.fontFamily`, `Theme.fontSizeBar:14`.

## 3. Data Source

* **Primary:** `Process { command: ["hyprctl","devices","-j"] }` JSON — parse `keyboards[].active_keymap` for the `at-translated-set-2-keyboard` (or whichever reports `main: true`).
* **Event-driven:** listen to Hyprland IPC `activelayout` event via `Quickshell.Hyprland` or `hyprctl` socket watch. If `Quickshell.Hyprland` exposes `Keyboard` signals, use them; otherwise tail `socat UNIX-CONNECT:$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock` for `activelayout>>`.

## 4. Interaction

* **Click** → `hyprctl switchxkblayout at-translated-set-2-keyboard next` (same as Waybar `on-click`). Cycle layout, don't open a launcher.
* **`Alt+Shift`** (Hyprland `input:kb_options = grp:alt_shift_toggle`) already handled by compositor — bar just reflects. No QML key handler needed for this.
* **Hover** → tooltip as above.

## 5. Error Handling

* `hyprctl` unavailable or `devices -j` missing `active_keymap` → show `⌨ --` dimmed, tooltip "Keyboard layout unavailable".
* Single layout configured (no variant) → show that layout statically; click still issues `switchxkblayout` (no-op, no error).

## 6. Acceptance

* [ ] Displays `|| ⌨ IT 🇮🇹 ||` / `|| ⌨ US 🇺🇸 ||` matching Waybar parity.
* [ ] `Alt+Shift` and click both cycle layouts and the bar updates within 300 ms.
* [ ] Fallback renders without flag emoji when the font lacks it.
* [ ] No polling beyond Hyprland IPC events (plus one-shot at startup).
