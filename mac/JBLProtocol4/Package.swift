// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "JBLProtocol4",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "JBLKit"),
        .executableTarget(name: "JBLProtocol4", dependencies: ["JBLKit"]),
        .testTarget(name: "JBLKitTests", dependencies: ["JBLKit"]),
    ]
)
