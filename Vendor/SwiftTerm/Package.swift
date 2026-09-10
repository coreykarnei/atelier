// swift-tools-version:5.9
import PackageDescription

// Atelier's vendored SwiftTerm — the library target only. See ATELIER.md for
// the upstream revision and the list of local patches.
let package = Package(
    name: "SwiftTerm",
    platforms: [.macOS(.v13)],
    products: [.library(name: "SwiftTerm", targets: ["SwiftTerm"])],
    targets: [
        .target(
            name: "SwiftTerm",
            path: "Sources/SwiftTerm",
            exclude: ["Mac/README.md"],
            resources: [.process("Apple/Metal/Shaders.metal")]
        ),
    ],
    swiftLanguageVersions: [.v5]
)
