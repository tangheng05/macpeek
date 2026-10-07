// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "macpeek",
    platforms: [.macOS(.v26)],
    targets: [
        .target(name: "MacpeekCore"),
        .executableTarget(name: "macpeek", dependencies: ["MacpeekCore"]),
        .executableTarget(name: "MacpeekApp", dependencies: ["MacpeekCore"]),
        .testTarget(name: "MacpeekCoreTests", dependencies: ["MacpeekCore"]),
    ]
)
