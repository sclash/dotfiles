pragma Singleton
import QtQuick
import Quickshell.Services.UPower

QtObject {
    id: root

    // Aggregate across all batteries (handles multi-battery machines).
    readonly property UPowerDevice display: UPower.displayDevice

    // Per-battery device for the fields the aggregate reports as N/A
    // (health, model). Prefer the laptop battery.
    readonly property UPowerDevice battery: {
        let fallback = null
        for (const d of UPower.devices.values) {
            if (d.type !== UPowerDeviceType.Battery) continue
            if (d.isLaptopBattery) return d
            if (!fallback) fallback = d
        }
        return fallback
    }

    readonly property bool available: display ? (display.ready && display.isPresent) : false

    // Quickshell reports `percentage` as a 0..1 fraction (unlike
    // `healthPercentage`, which is 0..100). Scale to 0..100.
    readonly property int capacity: {
        if (!available || isNaN(display.percentage)) return -1
        return Math.round(display.percentage * 100)
    }
    // Normalized to the historical contract: µWh / µW. UPower reports Wh / W.
    readonly property double energyNow: available ? display.energy * 1000000 : -1
    readonly property double energyFull: available ? display.energyCapacity * 1000000 : -1
    readonly property double powerNow: available ? display.changeRate * 1000000 : -1

    readonly property bool charging: available && display.state === UPowerDeviceState.Charging
    readonly property bool discharging: available &&
        (display.state === UPowerDeviceState.Discharging || display.state === UPowerDeviceState.Empty)
    // On AC and not actively charging (covers Full / pending / not-charging).
    readonly property bool plugged: !UPower.onBattery && !charging

    readonly property int timeLeftMinutes: {
        if (!display) return -1
        let secs = -1
        if (discharging) secs = display.timeToEmpty
        else if (charging) secs = display.timeToFull
        if (isNaN(secs) || secs <= 0) return -1
        return Math.round(secs / 60)
    }

    readonly property bool healthSupported: battery ? battery.healthSupported : false
    readonly property double health: (battery && battery.healthSupported) ? battery.healthPercentage : -1
    readonly property string model: battery ? (battery.model || "") : ""
}
