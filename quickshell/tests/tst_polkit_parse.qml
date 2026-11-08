import QtQuick
import QtTest
import "../services/polkitParse.js" as Parse

// Pure-logic tests for PolkitService routing (services/polkitParse.js).
TestCase {
    name: "PolkitParse"

    // pkexec's message (polkit 127): "Authentication is needed to run
    // `<program> <args>' as the super user".
    readonly property string howdyMsg: "Authentication is needed to run `/run/current-system/sw/bin/howdy -U asergi -y add glasses' as the super user"

    function test_howdy_request() {
        verify(Parse.isHowdyRequest("org.freedesktop.policykit.exec", howdyMsg))
    }
    function test_other_pkexec_is_not_howdy() {
        verify(!Parse.isHowdyRequest("org.freedesktop.policykit.exec",
            "Authentication is needed to run `/run/current-system/sw/bin/bash' as the super user"))
        // "howdy" only as an argument to something else does not count.
        verify(!Parse.isHowdyRequest("org.freedesktop.policykit.exec",
            "Authentication is needed to run `/usr/bin/rm -rf /var/lib/howdy' as the super user"))
    }
    function test_other_actions_are_not_howdy() {
        verify(!Parse.isHowdyRequest("org.freedesktop.udisks2.filesystem-mount", howdyMsg))
        verify(!Parse.isHowdyRequest("", ""))
    }

    function test_inline_routing() {
        verify(Parse.routeInline(true, "org.freedesktop.policykit.exec", howdyMsg))
        verify(!Parse.routeInline(false, "org.freedesktop.policykit.exec", howdyMsg))   // Face view not open
        verify(!Parse.routeInline(true, "org.freedesktop.udisks2.filesystem-mount", "Mount"))
    }
}
