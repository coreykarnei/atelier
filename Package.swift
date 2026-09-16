// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Atelier",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        // Vendored copy of SwiftTerm 1.13.0 with Atelier's terminal-side
        // patches (wheel routing, open view hooks) — see Vendor/SwiftTerm/ATELIER.md.
        .package(path: "Vendor/SwiftTerm"),
        // The M2 editor base (TECHNICAL_PLAN §3.3): TextKit-2 source editor
        // with incremental tree-sitter highlighting and multi-cursor support.
        // Vendored CodeEditSourceEditor 0.15.2 with Atelier's patches — see
        // Vendor/CodeEditSourceEditor/ATELIER.md.
        .package(path: "Vendor/CodeEditSourceEditor"),
        .package(path: "Vendor/CodeEditLanguages"),
        // Local override (by package identity) of CodeEditSourceEditor's
        // CodeEditSymbols dependency — see Vendor/CodeEditSymbols/Package.swift.
        .package(path: "Vendor/CodeEditSymbols"),
        // Local override of CodeEditTextView 0.12.1 carrying Atelier's
        // horizontal-scroll fix — see Vendor/CodeEditTextView/ATELIER.md.
        .package(path: "Vendor/CodeEditTextView"),
        // Already transitive through CodeEditLanguages; named here so the
        // highlight-query harness can drive tree-sitter directly.
        .package(url: "https://github.com/ChimeHQ/SwiftTreeSitter.git", from: "0.25.0"),
    ],
    targets: [
        // Shared IPC contract: socket path + the message both ends encode/decode.
        .target(
            name: "AtelierIPC",
            path: "Sources/AtelierIPC",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // The app.
        .executableTarget(
            name: "Atelier",
            dependencies: [
                "SwiftTerm",
                "AtelierIPC",
                .product(name: "CodeEditSourceEditor", package: "CodeEditSourceEditor"),
                .product(name: "CodeEditLanguages", package: "CodeEditLanguages"),
            ],
            path: "Sources/Atelier",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Dev harness: compile a language's highlight query against the
        // bundled grammar and print every capture for a file — the way to
        // test query work without launching the app (Scripts/hlcheck/README.md).
        .executableTarget(
            name: "atelier-hlcheck",
            dependencies: [
                .product(name: "CodeEditLanguages", package: "CodeEditLanguages"),
                .product(name: "CodeEditSourceEditor", package: "CodeEditSourceEditor"),
                .product(name: "SwiftTreeSitter", package: "SwiftTreeSitter"),
            ],
            path: "Sources/atelier-hlcheck",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Tiny CLI invoked by Claude Code's Stop/Notification hooks. Writes a
        // message to the app's unix socket, which posts the native notification.
        .executableTarget(
            name: "atelier-notify",
            dependencies: ["AtelierIPC"],
            path: "Sources/atelier-notify",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // The workspace CLI (`atelier`, `atelier -b`, `atelier -rm`) — the `ide`
        // script's successor. Same socket, command messages instead of notify.
        // (Named atelier-cli because target names clash case-insensitively with
        // the app module; the bundle ships it as plain `atelier`.)
        .executableTarget(
            name: "atelier-cli",
            dependencies: ["AtelierIPC"],
            path: "Sources/atelier-cli",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
