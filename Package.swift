// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MangoMusic",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "MangoMusic", targets: ["MangoMusic"])],
    targets: [
        .executableTarget(name: "MangoMusic", path: "MangoMusic", exclude: ["Assets.xcassets", "App/Info.plist"], linkerSettings: [.linkedLibrary("sqlite3")]),
        .testTarget(name: "MangoMusicTests", dependencies: ["MangoMusic"], path: "Tests/MangoMusicTests")
    ]
)
