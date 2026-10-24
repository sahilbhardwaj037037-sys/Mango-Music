// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LocalMusic",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "LocalMusic", targets: ["LocalMusic"])],
    targets: [
        .executableTarget(name: "LocalMusic", path: "LocalMusic", exclude: ["Assets.xcassets", "App/Info.plist"]),
        .testTarget(name: "LocalMusicTests", dependencies: ["LocalMusic"], path: "Tests/LocalMusicTests")
    ]
)
