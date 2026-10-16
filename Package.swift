// swift-tools-version:6.0
import PackageDescription
import Foundation

// Sources/XiaokeBar/Private 不在公开仓库里（iPhone 配对、中转、远程终端、付费解锁）。
// 有这个文件夹时编进去并打开 XIAOKE_PRIVATE；没有时编出纯 Mac 的开源版。
let hasPrivate = FileManager.default.fileExists(atPath: Context.packageDirectory + "/Sources/XiaokeBar/Private")
let appSettings: [SwiftSetting] = [.swiftLanguageMode(.v5)] + (hasPrivate ? [.define("XIAOKE_PRIVATE")] : [])

let package = Package(
    name: "XiaokeBar",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "XiaokeBar",
            path: "Sources/XiaokeBar",
            swiftSettings: appSettings
        ),
        .testTarget(
            name: "XiaokeBarTests",
            dependencies: ["XiaokeBar"],
            path: "Tests/XiaokeBarTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
