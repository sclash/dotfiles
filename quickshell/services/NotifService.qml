pragma Singleton
import QtQuick
import Quickshell.Io
import Quickshell.Services.Notifications

QtObject {
    id: root
    property bool dnd: false
    property int unreadCount: 0
    property bool hasUnread: unreadCount > 0
    property var history: []
    property bool available: true
    property bool soundEnabled: true
    property string fallbackSound: Qt.resolvedUrl("../assets/notify.ogg").toString().replace("file://", "")

    // Host the notification server to acquire org.freedesktop.Notifications
    property NotificationServer server: NotificationServer {
        id: notifServer
        keepOnReload: false
        actionsSupported: true
        bodySupported: true
        imageSupported: true
        onNotification: (n) => root.handleNotification(n)
    }

    function handleNotification(n) {
        try { n.tracked = true } catch(e) {}
        const copy = root.history.slice()
        copy.unshift({
            id: n.id || Date.now(),
            appName: n.appName || "Unknown",
            appIcon: n.appIcon || "",
            summary: n.summary || "",
            body: n.body || "",
            urgency: n.urgency !== undefined ? n.urgency : 1,
            timestamp: new Date(),
            image: n.image || "",
            actions: n.actions ? n.actions : [],
            notification: n
        })
        if (copy.length > 50) {
            const removed = copy.pop()
            if (removed && removed.notification && removed.notification.dismiss) try { removed.notification.dismiss() } catch(e) {}
        }
        root.history = copy
        if (!root.dnd) root.unreadCount++
        root.playSound(n)
    }

    property Process soundProc: Process {
        id: soundProcess
        command: ["pw-play", root.fallbackSound]
    }

    function playSound(n) {
        if (!root.soundEnabled || root.dnd) return
        try {
            const hints = n.hints
            if (hints && hints["suppress-sound"] === true) return
            let file = hints && hints["sound-file"]
            if (!file || file.length === 0) file = root.fallbackSound
            if (!file || file.length === 0) return
            if (file.indexOf("file://") === 0) file = file.substring(7)
            soundProcess.command = ["pw-play", file]
            soundProcess.running = true
        } catch(e) {
            console.log("NotifService: failed to play notification sound: " + e)
        }
    }

    function clearHistory() {
        for (let i=0;i<history.length;i++) {
            const entry = history[i]
            const n = entry.notification
            if (n && n.dismiss) try { n.dismiss() } catch(e) {}
            else if (entry && entry.dismiss) try { entry.dismiss() } catch(e) {}
        }
        history = []
        unreadCount = 0
    }
    function dismiss(idx) {
        if (idx <0 || idx >= history.length) return
        const entry = history[idx]
        const n = entry.notification
        if (n && n.dismiss) try { n.dismiss() } catch(e) {}
        const copy = history.slice()
        copy.splice(idx,1)
        history = copy
        if (unreadCount >0) unreadCount--
    }
    function toggleDnd() { dnd = !dnd }

    Component.onCompleted: {
        if (!notifServer) available = false
        else {
            try {
                const tracked = notifServer.trackedNotifications.values
                if (tracked && tracked.length > 0) {
                    const copy = []
                    const start = Math.max(0, tracked.length - 50)
                    for (let i = tracked.length - 1; i >= start; i--) {
                        const n = tracked[i]
                        copy.push({
                            id: n.id || Date.now()+i,
                            appName: n.appName || "Unknown",
                            appIcon: n.appIcon || "",
                            summary: n.summary || "",
                            body: n.body || "",
                            urgency: n.urgency !== undefined ? n.urgency : 1,
                            timestamp: new Date(),
                            image: n.image || "",
                            actions: n.actions ? n.actions : [],
                            notification: n
                        })
                    }
                    root.history = copy
                    root.unreadCount = copy.length
                }
            } catch(e) {}
        }
    }
}
