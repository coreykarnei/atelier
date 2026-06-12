import AppKit
import UserNotifications
import AtelierIPC

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

    /// Request authorization and begin listening. Safe to call once at launch.
    func start() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error { NSLog("Atelier: notification auth error: \(error)") }
            else { NSLog("Atelier: notification auth granted=\(granted)") }
        }
        bind()
    }

    func stop() {
        acceptSource?.cancel()
        if listenFD >= 0 { close(listenFD) }
        unlink(AtelierIPC.socketPath())
    }

    // MARK: Socket

    private func bind() {
        let path = AtelierIPC.ensureSocketDirectory()
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

        // `working` is tab-state only — no banner for "you pressed Enter."
        guard msg.kind != .working else { return }

        let content = UNMutableNotificationContent()
        content.title = msg.title
        content.body = msg.body
        content.sound = .default
        if let sessionId = msg.sessionId {
            content.userInfo = ["sessionId": sessionId]
        }
        let request = UNNotificationRequest(
            identifier: UUID().uuidString, content: content, trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: UNUserNotificationCenterDelegate

    // Show banners even while Atelier is frontmost (the agent pane may be in another
    // pane than the one you're watching).
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
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
