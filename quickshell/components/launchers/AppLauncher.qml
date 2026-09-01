import Quickshell
import Quickshell.Io

// Reverted to the external elephant + walker backend (see hyprland.lua:
// `exec-once = elephant` daemon, this launches `walker`). Will be revisited later.
Scope {
    id: root

    property bool isOpen: false

    function open() {
        isOpen = true
        spawnProc.running = true
        isOpen = false
    }
    function close() { isOpen = false }
    function toggle() { open() }

    // pkill-first keeps parity with the old bind behaviour (single walker instance)
    property Process spawnProc: Process {
        command: ["sh", "-c", "pkill -x walker 2>/dev/null; sleep 0.05; exec walker"]
    }
}