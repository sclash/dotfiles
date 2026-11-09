.pragma library

// Pure rule for the low-battery hibernate prompt — no Qt/QML dependencies,
// unit-tested by tests/tst_low_battery_rule.qml.
//
// `o` is the input snapshot read from BatteryService:
//   { available: bool, discharging: bool, minutes: int, capacity: int }
// `minutes` (UPower's time-to-empty) and `capacity` (0..100) are -1 when
// unknown. UPower's estimate is noisy: it is missing for a few seconds after
// unplugging and jumps with load spikes, so don't trust it alone.

// Thresholds, exported so the spec and the tests agree.
//   MINUTES — time-to-empty that counts as critical...
//   GATE    — ...but only at or below this percentage, so a load spike that
//             briefly reads "2 min left" at 40% doesn't fire;
//   PERCENT — fires on its own at or below this, for when the estimate is
//             missing or wrong. Matches UPower's default "critical" level (5%),
//             just above its own last-resort action (2%).
var MINUTES = 5
var GATE = 15
var PERCENT = 5

// True when the battery is low enough that the user should hibernate now.
// -1 means unknown and never counts as low.
function critical(o) {
    if (!o.available || !o.discharging)
        return false
    if (o.capacity >= 0 && o.capacity <= PERCENT)
        return true
    return o.minutes >= 0 && o.minutes <= MINUTES
        && o.capacity >= 0 && o.capacity <= GATE
}

// Next value of the "dismissed" latch. Once the user dismisses the prompt it
// stays hidden for the rest of this discharge, and re-arms as soon as the
// machine is on AC again (or the battery disappears).
function dismissed(o, wasDismissed) {
    if (!o.available || !o.discharging)
        return false
    return wasDismissed
}

// Whether the prompt is on screen for this snapshot.
function shown(o, wasDismissed, canHibernate) {
    return canHibernate && !dismissed(o, wasDismissed) && critical(o)
}
