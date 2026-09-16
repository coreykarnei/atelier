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

import CodeEditLanguages

/// Which language server to run for which buffer (M2.6). No extensions,
/// no marketplace: a language server is a binary that speaks one protocol,
/// so supporting a language is knowing its binary. Each entry lists
/// candidates in preference order; the first one installed wins. The PATH
/// is the owner's login-shell PATH (probed once), so whatever `npm i -g`,
/// `uv tool install`, cargo or brew put on it is found — plus the usual
/// tool bins for good measure. Nothing installed → the editor stays plain
/// for that language, silently.
enum LSPServers {
    struct Spec {
        let key: String
        let languageId: String
        let candidates: [[String]]
    }

    static func spec(for language: CodeLanguage) -> Spec? {
        switch language.id {
        case .swift:
            return Spec(key: "swift", languageId: "swift", candidates: [["/usr/bin/xcrun", "sourcekit-lsp"]])
        case .python:
            return Spec(key: "python", languageId: "python", candidates: [
                ["pyright-langserver", "--stdio"], ["basedpyright-langserver", "--stdio"],
                ["pylsp"], ["jedi-language-server"],
            ])
        case .typescript, .tsx:
            return Spec(key: "typescript", languageId: language.id == .tsx ? "typescriptreact" : "typescript",
                        candidates: [["typescript-language-server", "--stdio"], ["deno", "lsp"]])
        case .javascript, .jsx:
            return Spec(key: "typescript", languageId: language.id == .jsx ? "javascriptreact" : "javascript",
                        candidates: [["typescript-language-server", "--stdio"], ["deno", "lsp"]])
        case .rust:
            return Spec(key: "rust", languageId: "rust", candidates: [["rust-analyzer"]])
        case .go, .goMod:
            return Spec(key: "go", languageId: language.id == .goMod ? "go.mod" : "go", candidates: [["gopls"]])
        case .c:
            return Spec(key: "clangd", languageId: "c", candidates: [["clangd"]])
        case .cpp:
            return Spec(key: "clangd", languageId: "cpp", candidates: [["clangd"]])
        case .objc:
            return Spec(key: "clangd", languageId: "objective-c", candidates: [["clangd"]])
        case .lua:
            return Spec(key: "lua", languageId: "lua", candidates: [["lua-language-server"]])
        case .bash:
            return Spec(key: "bash", languageId: "shellscript", candidates: [["bash-language-server", "start"]])
        case .json:
            return Spec(key: "json", languageId: "json", candidates: [["vscode-json-language-server", "--stdio"]])
        case .yaml:
            return Spec(key: "yaml", languageId: "yaml", candidates: [["yaml-language-server", "--stdio"]])
        case .html:
            return Spec(key: "html", languageId: "html", candidates: [["vscode-html-language-server", "--stdio"]])
        case .css:
            return Spec(key: "css", languageId: "css", candidates: [["vscode-css-language-server", "--stdio"]])
        case .ruby:
            return Spec(key: "ruby", languageId: "ruby", candidates: [["ruby-lsp"], ["solargraph", "stdio"]])
        case .zig:
            return Spec(key: "zig", languageId: "zig", candidates: [["zls"]])
        case .kotlin:
            return Spec(key: "kotlin", languageId: "kotlin", candidates: [["kotlin-language-server"]])
        case .markdown:
            return Spec(key: "markdown", languageId: "markdown", candidates: [["marksman", "server"]])
        case .toml:
            return Spec(key: "toml", languageId: "toml", candidates: [["taplo", "lsp", "stdio"]])
        case .dockerfile:
            return Spec(key: "dockerfile", languageId: "dockerfile", candidates: [["docker-langserver", "--stdio"]])
        case .elixir:
            return Spec(key: "elixir", languageId: "elixir", candidates: [["elixir-ls"], ["expert", "--stdio"]])
        case .haskell:
            return Spec(key: "haskell", languageId: "haskell", candidates: [["haskell-language-server-wrapper", "--lsp"]])
        case .ocaml, .ocamlInterface:
            return Spec(key: "ocaml", languageId: "ocaml", candidates: [["ocamllsp"]])
        case .dart:
            return Spec(key: "dart", languageId: "dart", candidates: [["dart", "language-server", "--protocol=lsp"]])
        case .php:
            return Spec(key: "php", languageId: "php", candidates: [["intelephense", "--stdio"], ["phpactor", "language-server"]])
        case .cSharp:
            return Spec(key: "csharp", languageId: "csharp", candidates: [["csharp-ls"], ["OmniSharp", "-lsp"]])
        case .java:
            return Spec(key: "java", languageId: "java", candidates: [["jdtls"]])
        case .scala:
            return Spec(key: "scala", languageId: "scala", candidates: [["metals"]])
        case .julia:
            return Spec(key: "julia", languageId: "julia", candidates: [])
        case .perl:
            return Spec(key: "perl", languageId: "perl", candidates: [["perlnavigator"]])
        case .sql:
            return Spec(key: "sql", languageId: "sql", candidates: [["sqls"], ["sql-language-server", "up", "--method", "stdio"]])
        default:
            return nil
        }
    }

