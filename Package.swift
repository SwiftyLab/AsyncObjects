// swift-tools-version: 5.6

import PackageDescription
import class Foundation.ProcessInfo

let appleGitHub = "https://github.com/apple"
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
        .package(url: "\(appleGitHub)/swift-collections.git", from: "1.0.0"),
        .package(url: "\(appleGitHub)/swift-docc-plugin", from: "1.0.0"),
        .package(url: "\(appleGitHub)/swift-format", from: "0.50600.1"),
    ],
    targets: [
        .target(
            name: "AsyncObjects",
            dependencies: [
                .product(
                    name: "OrderedCollections",
                    package: "swift-collections"
                ),
            ],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "AsyncObjectsTests",
            dependencies: ["AsyncObjects"],
            swiftSettings: testingSwiftSettings
        ),
    ]
)

var swiftSettings: [SwiftSetting] {
    var swiftSettings: [SwiftSetting] = []

    if ProcessInfo.processInfo.environment[
        "SWIFTCI_CONCURRENCY_CHECKS"
    ] != nil {
        swiftSettings.append(
            .unsafeFlags([
                "-Xfrontend",
                "-warn-concurrency",
                "-enable-actor-data-race-checks",
                "-require-explicit-sendable",
            ])
        )
    }

    if ProcessInfo.processInfo.environment[
        "SWIFTCI_WARNINGS_AS_ERRORS"
    ] != nil {
        swiftSettings.append(
            .unsafeFlags([
                "-warnings-as-errors"
            ])
        )
    }

    if ProcessInfo.processInfo.environment[
        "ASYNCOBJECTS_USE_CHECKEDCONTINUATION"
    ] != nil {
        swiftSettings.append(
            .define("ASYNCOBJECTS_USE_CHECKEDCONTINUATION")
        )
    }

    return swiftSettings
}

var testingSwiftSettings: [SwiftSetting] {
    var swiftSettings: [SwiftSetting] = []

    if ProcessInfo.processInfo.environment[
        "SWIFTCI_CONCURRENCY_CHECKS"
    ] != nil {
        swiftSettings.append(
            .unsafeFlags([
                "-Xfrontend",
                "-warn-concurrency",
                "-enable-actor-data-race-checks",
                "-require-explicit-sendable",
            ])
        )
    }

    return swiftSettings
}
