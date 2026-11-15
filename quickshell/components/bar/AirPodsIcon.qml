import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../services"
import "../../services/airPodsParse.js" as Parse

// Bar badge: the lowest known AirPods level, click to toggle the launcher.
// A pure reader over AirPodsService — no process, timer or write lives here.
// Hidden whenever the service has nothing true to say, so it never sits in the
// bar showing stale levels (the service keeps them after the daemon stops).
Rectangle {
    id: root
    signal clicked()

    visible: AirPodsService.daemonReachable
        && AirPodsService.hasAirPods
        && AirPodsService.hasBattery

    // ---------- readings ----------
    // Every shape the daemon can report, with unknown levels dropped: a pod or
    // case it has stopped hearing from reports -1 and must not win the minimum.
    readonly property var knownLevels: {
        const all = [
            AirPodsService.leftPod,
            AirPodsService.rightPod,
            AirPodsService.caseBattery,
            AirPodsService.headsetBattery
        ]
        const levels = []
        for (let i = 0; i < all.length; i++) {
            const level = all[i] ? all[i].level : Parse.LEVEL_UNKNOWN
            if (level !== Parse.LEVEL_UNKNOWN) levels.push(level)
        }
        return levels
    }

    readonly property int lowestLevel: {
        if (root.knownLevels.length === 0) return -1
        let lowest = root.knownLevels[0]
        for (let i = 1; i < root.knownLevels.length; i++) {
            if (root.knownLevels[i] < lowest) lowest = root.knownLevels[i]
        }
        return lowest
    }

    readonly property string batteryText: root.lowestLevel >= 0 ? root.lowestLevel + "%" : ""

    readonly property bool charging: AirPodsService.leftPod.charging
        || AirPodsService.rightPod.charging
        || AirPodsService.caseBattery.charging
        || AirPodsService.headsetBattery.charging

    readonly property color levelColor: {
        if (root.lowestLevel >= 0 && root.lowestLevel <= 20) return Theme.warning
        if (root.charging) return Theme.accent
        return Theme.fg
    }

    // ---------- tooltip ----------
    readonly property string tooltipText: {
        const name = AirPodsService.deviceName
        const model = AirPodsService.modelName
        const head = name === "" ? model : (model === "" || model === name ? name : name + " · " + model)

        const levels = AirPodsService.isHeadset
            ? "H " + Parse.levelText(AirPodsService.headsetBattery.level)
            : "L " + Parse.levelText(AirPodsService.leftPod.level)
                + " · R " + Parse.levelText(AirPodsService.rightPod.level)
                + " · C " + Parse.levelText(AirPodsService.caseBattery.level)

        const state = []
        if (AirPodsService.noiseMode !== Parse.NOISE_UNKNOWN)
            state.push(Parse.noiseModeName(AirPodsService.noiseMode))
        if (AirPodsService.supportsConversationalAwareness)
            state.push("CA " + (AirPodsService.conversationalAwareness ? "on" : "off"))
        if (AirPodsService.supportsOneBudANC)
            state.push("1-bud " + (AirPodsService.oneBudANC ? "on" : "off"))
        const ear = ["one out", "both out", "off"][AirPodsService.earDetectionBehavior]
        if (ear !== undefined) state.push("Ear " + ear)

        return [head, levels, state.join(" · ")].filter(line => line !== "").join("\n")
    }

    height: Theme.barIconSlot
    Layout.preferredWidth: badgeRow.implicitWidth + 14
    radius: Theme.roundingItem
    color: badgeMA.containsMouse ? Theme.bgHover : "transparent"
    Behavior on color { ColorAnimation { duration: Theme.durationFast } }

    RowLayout {
        id: badgeRow
        anchors.centerIn: parent
        spacing: 4

        Text {
            text: Icons.airpods
            font.family: Theme.fontFamily
            font.pixelSize: Theme.barIconSize
            color: root.levelColor
        }

        Text {
            visible: root.batteryText !== ""
            text: root.batteryText
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
            color: root.levelColor
        }
    }

    BarToolTip {
        id: badgeTip
        visible: badgeMA.containsMouse && root.tooltipText !== ""
        text: root.tooltipText
        anchorItem: root
    }

    MouseArea {
        id: badgeMA
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
