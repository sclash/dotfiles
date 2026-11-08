.pragma library

// Pure parsing helpers for IdentityService.qml. Kept out of the QML file so
// they can be unit-tested headless (tests/tst_identity_parse.qml).

// fprintd finger ids (utils/fprintd-enroll.c, fprintd 1.94.5).
const FINGERS = [
    "left-thumb", "left-index-finger", "left-middle-finger", "left-ring-finger", "left-little-finger",
    "right-thumb", "right-index-finger", "right-middle-finger", "right-ring-finger", "right-little-finger"
]

// fprintd-list prints " - #N: <finger>" per enrolled finger (utils/list.c).
// Returns the known finger ids, deduplicated.
function parseEnrolled(text) {
    const out = []
    const re = /^\s*-\s*#\d+:\s*(\S+)\s*$/gm
    let m
    while ((m = re.exec(text || "")) !== null) {
        if (FINGERS.indexOf(m[1]) !== -1 && out.indexOf(m[1]) === -1)
            out.push(m[1])
    }
    return out
}

// Classifies fprintd-list output. "" = usable output; otherwise a distinct
// degraded state (utils/list.c messages).
function listError(text) {
    const t = (text || "").toLowerCase()
    if (t.indexOf("no devices available") !== -1) return "nodevice"
    if (t.indexOf("impossible to get devices") !== -1
        || t.indexOf("failed to connect to session bus") !== -1
        || t.indexOf("failed to get fprintd manager") !== -1) return "daemon"
    if (t.indexOf("listenrolledfingers failed") !== -1) return "listfail"
    return ""
}

// hyprlock fingerprint override file (`enabled = ...`); the file being
// absent/unreadable ("ABSENT" or garbage) means enabled — the repo default.
// Last assignment wins, mirroring hyprlang.
function parseAuthEnabled(text) {
    const re = /enabled\s*=\s*(true|false|1|0)/g
    let m
    let enabled = true
    while ((m = re.exec(text || "")) !== null)
        enabled = (m[1] === "true" || m[1] === "1")
    return enabled
}

// EnrollStatus result strings (fprintd daemon, 1.94.5) to user-facing text.
const STAGE_LABELS = {
    "enroll-stage-passed": "Stage passed - lift and place again",
    "enroll-retry-scan": "Please retry fingerprint scan",
    "enroll-swipe-too-short": "Swipe too short - try again",
    "enroll-finger-not-centered": "Finger not centered - try again",
    "enroll-remove-and-retry": "Remove your finger and try again",
    "enroll-too-fast": "Too fast - try again",
    "enroll-completed": "Enrolled",
    "enroll-failed": "Enrollment failed",
    "enroll-duplicate": "Finger already enrolled",
    "enroll-data-full": "Fingerprint storage full",
    "enroll-disconnected": "Device disconnected",
    "enroll-unknown-error": "Unknown error"
}

function enrollStageLabel(status) {
    return STAGE_LABELS[status] || status
}

// "right-index-finger" -> "Right Index Finger"; unknown names pass through.
function fingerLabel(name) {
    if (FINGERS.indexOf(name) === -1) return name
    return name.split("-").map(w => w.charAt(0).toUpperCase() + w.slice(1)).join(" ")
}
