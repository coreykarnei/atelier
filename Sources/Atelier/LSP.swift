import Foundation

/// A diagnostic as the editor needs it: where, how bad, what it says.
struct LSPDiagnostic {
    enum Severity: Int { case error = 1, warning = 2, information = 3, hint = 4 }
    let startLine: Int      // 0-based (LSP convention)
    let startCharacter: Int // UTF-16 code units
    let endLine: Int
    let endCharacter: Int
    let severity: Severity
    let message: String
}

/// One language server for one repo root (M2.5, TECHNICAL_PLAN §3.3 —
/// go-to-definition and diagnostics, nothing else). JSON-RPC over stdio;
/// v1 speaks only to sourcekit-lsp. The client is deliberately dynamic
/// (JSONSerialization, not a Codable mirror of the whole protocol): we use
/// four notifications and one request.
final class LSPClient {
    private let process = Process()
    private let stdin = Pipe()
    private let stdout = Pipe()
    /// All mutable state lives on this queue; completions hop to main.
    private let queue = DispatchQueue(label: "atelier.lsp")

    private var buffer = Data()
    private var nextID = 1
    private var pending: [Int: ([String: Any]?) -> Void] = [:]
    private var initialized = false
    /// Notifications queued while the initialize handshake is in flight.
    private var deferredUntilReady: [[String: Any]] = []
    private var documentVersions: [String: Int] = [:]

    let root: String
    /// Fired on the main queue whenever the server publishes diagnostics.
    var onDiagnostics: ((_ path: String, _ diagnostics: [LSPDiagnostic]) -> Void)?

