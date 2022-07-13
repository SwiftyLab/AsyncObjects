// swift-tools-version: 5.6

import PackageDescription

let package = Package(
    name: "AsyncObjects",
    platforms: [
        .macOS(.v10_15),
        .iOS(.v13),
        .tvOS(.v13),
        .watchOS(.v6),
    ],
    products: [
        .library(
            name: "AsyncObjects",
            targets: ["AsyncObjects"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-collections.git", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-format", from: "0.50600.1"),
    ],
    targets: [
        .target(
            name: "AsyncObjects",
            dependencies: [
                .product(name: "OrderedCollections", package: "swift-collections"),
            ]
        ),
        .testTarget(
            name: "AsyncObjectsTests",
            dependencies: ["AsyncObjects"]
        ),
    ]
)
