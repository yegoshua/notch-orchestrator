// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NotchOrchestrator",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "SessionCore"),
        .target(name: "ClaudeConnection"),
        .executableTarget(name: "NotchApp", dependencies: ["SessionCore", "ClaudeConnection"]),
        .testTarget(name: "SessionCoreTests", dependencies: ["SessionCore"]),
        .testTarget(name: "ClaudeConnectionTests", dependencies: ["ClaudeConnection"]),
    ],
    swiftLanguageModes: [.v5]
)
