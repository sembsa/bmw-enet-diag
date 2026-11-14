// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "EnetDiag",
    platforms: [.macOS(.v14)],
    targets: [.executableTarget(name: "EnetDiag")]
)
