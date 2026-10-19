// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "today-md",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "today-md",
            targets: ["TodayMdApp"]
        )
    ],
    dependencies: [
        // Shared unlock logic (license keys, activation) from the toolstokeep monorepo.
        .package(path: "../../../../packages/ToolsToKeepKit")
    ],
    targets: [
        .executableTarget(
            name: "TodayMdApp",
            dependencies: [
                .product(name: "ToolsToKeepKit", package: "ToolsToKeepKit")
            ],
            path: "today-md",
            exclude: [
                "Info.plist",
                "PrivacyInfo.xcprivacy",
                "today-md.entitlements",
                "today-md-direct.entitlements"
            ],
            resources: [
                .process("Assets.xcassets")
            ],
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .testTarget(
            name: "TodayMdAppTests",
            dependencies: ["TodayMdApp"],
            path: "Tests/TodayMdAppTests"
        )
    ]
)
