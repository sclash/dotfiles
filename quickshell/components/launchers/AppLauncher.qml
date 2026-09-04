import Quickshell
import Quickshell.Io

// App launcher — external walker UI (resident service) themed via walker-style/
// to match the native launchers. See specs/launchers/App-Launcher.md for the
// eventual in-process Quickshell.DesktopEntries implementation.
Scope {
    id: root

    property bool isOpen: false

    // walker runs resident via `walker --gapplication-service` (hyprland.lua autostart),
    // so invoking plain `walker` is a cheap D-Bus activation. close_when_open=true
    // (walker default) makes that invocation toggle: open when closed, close when open.
    function open() { spawnProc.running = true }
    // Guarded close for IPC closeAll/closeAllExcept: only fires when the walker
    // layer is actually on screen, so it is a no-op when walker is closed.
    function close() { closeProc.running = true }
    function toggle() { open() }

    property Process spawnProc: Process {
        command: ["walker"]
    }

    property Process closeProc: Process {
        command: ["sh", "-c", "hyprctl layers | grep -q 'namespace: walker' && exec walker -q"]
    }
}