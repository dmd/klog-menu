// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "KlogMenu",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "KlogMenuKit", path: "Sources/KlogMenuKit"),
        .executableTarget(name: "KlogMenu", dependencies: ["KlogMenuKit"], path: "Sources/KlogMenu"),
        .testTarget(name: "KlogMenuKitTests", dependencies: ["KlogMenuKit"], path: "Tests/KlogMenuKitTests")
    ]
)
