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

    // Transient toast surface — on by default. Suppressed automatically
    // while dnd is true (re-enabled when dnd is lifted).
    property bool toastEnabled: true
    property int toastTimeoutMs: 3000
    property int toastMaxVisible: 5
    property int toastQueueMax: 20
    property var toasts: []
    property var toastQueue: []

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
        const entry = {
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
        }
        const copy = root.history.slice()
        copy.unshift(entry)
        if (copy.length > 50) {
            const removed = copy.pop()
            if (removed && removed.notification && removed.notification.dismiss) try { removed.notification.dismiss() } catch(e) {}
        }
        root.history = copy
        if (!root.dnd) root.unreadCount++
        root.playSound(n)
        root.spawnToast(entry)
    }

    function spawnToast(entry) {
        if (!entry) return
        if (!root.toastEnabled) return
        // DND suppresses toast entirely, regardless of urgency.
        if (root.dnd) return
        const timeout = Math.max(1000, Math.min(10000, root.toastTimeoutMs || 3000))
        const stamped = Object.assign({}, entry, { _toastId: Date.now() + "_" + Math.random().toString(36).slice(2,8), _expiresAt: Date.now() + timeout, _timeout: timeout })
        // Max 5 visible; extras go to a FIFO queue and are shown as slots free up.
        if (root.toasts.length >= root.toastMaxVisible) {
            const q = root.toastQueue.slice()
            q.push(stamped)
            while (q.length > root.toastQueueMax) q.shift()
            root.toastQueue = q
        } else {
            const next = root.toasts.slice()
            next.push(stamped)
            root.toasts = next
        }
    }

    // Promote queued toasts into the visible list until the stack is full.
    function promoteFromQueue() {
        if (!root.toastEnabled || root.dnd) return
        const t = root.toasts.slice()
        const q = root.toastQueue.slice()
        const now = Date.now()
        let changed = false
        while (t.length < root.toastMaxVisible && q.length > 0) {
            const queued = q.shift()
            // Give the promoted toast a full lifetime from the moment it is shown.
            t.push(Object.assign({}, queued, { _expiresAt: now + (queued._timeout || root.toastTimeoutMs || 3000) }))
            changed = true
        }
        if (changed) root.toasts = t
        if (q.length !== root.toastQueue.length) root.toastQueue = q
    }

    function dismissToast(toastId) {
        const next = root.toasts.filter(t => t._toastId !== toastId)
        if (next.length !== root.toasts.length) {
            root.toasts = next
            root.promoteFromQueue()
        }
    }

    // Called by the reaper timer; drop expired visible toasts, then backfill from queue.
    function reapExpiredToasts() {
        const now = Date.now()
        const live = root.toasts.filter(t => !t._expiresAt || t._expiresAt > now)
        if (live.length !== root.toasts.length) {
            root.toasts = live
            root.promoteFromQueue()
        }
    }

    function clearToasts() { root.toasts = []; root.toastQueue = [] }

    function toggleToast() { root.toastEnabled = !root.toastEnabled; if (!root.toastEnabled) root.clearToasts() }

    function toggleSound() { root.soundEnabled = !root.soundEnabled }

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
