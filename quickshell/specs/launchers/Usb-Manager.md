# USB-Manager — Refined Spec

> Command: `SUPER+u` · File: `components/launchers/UsbManager.qml` · Service: `UsbService.qml`

---

## 1. Purpose

Center-screen window to manage plug-and-play USB devices: mount / unmount / power-off USB storage, and inspect every other USB device currently connected (hubs, HID, audio, video, …). The lists update automatically on plug/unplug — event-driven via udev, no polling — so the launcher reflects reality the moment it is opened. A **bar icon** in the right group next to Bluetooth (inline in `Bar.qml`) mirrors mount state read-only from `UsbService`: `Icons.usbDrive` at `Theme.accent` when at least one storage device is mounted, `Icons.usb` at `Theme.fg` when storage is present but unmounted, `Theme.warning` while a mount/unmount/power-off is in flight (`busyNode`), `Theme.fgDim` when no storage is attached or the service is unavailable; click toggles the launcher (`usb`).

## 2. Window

* `LauncherBase.qml`: `width: 640`, `radius: Theme.roundingLauncher`, vim nav, `/` filter, `Esc` closes.
* **Hyprland:** layer on top; same `layerrule` treatment as the other launchers.

## 3. Sections (top → bottom)

### 3.1 Storage Devices

* Source: `UsbService.storage` — `lsblk -J -o NAME,PATH,LABEL,FSTYPE,SIZE,MOUNTPOINT,TRAN` filtered to `tran === "usb"` (partition children fold into their parent disk row), enriched with udisks2 state.
* Each row: `Icons.usbDrive` glyph + `label` (or `node` when no label, bold) + `size` and `fstype` right-aligned (`Theme.fgMuted`, `fontSizeSmall`); second line: mount point in `Theme.fg` when mounted, else `"Not mounted"` at `Theme.fgDim`.
* **Actions per row:**

  | Action | Command | When |
  |---|---|---|
  | Mount | `udisksctl mount -b {node}` | unmounted (default on `Enter`, key `m`) |
  | Unmount | `udisksctl unmount -b {node}` | mounted (default on `Enter`, key `u`) |
  | Open | `$fileManager {mountPoint}` | mounted only (key `o`) |
  | Power-off | `udisksctl power-off -b {diskNode}` | always (key `e`); `y/n` confirm |

* **Power-off** is safe removal: the service unmounts all child filesystems first, then spins down / cuts power; the row disappears on success. Aborts with an inline error if a child unmount fails.
* **Busy state:** while an operation is in flight the row shows `"Mounting…"` / `"Unmounting…"` / `"Powering off…"` at `Theme.fgMuted`; `Enter` and single-key actions are ignored until it resolves. Failure clears busy and shows the inline error (§4).
* **Encrypted** (`fstype === "crypto_LUKS"`, no unlocked child): `Icons.lock` badge at `Theme.warning` next to the label; action `Unlock` replaces `Mount` — inline passphrase dialog (placeholder `"Passphrase for {label}"`, `echoMode: Password`, `Ctrl+s` show/hide — same pattern as Network-Center §3.3). On submit the dialog closes immediately, the row goes busy, `udisksctl unlock -b {node}` runs, then the unlocked child mounts automatically.

### 3.2 All USB Devices

* Source: `UsbService.allDevices` — `lsusb` rows of the form `Bus {bus} Device {dev}: ID {vid}:{pid} {name}`.
* Each row: type glyph + `name` (bold; `"Unknown device"` when lsusb omits it) + `bus:dev` and `vid:pid` right-aligned (`Theme.fgMuted`, `fontSizeSmall`).
* **Glyph mapping:** device also present in §3.1 → `Icons.usbDrive`; `name` contains `hub` (case-insensitive) → `Icons.usbPort`; else `Icons.usb`.
* Display-only — no actions. Plug/unplug updates arrive via the udev monitor; storage rows are cross-linked with §3.1 (mount state shown).
* Sorted by bus, then device number.

## 4. Shared Behaviours

* `/` filter across both lists by label / name / node / `vid:pid` substring; `Esc` clears the filter first.
* `j/k` (or arrows) move focus continuously across both lists — section headers are not focusable; `Home`/`End` jump.
* `Enter` triggers the focused row's primary action (Mount / Unmount / Unlock; no-op on info rows).
* Single-key actions on the focused storage row: `m` mount · `u` unmount · `o` open · `e` power-off (with `y/n` confirm) · `r` refresh both lists.
* Inline errors (`Theme.critical`) under the relevant row — e.g. `"Unmount failed: device is busy"`, `"Power-off failed: other mounted filesystems"`, `"udisksctl not found"`; cleared on next success for that device.
* Empty states at `Theme.fgMuted`: `"No USB storage devices"` (§3.1), `"No other USB devices"` (§3.2).

