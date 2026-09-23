// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MasterKey",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "MasterKey", targets: ["MasterKey"])],
    targets: [
        .target(name: "BridgeCore"),
        .executableTarget(name: "MasterKey", dependencies: ["BridgeCore"]),
        .executableTarget(name: "BridgeChecks", dependencies: ["BridgeCore"], path: "Tests/BridgeCoreTests")
    ]
)
