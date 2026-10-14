// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "XiaokeBar",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "XiaokeBar",
            path: "Sources/XiaokeBar",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "XiaokeBarTests",
            dependencies: ["XiaokeBar"],
            path: "Tests/XiaokeBarTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
