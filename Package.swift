// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NotchOrchestrator",
    platforms: [.macOS(.v14)],
    dependencies: [
        // Self-update. The only dependency: replacing a running app safely is not worth rewriting.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.0"),
    ],
    targets: [
        .target(name: "SessionCore"),
        .target(name: "ClaudeConnection"),
        .executableTarget(
            name: "NotchApp",
            dependencies: ["SessionCore", "ClaudeConnection", .product(name: "Sparkle", package: "Sparkle")],
            // Where the app bundle keeps the Sparkle framework.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .testTarget(name: "SessionCoreTests", dependencies: ["SessionCore"]),
        .testTarget(name: "ClaudeConnectionTests", dependencies: ["ClaudeConnection"]),
    ],
    swiftLanguageModes: [.v5]
)
