// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MiniDock",
    defaultLocalization: "zh-Hans",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.7.0"),
    ],
    targets: [
        .executableTarget(
            name: "MiniDock",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
            ],
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
