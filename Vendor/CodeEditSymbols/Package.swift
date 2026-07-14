// swift-tools-version: 5.5

// Vendored from https://github.com/CodeEditApp/CodeEditSymbols with one fix:
// the upstream manifest never declares Symbols.xcassets as a resource, so
// `Bundle.module` is only synthesized under Xcode's implicit asset handling —
// pure `swift build` (this repo's build) fails. Declaring the resource
// restores Bundle.module for the SwiftPM CLI. The test target (and its
// SnapshotTesting dependency) is dropped. SwiftPM resolves this local copy
// over the remote by package identity, satisfying CodeEditSourceEditor's
// dependency.

import PackageDescription

let package = Package(
    name: "CodeEditSymbols",
    platforms: [
        .macOS(.v12),
    ],
    products: [
        .library(
            name: "CodeEditSymbols",
            targets: ["CodeEditSymbols"]),
    ],
    targets: [
        .target(
            name: "CodeEditSymbols",
            dependencies: [],
            resources: [.process("Symbols.xcassets")]
        ),
    ]
)
