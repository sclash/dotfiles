# Shutdown-Launcher — Refined Spec

> Command: `SUPER+q` · File: `components/launchers/ShutdownLauncher.qml`

---

## 1. Purpose

Center-screen confirmation grid for power/plane actions. Minimal chrome, large hit targets, keyboard-only.

## 2. Window

* `LauncherBase.qml`: `width: 520` (narrower than others — 2×2 grid), `radius: Theme.roundingLauncher`, vim nav, `Esc` closes.
* No filter field — fixed 4–5 options, filter is unnecessary.

## 3. Options (normative, 2×2 grid + optional 5th)

| # | Action | Icon | Command | Confirm |
|---|---|---|---|---|
| 1 | **Sleep** | `󰒲` | `systemctl suspend` | no |
| 2 | **Reboot** | `󰜉` | `systemctl reboot` | yes — highlight in `Theme.warning` |
| 3 | **Shutdown** | `` | `systemctl poweroff` | yes — highlight in `Theme.critical` |
| 4 | **Plane Mode** (toggle) | `󰀝` when off, `󱤱` when on | `rfkill block all` / `rfkill unblock all` (or `nmcli radio all off/on`) | no — toggle with inline state |
| 5 | **Logout** (optional, not in original spec but conventional) | `󰍃` | `hyprctl dispatch exit` | yes |

> Original spec lists Sleep, Shutdown, Reboot, Plane Mode — keep exactly those four as required. Logout is optional addition; if omitted, grid is 2×2.

### Plane Mode semantics

* "Deactivate all outside connections" — implemented as:
  1. `nmcli radio all off` (Wi-Fi + WWAN off),
  2. `bluetoothctl power off` (or `rfkill block bluetooth`),
  3. `rfkill block all` as blanket if the above fail.
* When **on**, bar `Wifi`/`Bluetooth` icons switch to disconnected/off states via their services. Toggling again reverses: `rfkill unblock all; nmcli radio all on; bluetoothctl power on`.
* Button label reflects current state: `"Plane Mode: ON — click to disable"` vs `"Plane Mode"`. State derived from `rfkill list` or `nmcli radio`.

## 4. Interaction

* `h/j/k/l` or arrow keys move focus in the grid; `Enter` activates.
* **Confirm step** for Reboot/Shutdown/Logout: first `Enter` highlights the button and shows `"Press Enter again to confirm"` at `Theme.warning`/`Theme.critical`; second `Enter` executes. `Esc` cancels confirm and stays in launcher. Single-press `Enter` for Sleep/Plane Mode.
* `Esc` (when not confirming) closes launcher.
* No typing/filter.

## 5. Styling

* Grid cards: `radius: Theme.roundingItem`, `height: 84`, icon `Theme.fontSizeLauncher*1.6` centered above label, `Theme.fg`. Hover `Theme.bgHover`; focused `Theme.bgSelected` + `border.color: Theme.borderSelected`; critical focused `border.color: Theme.critical`.
* Plane Mode ON: card at `Theme.accent` tint to indicate active.

## 6. Dry-Run / Safety

* All `systemctl` commands are `Process {}` with no `sudo` — they work for an active logind session. No polkit prompt.
* Log the issued command to `console.log` before execution for debuggability.

## 7. Acceptance

* [ ] Renders 4 (or 5 with Logout) cards in a grid; vim `h/j/k/l` nav + `Enter` works.
* [ ] Sleep executes immediately; Reboot/Shutdown/Logout require double-Enter confirm.
* [ ] Plane Mode toggles radios and the bar icons update via `NetworkService`/`BluetoothService`.
* [ ] `Esc` cancels confirm, second `Esc` closes.
* [ ] Uses `LauncherBase` + `Theme.*` tokens.
