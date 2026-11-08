.pragma library

// Pure helpers for PolkitService.qml (tested by tests/tst_polkit_parse.qml).

// A pkexec request whose program is howdy (Identity Manager face models).
// pkexec's message: "Authentication is needed to run `<program> <args>' …".
function isHowdyRequest(actionId, message) {
    if (actionId !== "org.freedesktop.policykit.exec") return false
    const m = String(message || "").match(/`(\S+)/)
    return m !== null && /(^|\/)howdy$/.test(m[1])
}

// Shown inside the Face view (claimed = that view is open) instead of the
// generic prompt overlay.
function routeInline(claimed, actionId, message) {
    return claimed && isHowdyRequest(actionId, message)
}
