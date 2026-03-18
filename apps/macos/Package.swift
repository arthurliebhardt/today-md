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
    targets: [
        .executableTarget(
            name: "TodayMdApp",
            path: "today-md",
            exclude: [
                "Info.plist",
                "today-md.entitlements"
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
