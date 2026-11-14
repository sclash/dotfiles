.pragma library

function shouldRun(connectedAirPods, panelOpen, statusConnected) {
    return connectedAirPods === true || panelOpen === true || statusConnected === true
}

function nextAction(want, active) {
    if (want === true && active !== true) return "start"
    if (want !== true && active === true) return "stop"
    return "none"
}
