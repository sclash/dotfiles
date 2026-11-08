pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Polkit
import "polkitParse.js" as Parse

// PolkitService — Quickshell is the session's polkit authentication agent,
// so password prompts (pkexec, udisks, …) appear inside the shell instead
// of a separate agent's window. A session has exactly one agent, which is
// why nixos/configuration.nix no longer starts hyprpolkitagent.
//
// Routing: a request is shown inline by the view that claimed it (today:
// the Identity Manager's Face view, for its own `pkexec howdy …`); every
// other request goes to components/launchers/PolkitPrompt.qml.
//
// QS_NO_POLKIT_AGENT=1 skips registration (tests run inside a live
// session and must not replace the real agent).
QtObject {
    id: root

    readonly property bool disabled: !!Quickshell.env("QS_NO_POLKIT_AGENT")
    property var agent: null
    readonly property bool registered: agent !== null && agent.isRegistered
    readonly property var flow: agent !== null && agent.isActive ? agent.flow : null
    readonly property bool active: flow !== null

    // Set by the Identity Manager while its Face view is open.
    property bool faceClaim: false
    readonly property bool faceInline: active && Parse.routeInline(faceClaim, flow.actionId, flow.message)

    function submit(value) {
        if (root.flow !== null && root.flow.isResponseRequired) root.flow.submit(value)
    }
    function cancel() {
        if (root.flow !== null) root.flow.cancelAuthenticationRequest()
    }

    property Component _agentComponent: Component { PolkitAgent {} }

    Component.onCompleted: {
        if (!root.disabled) root.agent = root._agentComponent.createObject(root)
    }
}
