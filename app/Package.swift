// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "EnetDiag",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "EnetCore"),
        .executableTarget(name: "EnetDiag", dependencies: ["EnetCore"]),
        .testTarget(name: "EnetCoreTests", dependencies: ["EnetCore"]),
    ]
)