    /// The argv to launch, executable made absolute — or nil when no
    /// candidate is installed. Results are cached per spec key.
    static func resolve(_ spec: Spec) -> [String]? {
        if let cached = resolved[spec.key] { return cached }
        var found: [String]?
        for candidate in spec.candidates {
            guard let name = candidate.first else { continue }
            if let path = executable(named: name) {
                found = [path] + candidate.dropFirst()
                break
            }
        }
        resolved[spec.key] = found
        return found
    }
    private static var resolved: [String: [String]?] = [:]

    private static func executable(named name: String) -> String? {
        if name.hasPrefix("/") {
            return FileManager.default.isExecutableFile(atPath: name) ? name : nil
        }
        for dir in searchPath where FileManager.default.isExecutableFile(atPath: dir + "/" + name) {
            return dir + "/" + name
        }
        return nil
    }

    /// The login shell's PATH (once), then the app's own, then the usual
    /// tool bins in case the shell probe failed. Order preserved, deduped.
    private static let searchPath: [String] = {
        var dirs: [String] = []
        let probe = Process()
        probe.executableURL = URL(fileURLWithPath: "/bin/zsh")
        probe.arguments = ["-lic", "echo $PATH"]
        let pipe = Pipe()
        probe.standardOutput = pipe
        probe.standardError = FileHandle.nullDevice
        if (try? probe.run()) != nil {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            probe.waitUntilExit()
            if let out = String(data: data, encoding: .utf8) {
                dirs += out.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ":").map(String.init)
            }
        }
        dirs += (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        let home = NSHomeDirectory()
        dirs += [
            "/opt/homebrew/bin", "/usr/local/bin", "\(home)/.local/bin", "\(home)/.cargo/bin",
            "\(home)/go/bin", "\(home)/.bun/bin", "\(home)/.deno/bin", "\(home)/.volta/bin",
            "\(home)/.npm-global/bin", "/usr/bin",
        ]
        var seen = Set<String>()
        return dirs.filter { !$0.isEmpty && seen.insert($0).inserted }
    }()
}

/// One language server for one repo root (M2.5, TECHNICAL_PLAN §3.3 —
/// go-to-definition and diagnostics, nothing else). JSON-RPC over stdio;
/// the binary comes from `LSPServers`. The client is deliberately dynamic
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
    let languageId: String
    /// Fired on the main queue whenever the server publishes diagnostics.
    var onDiagnostics: ((_ path: String, _ diagnostics: [LSPDiagnostic]) -> Void)?

    init?(root: String, command: [String], languageId: String) {
        self.root = root
        self.languageId = languageId
        guard let executable = command.first else { return nil }
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = Array(command.dropFirst())
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
                    "uri": Self.uri(path), "languageId": self.languageId, "version": 1, "text": text,
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

/// One server per (repo root, language), spawned on first use, reused
/// across sessions, torn down at quit. A language with no installed server
/// simply gets no client and the editor stays plain.
enum LSPRegistry {
    private static var clients: [String: LSPClient] = [:]

    static func client(for root: String, language: CodeLanguage) -> LSPClient? {
        guard let spec = LSPServers.spec(for: language) else { return nil }
        let key = "\(root)|\(spec.key)"
        if let existing = clients[key] { return existing }
        guard let command = LSPServers.resolve(spec),
              let client = LSPClient(root: root, command: command, languageId: spec.languageId) else { return nil }
        clients[key] = client
        return client
    }

    static func terminateAll() {
        for client in clients.values { client.shutdown() }
        clients.removeAll()
    }
}
