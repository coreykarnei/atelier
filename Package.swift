// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Atelier",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.13.0")
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
            dependencies: ["SwiftTerm", "AtelierIPC"],
            path: "Sources/Atelier",
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
    ]
)
