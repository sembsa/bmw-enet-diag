// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "EnetDiag",
    platforms: [.macOS(.v26)],
    targets: [
        .target(name: "EnetCore"),
        .executableTarget(name: "EnetDiag", dependencies: ["EnetCore"]),
        .testTarget(name: "EnetCoreTests", dependencies: ["EnetCore"]),
    ],
    swiftLanguageModes: [.v5]          // shortcut: Swift 6 strict concurrency not yet adopted (MCP's [String: Any] tables, Car's queue)
)
