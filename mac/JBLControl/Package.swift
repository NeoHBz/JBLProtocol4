// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "JBLControl",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "JBLKit"),
        .executableTarget(name: "JBLControl", dependencies: ["JBLKit"]),
        .testTarget(name: "JBLKitTests", dependencies: ["JBLKit"]),
    ]
)
