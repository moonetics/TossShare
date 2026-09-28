// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "TossShare",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "TossShareApp",
            targets: ["TossShareApp"]
        ),
        .library(
            name: "TossShareCore",
            targets: ["TossShareCore"]
        ),
        .library(
            name: "TossShareUI",
            targets: ["TossShareUI"]
        ),
        .library(
            name: "TossShareExtension",
            targets: ["TossShareExtension"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.28.2")
    ],
    targets: [
        .target(
            name: "TossShareCore",
            dependencies: [
                .product(name: "SwiftProtobuf", package: "swift-protobuf")
            ],
            path: "Sources/TossShareCore",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .target(
            name: "TossShareUI",
            dependencies: [
                "TossShareCore"
            ],
            path: "Sources/TossShareUI",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .executableTarget(
            name: "TossShareApp",
            dependencies: [
                "TossShareCore",
                "TossShareUI"
            ],
            path: "Sources/TossShareApp",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .target(
            name: "TossShareExtension",
            dependencies: [
                "TossShareCore"
            ],
            path: "Sources/TossShareExtension",
            exclude: [
                "Info.plist"
            ],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "TossShareCoreTests",
            dependencies: [
                "TossShareCore",
                "TossShareUI"
            ],
            path: "Tests/TossShareCoreTests",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        )
    ]
)
