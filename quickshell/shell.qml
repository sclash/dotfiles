//@ pragma UseQApplication
import Quickshell
import Quickshell.Io
import "theme"
import "services"
import "components/launchers"

Scope {
    id: root

    // Force NotifService singleton instantiation so its NotificationServer acquires DBus name early
    property var _ensureNotif: NotifService.history

    // Bar
    Bar {
        id: bar
        onLauncherToggleRequested: (name) => ipcHandler.toggle(name)
    }

    // Launchers — each is a WlrLayershell singleton overlay
    AppLauncher { id: appLauncher }
    NetworkCenter { id: networkCenter }
    BluetoothCenter { id: bluetoothCenter }
    AudioCenter { id: audioCenter }
    DisplayManager { id: displayManager }
    NotificationCenter { id: notificationCenter }
    ShutdownLauncher { id: shutdownLauncher }
    KeyLauncher { id: keyLauncher }
    ControlCenter {
        id: controlCenter
        onRequestToggle: (name) => ipcHandler.toggle(name)
    }

    // IPC
    IpcHandler {
        id: ipcHandler
        target: "launcher"

        function closeAllExcept(except: string): void {
            if (except !== "app") appLauncher.close()
            if (except !== "network") networkCenter.close()
            if (except !== "bluetooth") bluetoothCenter.close()
            if (except !== "audio") audioCenter.close()
            if (except !== "display") displayManager.close()
            if (except !== "notification") notificationCenter.close()
            if (except !== "shutdown") shutdownLauncher.close()
            if (except !== "keys" && except !== "key") keyLauncher.close()
            if (except !== "control") controlCenter.close()
        }

        function toggle(name: string): void {
            if (name === "app") { if (appLauncher.isOpen) appLauncher.close(); else { closeAllExcept("app"); appLauncher.open() } }
            else if (name === "network") { if (networkCenter.isOpen) networkCenter.close(); else { closeAllExcept("network"); networkCenter.open() } }
            else if (name === "bluetooth") { if (bluetoothCenter.isOpen) bluetoothCenter.close(); else { closeAllExcept("bluetooth"); bluetoothCenter.open() } }
            else if (name === "audio") { if (audioCenter.isOpen) audioCenter.close(); else { closeAllExcept("audio"); audioCenter.open() } }
            else if (name === "display") { if (displayManager.isOpen) displayManager.close(); else { closeAllExcept("display"); displayManager.open() } }
            else if (name === "notification") { if (notificationCenter.isOpen) notificationCenter.close(); else { closeAllExcept("notification"); notificationCenter.open() } }
            else if (name === "shutdown") { if (shutdownLauncher.isOpen) shutdownLauncher.close(); else { closeAllExcept("shutdown"); shutdownLauncher.open() } }
            else if (name === "keys" || name === "key") { if (keyLauncher.isOpen) keyLauncher.close(); else { closeAllExcept("keys"); keyLauncher.open() } }
            else if (name === "control") { if (controlCenter.isOpen) controlCenter.close(); else { closeAllExcept("control"); controlCenter.open() } }
            else if (name === "perf") { PerfService.toggle() }
            else console.log("unknown launcher: " + name)
        }

        function closeAll(): void {
            appLauncher.close(); networkCenter.close(); bluetoothCenter.close(); audioCenter.close()
            displayManager.close(); notificationCenter.close(); shutdownLauncher.close(); keyLauncher.close(); controlCenter.close()
        }

        function open(name: string): void { toggle(name) }
        function close(name: string): void {
            if (name==="app") appLauncher.close()
            else if (name==="network") networkCenter.close()
            else if (name==="bluetooth") bluetoothCenter.close()
            else if (name==="audio") audioCenter.close()
            else if (name==="display") displayManager.close()
            else if (name==="notification") notificationCenter.close()
            else if (name==="shutdown") shutdownLauncher.close()
            else if (name==="keys") keyLauncher.close()
            else if (name==="control") controlCenter.close()
        }
    }

    // Perf IPC also
    IpcHandler {
        target: "perf"
        function toggle(): void { PerfService.toggle() }
        function isExpanded(): bool { return PerfService.expanded }
    }

}
