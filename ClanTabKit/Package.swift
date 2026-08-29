// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ClanTabKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "ClanTabKit",
            targets: ["ClanTabKit"]
        ),
    ],
    targets: [
        .target(
            name: "ClanTabKit",
            dependencies: []
        ),
        .testTarget(
            name: "ClanTabKitTests",
            dependencies: ["ClanTabKit"]
        ),
    ]
)
