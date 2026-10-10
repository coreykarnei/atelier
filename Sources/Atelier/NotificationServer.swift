import AppKit
import UserNotifications
import AtelierIPC

/// The one-time notification-permission ask (POLISH_PLAN §5): fires the moment
/// the first agent exists — a promote or a restore — never at bare launch. A
/// fresh Landing asks for nothing.
enum NotificationPermission {
    private static var requested = false

    static func requestOnce() {
        guard !requested else { return }
        requested = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error { NSLog("Atelier: notification auth error: \(error)") }
            else { NSLog("Atelier: notification auth granted=\(granted)") }
        }
    }
}

/// Listens on Atelier's unix domain socket for `NotifyMessage`s sent by the
/// `atelier-notify` CLI (invoked from Claude Code's Stop / Notification hooks) and
/// posts them as real macOS notifications.
///
/// This is the vision's "the agent talks to the OS directly" — implemented through
/// Claude Code's hook system, not by sniffing the terminal bell (TECHNICAL_PLAN §2.3).
final class NotificationServer: NSObject, UNUserNotificationCenterDelegate {
    private var listenFD: Int32 = -1
    private var acceptSource: DispatchSource?
    private let queue = DispatchQueue(label: "dev.sterlingcore.atelier.notify")

    /// Workspace commands from the `atelier` CLI arrive on the same socket;
    /// the app delegate handles them (main thread).
    var onCommand: ((CommandMessage) -> Void)?

    /// Every agent lifecycle event (incl. `working`, which posts no banner) —
    /// feeds the per-tab attention state (MILESTONE_1 §7.1). The full message is
    /// passed so the app can classify (e.g. idle-waiting vs needs-permission).
    /// Main thread.
    var onAgentEvent: ((NotifyMessage) -> Void)?

    /// A notification banner was clicked; the payload is the Claude session id.
    /// Click-to-focus the right session tab (TECHNICAL_PLAN §4 M3). Main thread.
    var onNotificationClick: ((String) -> Void)?

    /// Dev-only debug commands (window snapshots for the polish pass's visual
    /// loop). Main thread.
    var onDebug: ((DebugMessage) -> Void)?

    /// Begin listening and take the notification-center delegate. Deliberately
    /// does NOT request authorization — that prompt fires on first promote
    /// (the moment the first agent exists; POLISH_PLAN §5), via
    /// `NotificationPermission.requestOnce()`.
    ///
    /// Returns false, touching nothing, when another Atelier already answers
    /// on this state directory's socket (owner report 2026-10-08: a film
    /// build launched without `ATELIER_STATE_DIR` unlinked the live app's
    /// socket, then deleted its own on quit — every hook after that was
    /// dropped, and the live app's dots stopped moving).
    func start() -> Bool {
        let bound: Bool = queue.sync {
            if AtelierIPC.isAppListening() { return false }
            bind()
            return true
        }
        if bound { UNUserNotificationCenter.current().delegate = self }
        return bound
    }

    func stop() {
        queue.sync {
            directoryWatch?.cancel()
            directoryWatch = nil
            // Only our own socket: a path some other instance bound since
            // is theirs to remove.
            let ours = ownsSocketPath
            closeListener()
            if ours { unlink(AtelierIPC.socketPath()) }
        }
    }

    // MARK: Socket

    /// The socket file we bound, by identity — a path is only ours while
    /// it still names this inode.
    private var boundFile: (dev: dev_t, ino: ino_t)?

    /// Watches the state directory, so a socket removed or replaced from
    /// outside — another instance's start or quit, an `rm` — is rebound at
    /// once instead of leaving every hook to fail until relaunch.
    private var directoryWatch: DispatchSourceFileSystemObject?

    private var ownsSocketPath: Bool {
        var st = stat()
        guard let boundFile, stat(AtelierIPC.socketPath(), &st) == 0 else { return false }
        return st.st_dev == boundFile.dev && st.st_ino == boundFile.ino
    }

    private func closeListener() {
        acceptSource?.cancel()
        acceptSource = nil
        if listenFD >= 0 { close(listenFD) }
        listenFD = -1
        boundFile = nil
    }

    /// The directory changed: if our socket is no longer at its path, bind
    /// a fresh one there. The first instance owns the directory — an older
    /// build that took the path on launch gives it back here.
    private func reclaimIfLost() {
        guard boundFile != nil, !ownsSocketPath else { return }
        NSLog("Atelier: notification socket was removed or replaced — rebinding")
        closeListener()
        bind()
    }

