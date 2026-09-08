// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "UsageBar",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "UsageBar", targets: ["UsageBar"])],
    targets: [
        .executableTarget(name: "UsageBar"),
        .testTarget(name: "UsageBarTests", dependencies: ["UsageBar"])
    ]
)