    init?(root: String) {
        self.root = root
        // sourcekit-lsp rides the active toolchain; xcrun finds it without
        // hardcoding an Xcode path.
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["sourcekit-lsp"]
        process.currentDirectoryURL = URL(fileURLWithPath: root, isDirectory: true)
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }

        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let self, !data.isEmpty else { return }
            self.queue.async { self.consume(data) }
        }
        initialize()
    }

    deinit {
        stdout.fileHandleForReading.readabilityHandler = nil
        if process.isRunning { process.terminate() }
    }

    func shutdown() {
        stdout.fileHandleForReading.readabilityHandler = nil
        if process.isRunning { process.terminate() }
    }

    // MARK: Handshake

    private func initialize() {
        let rootURI = URL(fileURLWithPath: root, isDirectory: true).absoluteString
        request("initialize", params: [
            "processId": Int(ProcessInfo.processInfo.processIdentifier),
            "rootUri": rootURI,
            "capabilities": [
                "textDocument": [
                    "publishDiagnostics": [:],
                    "diagnostic": [:],
                    "definition": [:],
                ] as [String: Any],
            ] as [String: Any],
            "workspaceFolders": [["uri": rootURI, "name": (root as NSString).lastPathComponent]],
        ]) { [weak self] _ in
            guard let self else { return }
            self.queue.async {
                self.write(["jsonrpc": "2.0", "method": "initialized", "params": [:] as [String: Any]])
                self.initialized = true
                for message in self.deferredUntilReady { self.write(message) }
                self.deferredUntilReady.removeAll()
            }
        }
    }

    // MARK: Document lifecycle

    func didOpen(path: String, text: String) {
        queue.async {
            self.documentVersions[path] = 1
            self.notifyWhenReady("textDocument/didOpen", params: [
                "textDocument": [
                    "uri": Self.uri(path), "languageId": "swift", "version": 1, "text": text,
                ] as [String: Any],
            ])
        }
    }

    func didChange(path: String, text: String) {
        queue.async {
            let version = (self.documentVersions[path] ?? 1) + 1
            self.documentVersions[path] = version
            self.notifyWhenReady("textDocument/didChange", params: [
                "textDocument": ["uri": Self.uri(path), "version": version] as [String: Any],
                // A change event without a range replaces the whole document.
                "contentChanges": [["text": text]],
            ])
        }
    }

    func didSave(path: String) {
        queue.async {
            self.notifyWhenReady("textDocument/didSave", params: [
                "textDocument": ["uri": Self.uri(path)],
            ])
        }
    }

    func didClose(path: String) {
        queue.async {
            self.documentVersions[path] = nil
            self.notifyWhenReady("textDocument/didClose", params: [
                "textDocument": ["uri": Self.uri(path)],
            ])
        }
    }

    /// Pull diagnostics (LSP 3.17) — sourcekit-lsp's primary mechanism; it
    /// rarely pushes. Results flow through `onDiagnostics` like a push would.
    func requestDiagnostics(path: String) {
        request("textDocument/diagnostic", params: [
            "textDocument": ["uri": Self.uri(path)],
        ]) { [weak self] response in
            guard let self,
                  let result = response?["result"] as? [String: Any],
                  let items = result["items"] as? [[String: Any]] else { return }
            let diagnostics = items.compactMap(Self.diagnostic(from:))
            DispatchQueue.main.async { self.onDiagnostics?(path, diagnostics) }
        }
    }

    // MARK: Definition

    /// Resolve the definition under `line:character` (0-based, LSP-style).
    /// Completion lands on main with (path, line, column) 1-based, ready for
    /// `EditorPane.reveal`.
    func definition(
        path: String, line: Int, character: Int,
        completion: @escaping ([(path: String, line: Int, column: Int)]) -> Void
    ) {
        request("textDocument/definition", params: [
            "textDocument": ["uri": Self.uri(path)],
            "position": ["line": line, "character": character],
        ]) { response in
            var locations: [[String: Any]] = []
            switch response?["result"] {
            case let array as [[String: Any]]: locations = array
            case let single as [String: Any]: locations = [single]
            default: break
            }
            let targets: [(String, Int, Int)] = locations.compactMap { location in
                // Location {uri, range} or LocationLink {targetUri, targetSelectionRange}
                let uri = (location["uri"] ?? location["targetUri"]) as? String
                let range = (location["range"] ?? location["targetSelectionRange"]) as? [String: Any]
                guard let uri, let url = URL(string: uri), url.isFileURL,
                      let start = range?["start"] as? [String: Any],
                      let line = start["line"] as? Int,
                      let character = start["character"] as? Int
                else { return nil }
                return (url.path, line + 1, character + 1)
            }
            DispatchQueue.main.async { completion(targets) }
        }
    }

    // MARK: JSON-RPC plumbing

    private static func uri(_ path: String) -> String {
        URL(fileURLWithPath: path).absoluteString
    }

    private func request(_ method: String, params: [String: Any], completion: @escaping ([String: Any]?) -> Void) {
        queue.async {
            let id = self.nextID
            self.nextID += 1
            self.pending[id] = completion
            self.write(["jsonrpc": "2.0", "id": id, "method": method, "params": params])
        }
    }

    /// Notifications other than `initialize` wait for the handshake.
    private func notifyWhenReady(_ method: String, params: [String: Any]) {
        let message: [String: Any] = ["jsonrpc": "2.0", "method": method, "params": params]
        if initialized { write(message) } else { deferredUntilReady.append(message) }
    }

    private func write(_ message: [String: Any]) {
        guard let body = try? JSONSerialization.data(withJSONObject: message) else { return }
        var frame = Data("Content-Length: \(body.count)\r\n\r\n".utf8)
        frame.append(body)
        stdin.fileHandleForWriting.write(frame)
    }

    private func consume(_ data: Data) {
        buffer.append(data)
        while let message = nextFrame() { dispatch(message) }
    }

    private func nextFrame() -> [String: Any]? {
        guard let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let header = String(decoding: buffer[..<headerEnd.lowerBound], as: UTF8.self)
        guard let lengthLine = header.split(separator: "\r\n").first(where: { $0.lowercased().hasPrefix("content-length:") }),
              let length = Int(lengthLine.split(separator: ":")[1].trimmingCharacters(in: .whitespaces))
        else { buffer.removeAll(); return nil }
        let bodyStart = headerEnd.upperBound
        guard buffer.count - bodyStart >= length else { return nil }
        let body = buffer.subdata(in: bodyStart..<(bodyStart + length))
        buffer.removeSubrange(..<(bodyStart + length))
        return (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
    }

    private func dispatch(_ message: [String: Any]) {
        if let method = message["method"] as? String {
            if let id = message["id"] {
                // A request *from* the server: answer honestly-empty so it
                // never stalls waiting on us. workspace/configuration wants
                // one entry per requested item.
                var result: Any = NSNull()
                if method == "workspace/configuration",
                   let params = message["params"] as? [String: Any],
                   let items = params["items"] as? [Any] {
                    result = Array(repeating: NSNull(), count: items.count)
                }
                write(["jsonrpc": "2.0", "id": id, "result": result])
            } else if method == "textDocument/publishDiagnostics",
                      let params = message["params"] as? [String: Any],
                      let uriString = params["uri"] as? String,
                      let url = URL(string: uriString), url.isFileURL {
                let diagnostics = (params["diagnostics"] as? [[String: Any]] ?? []).compactMap(Self.diagnostic(from:))
                let path = url.path
                DispatchQueue.main.async { self.onDiagnostics?(path, diagnostics) }
            }
        } else if let id = message["id"] as? Int, let completion = pending.removeValue(forKey: id) {
            completion(message)
        }
    }

    private static func diagnostic(from json: [String: Any]) -> LSPDiagnostic? {
        guard let range = json["range"] as? [String: Any],
              let start = range["start"] as? [String: Any],
              let end = range["end"] as? [String: Any],
              let startLine = start["line"] as? Int, let startCharacter = start["character"] as? Int,
              let endLine = end["line"] as? Int, let endCharacter = end["character"] as? Int
        else { return nil }
        return LSPDiagnostic(
            startLine: startLine, startCharacter: startCharacter,
            endLine: endLine, endCharacter: endCharacter,
            severity: LSPDiagnostic.Severity(rawValue: json["severity"] as? Int ?? 1) ?? .error,
            message: json["message"] as? String ?? ""
        )
    }
}

/// One server per repo root, spawned on first use, reused across sessions,
/// torn down at quit. Swift-only in v1 (the plan's sourcekit-lsp scope);
/// other languages simply get no client and the editor stays plain.
enum LSPRegistry {
    private static var clients: [String: LSPClient] = [:]

    static func client(for root: String) -> LSPClient? {
        if let existing = clients[root] { return existing }
        guard let client = LSPClient(root: root) else { return nil }
        clients[root] = client
        return client
    }

    static func terminateAll() {
        for client in clients.values { client.shutdown() }
        clients.removeAll()
    }
}
