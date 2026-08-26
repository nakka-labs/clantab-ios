// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SquareKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "SquareKit",
            targets: ["SquareKit"]
        ),
    ],
    targets: [
        .target(
            name: "SquareKit",
            dependencies: []
        ),
        .testTarget(
            name: "SquareKitTests",
            dependencies: ["SquareKit"]
        ),
    ]
)
