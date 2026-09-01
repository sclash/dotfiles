# Wifi — Bar Icon — Refined Spec

> Parent: [`Bar.md`](./Bar.md) · Service: `services/NetworkService.qml`

---

## 1. Purpose

Single glyph in the right group that reflects network connectivity at a glance
and opens `Network-Center` (`SUPER+w`) on click.

## 2. States & Glyphs

All glyphs via `Icons.*` (see `STYLE.md:3`), sizes from `Theme.fontSizeBar:14`.

| State | Condition | Glyph | Colour | Tooltip |
|---|---|---|---|---|
| **Ethernet** | `NetworkService.type === "ethernet"` | `Icons.wifiEthernet` (``) | `Theme.fg` | `"{essid}\n{ipaddr} 🖧"` — Waybar semantics (`config.jsonc:59`) |
| **Wi-Fi connected** | `type==="wifi" && connected` | `Icons.wifiConnected` (``) | `Theme.fg` | `"{essid} ({signal}%) \n{ipaddr}"` — include VPN line if active |
| **Wi-Fi weak** | same but `signal < 30` | same glyph | `Theme.warning` | same |
| **VPN active** | `vpnActive === true` | `Icons.vpn` (`󰖂`) overlaid or `` + `󰖂` badge | `Theme.accent` | `"{essid} via {vpnName}\n{ipaddr}"` |
| **Disconnected** | `!connected` | `Icons.wifiDisconnected` (``) | `Theme.fgDim` | `"Disconnected"` |
| **Unavailable** | `NetworkService.available === false` | `` | `Theme.fgDim` | `"NetworkManager unavailable"` |

Signal tiers (optional dimming, not required): 0–29 warning, 30–69 normal, 70–100 normal.

## 3. Service Contract — `NetworkService.qml`

```qml
QtObject {
  property bool available       // false if nmcli/DBus not reachable
  property bool connected
  property string type          // "wifi" | "ethernet" | "none"
  property string essid
  property string ipaddr        // IPv4
  property int signalStrength   // 0-100, -1 if not wifi
  property bool vpnActive
  property string vpnName
}
```

* **Data source:** prefer DBus `org.freedesktop.NetworkManager` signals (`StateChanged`, `PropertiesChanged`) for event-driven updates. Fallback: `Process { command: ["nmcli","-t","-f","TYPE,STATE,NAME","device"] }` polled at 5s when DBus unavailable, and `nmcli monitor` tail if available.
* **VPN:** `nmcli -t -f NAME,TYPE connection show --active | grep vpn`.
* **No polling when bar is the only consumer** beyond DBus / 5s fallback.

## 4. Interaction

* **Click** → `launcher.toggle("network")`.
* **Right-click** (optional) → same as click (no separate menu).
* **Hover** → tooltip as above; `Behavior on color { ColorAnimation { duration: Theme.durationNormal } }`.

## 5. Launcher Sync

`NetworkService` is shared with `Network-Center`. Mutations from the launcher
(`connect`, `disconnect`, `forget`) update these properties and the icon reflects
within ≤ 500 ms via DBus signal or next poll.

## 6. Error Handling

* `nmcli` missing / permission denied → `available = false`, degraded glyph, tooltip explains. No crash, no repeated error spam (log once per 30s).
* Hyprland on a machine with no Wi-Fi hardware → show `` if ethernet, else `` — not a hard error.

## 7. Acceptance

* [ ] Each row in the States table renders correctly (manual NM `connect`/`disconnect` test).
* [ ] VPN badge appears when a VPN is active; tooltip includes VPN name.
* [ ] Click opens `Network-Center`; launcher mutations reflect back on icon.
* [ ] No per-icon `Process` — single `NetworkService` owns all NM interaction.
* [ ] Tooltip text matches Waybar's `tooltip-format-*` parity.