## 5. Service Contract

All `udisksctl` / `lsblk` / `lsusb` / udev access goes through `UsbService.qml` — no ad-hoc `Process` in the launcher.

```qml
// UsbService.qml
property bool available        // udisksctl + lsusb both present
property var storage: []       // { node, diskNode, label, size, fstype, mountPoint, mounted, busy, encrypted }
property var allDevices: []    // { bus, dev, vid, pid, name, isStorage, node }
property string lastError: ""
signal dataUpdated()

function refresh(): void
function mount(node: string): void
function unmount(node: string): void
function powerOff(diskNode: string): void
function unlock(node: string, passphrase: string): void
```

* **Event-driven, no polling (SPECS.md §2.3 rule 1):** a long-running `udevadm monitor --udev` `Process` watches for `add` / `remove` / `change` under the `usb` and `block` subsystems; every event debounces (~300 ms) into a single `refresh()` (one `lsblk -J` + one `lsusb` per burst). Mutations the service performs itself refresh on process exit. No timer-based polling anywhere.
* **One `Process` per subsystem (SPECS.md §2.3 rule 3):** one `lsblk` proc, one `lsusb` proc, one serialized `udisksctl` action proc (operations queue), one `udevadm monitor` proc.

## 6. Backend Notes

* **New Nix deps:** `pkgs.udisks2` (provides `udisksctl`) and `pkgs.usbutils` (provides `lsusb`) in `nixos/programs/quickshell.nix` (SPECS.md §2.2), plus `services.udisks2.enable = true` in the system config. udev itself is already present.
* udisks2 mounts removable media at `/run/media/$USER/{label}`; polkit allows any active seat user to mount / unmount / power-off removable devices without a password prompt — no extra polkit rules needed.
* `udisksctl mount -b {node}` prints `Mounted /dev/sdX1 at …` — the service does not parse stdout; it refreshes on process exit.
* Storage detection uses `tran === "usb"`, **not** `rm === 1` (USB SSDs / enclosures don't report removable). Mount / unmount act on partition nodes; `power-off` acts on the parent disk node.
* `lsusb` parse: `Bus (\d+) Device (\d+): ID ([0-9a-f]{4}):([0-9a-f]{4}) (.*)`.
* Auto-mount on plug (e.g. `udiskie -a`) is **out of scope** — plugging updates the list automatically; mounting stays an explicit `Enter`.

## 7. Empty / Degraded States

* `udisksctl` missing (`available === false`) → banner atop §3.1: `"udisks2 unavailable — mounting disabled"` at `Theme.warning`; storage rows render read-only, §3.2 unaffected.
* `lsusb` missing → §3.2 shows `"usbutils unavailable"` at `Theme.fgDim`; §3.1 unaffected.
* No devices → the §4 empty states.
* udev monitor died → one auto-restart per 5 s; while down, footer hint `"device monitoring lost — press r to refresh"` at `Theme.fgDim`.

## 8. Acceptance

* [ ] Storage rows show label/node, size, fstype, and mount point (or `"Not mounted"`).
* [ ] Mount / Unmount work via `Enter` and `m`/`u`; `Open` launches `$fileManager` at the mount point; busy rows block duplicate actions.
* [ ] Power-off (`e`) confirms `y/n`, unmounts children, removes the row on success.
* [ ] Encrypted rows unlock via the passphrase dialog, then mount the unlocked child.
* [ ] §3.2 lists every USB device (hubs, HID, audio, …) with `bus:dev` + `vid:pid`; storage rows cross-linked with their §3.1 state.
* [ ] Plugging / unplugging updates both lists without opening the launcher or pressing `r` (udev-driven; no polling).
* [ ] `/` filter, `j/k` nav across both lists, `r` refresh, `Esc` hierarchy all work.
* [ ] Degraded states render when udisks2 / usbutils are missing; empty states at `Theme.fgMuted`.
* [ ] Uses `LauncherBase` + `Theme.*` tokens; no hard-coded colours; all glyphs via `Icons.*`.