    private func watchDirectory(_ dir: String) {
        directoryWatch?.cancel()
        let fd = open(dir, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .delete, .rename], queue: queue
        )
        source.setEventHandler { [weak self] in self?.reclaimIfLost() }
        source.setCancelHandler { close(fd) }
        source.resume()
        directoryWatch = source
    }

    /// On `queue`, like everything that touches the listener.
    private func bind() {
        let path = AtelierIPC.ensureSocketDirectory()
        // A deleted directory is recreated above; watch whichever is there now.
        watchDirectory((path as NSString).deletingLastPathComponent)
        unlink(path) // clear any stale socket from a previous run

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { NSLog("Atelier: socket() failed"); return }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: addr.sun_path) else {
            NSLog("Atelier: socket path too long"); close(fd); return
        }
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: bytes.count + 1) { dst in
                for (i, b) in bytes.enumerated() { dst[i] = CChar(bitPattern: b) }
                dst[bytes.count] = 0
            }
        }

        let bound = withUnsafePointer(to: &addr) { p in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) { sp in
                Darwin.bind(fd, sp, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0 else { NSLog("Atelier: bind() failed errno=\(errno)"); close(fd); return }
        guard listen(fd, 8) == 0 else { NSLog("Atelier: listen() failed"); close(fd); return }

        var st = stat()
        if stat(path, &st) == 0 { boundFile = (st.st_dev, st.st_ino) }
        listenFD = fd
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.acceptOne() }
        source.resume()
        acceptSource = source as? DispatchSource
        NSLog("Atelier: notification socket listening at \(path)")
    }

    private func acceptOne() {
        let client = accept(listenFD, nil, nil)
        guard client >= 0 else { return }
        defer { close(client) }

        // Hooks send one short JSON line then close — a single read suffices.
        var buffer = [UInt8](repeating: 0, count: 4096)
        let n = read(client, &buffer, buffer.count)
        guard n > 0 else { return }
        let data = Data(buffer[0..<n])

        for line in data.split(separator: 0x0A) where !line.isEmpty {
            let payload = Data(line)
            if let msg = try? JSONDecoder().decode(NotifyMessage.self, from: payload) {
                DispatchQueue.main.async { self.post(msg) }
            } else if let cmd = try? JSONDecoder().decode(CommandMessage.self, from: payload) {
                DispatchQueue.main.async { self.onCommand?(cmd) }
            } else if let dbg = try? JSONDecoder().decode(DebugMessage.self, from: payload) {
                DispatchQueue.main.async { self.onDebug?(dbg) }
            }
        }
    }

    private func post(_ msg: NotifyMessage) {
        NSLog("Atelier: notify received kind=\(msg.kind.rawValue) session=\(msg.sessionId ?? "-")")
        onAgentEvent?(msg)

        // `working` and `session` are tab state only — no banner for "you
        // pressed Enter" or "a conversation opened." Nor `inputNeeded`: it is
        // `idle_prompt`, a minute after the Stop that already rang — a second
        // chime would re-notify (§1.3).
        guard msg.kind != .working, msg.kind != .session, msg.kind != .inputNeeded else { return }

        // The sound vocabulary the dotfiles IDE used (POLISH_PLAN §7, resolved
        // 2026-09-16): Blow = finished, Tink = needs you. One audio path — the
        // app plays it, the banner stays silent — so it's heard whether or not
        // banners are authorised, and for remote sessions it sounds *here*.
        // Settings → Sounds turns it off; a sound hook of the user's own
        // that still fires under Atelier turns it off too, so a turn never
        // rings twice (`AgentHooks.userSoundHooks`).
        if Settings.sounds, AgentHooks.userSoundHooks().isEmpty {
            Self.sound(for: msg.kind)?.play()
        }

        let content = UNMutableNotificationContent()
        content.title = msg.title
        content.body = msg.body
        content.sound = nil
        if let sessionId = msg.sessionId {
            content.userInfo = ["sessionId": sessionId]
        }
        let request = UNNotificationRequest(
            identifier: UUID().uuidString, content: content, trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    private static func sound(for kind: NotifyMessage.Kind) -> NSSound? {
        switch kind {
        case .stop: return NSSound(named: "Blow")
        case .blocked: return NSSound(named: "Tink")
        case .inputNeeded, .working, .session: return nil
        }
    }

    // MARK: UNUserNotificationCenterDelegate

    // Show banners even while Atelier is frontmost (the agent pane may be in another
    // pane than the one you're watching).
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner])
    }

    // Click-to-focus: the banner carries the Claude session id; route to the app.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if let sessionId = response.notification.request.content.userInfo["sessionId"] as? String {
            DispatchQueue.main.async { self.onNotificationClick?(sessionId) }
        }
        completionHandler()
    }
}
