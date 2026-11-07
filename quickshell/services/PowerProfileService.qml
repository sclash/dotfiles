pragma Singleton
import QtQuick
import Quickshell.Io
import Quickshell.Services.UPower
import "powerProfileRule.js" as ProfileRule

QtObject {
    id: root

    // PPD reachable — set by the one-shot probe below.
    property bool _probed: false
    readonly property bool available: _probed

    readonly property bool hasPerformance: PowerProfiles.hasPerformanceProfile
    readonly property int  current: PowerProfiles.profile
    readonly property int  degradation: PowerProfiles.degradationReason
    readonly property bool degraded: degradation !== PerformanceDegradationReason.None

    // Auto mode follows the power source; a manual pick holds until setAuto().
    property bool auto: true
    // Hysteresis latch: true once capacity dropped to <= 20 on battery.
    property bool _low: false

    function _inputs() {
        return {
            available: BatteryService.available,
            // plugged is false while charging, so AC = plugged || charging.
            onAc: BatteryService.plugged || BatteryService.charging,
            capacity: BatteryService.capacity,
            hasPerformance: hasPerformance
        }
    }
    function _toEnum(name) {
        if (name === "performance") return PowerProfile.Performance
        if (name === "power-saver") return PowerProfile.PowerSaver
        return PowerProfile.Balanced
    }
    function _target() { return _toEnum(ProfileRule.target(_inputs(), _low)) }

    readonly property int autoTarget: _target()

    // Manual pick — holds until setAuto(). Guarded at the writer so no caller
    // (the card, or a future IPC/bar hook) can request a profile PPD does not
    // offer, or write while PPD is unreachable.
    function setProfile(p) {
        if (!available) return
        if (p === PowerProfile.Performance && !hasPerformance) return
        auto = false
        PowerProfiles.profile = p
    }
    // Re-enable auto and apply immediately.
    function setAuto()     { auto = true; _apply() }

    function _apply() {
        _low = ProfileRule.latch(_inputs(), _low)
        if (auto && available) PowerProfiles.profile = _target()
    }

    property Connections batteryConn: Connections {
        target: BatteryService
        function onCapacityChanged() { root._apply() }
        function onPluggedChanged()  { root._apply() }
        function onChargingChanged() { root._apply() }
    }

    // Quickshell populates PowerProfiles asynchronously (hasPerformanceProfile
    // is false for the first ~0.5s), so re-apply once the real value lands;
    // otherwise the initial AC->performance write is silently skipped.
    property Connections ppConn: Connections {
        target: PowerProfiles
        function onHasPerformanceProfileChanged() { root._apply() }
    }

    property Process probe: Process {
        command: ["powerprofilesctl", "list"]
        running: true
        onExited: (code) => { root._probed = (code === 0); root._apply() }
    }

    Component.onCompleted: _apply()
}
