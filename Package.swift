// swift-tools-version: 5.5

import PackageDescription

let package = Package(
    name: "AsyncObject",
    platforms: [
        .macOS(.v10_15),
        .iOS(.v13),
        .tvOS(.v13),
        .watchOS(.v6),
    ],
    products: [
        .library(
            name: "AsyncObject",
            targets: ["AsyncObject"]
        ),
    ],
    dependencies: [
    ],
    targets: [
        .target(
            name: "AsyncObject",
            dependencies: []
        ),
        .testTarget(
            name: "AsyncObjectTests",
            dependencies: ["AsyncObject"]
        ),
    ]
)
