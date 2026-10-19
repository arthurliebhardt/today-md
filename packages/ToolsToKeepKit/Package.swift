// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ToolsToKeepKit",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [
        .library(name: "ToolsToKeepKit", targets: ["ToolsToKeepKit"]),
    ],
    targets: [
        .target(name: "ToolsToKeepKit"),
        .testTarget(name: "ToolsToKeepKitTests", dependencies: ["ToolsToKeepKit"]),
    ]
)
