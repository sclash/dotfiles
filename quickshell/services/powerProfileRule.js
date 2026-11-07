.pragma library

// Pure auto rule for power profiles — no Qt/QML dependencies, unit-tested by
// tests/tst_power_profile_rule.qml.
//
// `o` is the input snapshot:
//   { available: bool, onAc: bool, capacity: int, hasPerformance: bool }
// `onAc` is true whenever the machine is on AC power, including while actively
// charging (BatteryService.plugged is false during charge, so callers pass
// plugged || charging).
// `low` is the hysteresis latch: true once the battery dropped to <= 20 while
// on battery (callers update it with latch() before asking for target()).

// Profile the auto rule wants. `capacity` is -1 when unknown, so the low tests
// require capacity >= 0 (otherwise -1 <= 20 would wrongly pick power-saver).
function target(o, low) {
    if (!o.available || o.onAc)
        return o.hasPerformance ? "performance" : "balanced"
    if (o.capacity >= 0 && o.capacity <= 20)
        return "power-saver"
    if (low && o.capacity >= 0 && o.capacity < 25)
        return "power-saver"
    return "balanced"
}

// Next value of the hysteresis latch for the given snapshot.
function latch(o, low) {
    if (!o.available || o.onAc)
        return false
    if (o.capacity >= 0 && o.capacity <= 20)
        return true
    return low
}
