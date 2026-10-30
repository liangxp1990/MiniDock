// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MiniDock",
    defaultLocalization: "zh-Hans",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "MiniDock",
            path: "Sources/MiniDock",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "MiniDockTests",
            dependencies: ["MiniDock"],
            path: "Tests/MiniDockTests"
        ),
    ]
)
