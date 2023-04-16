// swift-tools-version: 5.6

import PackageDescription
import Foundation

let packages: [Package.Dependency] = {
    var dependencies: [Package.Dependency] = [
        .package(url: "https://github.com/apple/swift-collections.git", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-async-algorithms", from: "0.1.0"),
    ]

    if Context.environment["ASYNCOBJECTS_ENABLE_DEV"] != nil {
        dependencies.append(contentsOf: [
            .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.0.0"),
            .package(url: "https://github.com/apple/swift-format", from: "0.50700.0"),
        ])
    }

    if Context.environment["ASYNCOBJECTS_ENABLE_LOGGING_LEVEL"] != nil {
        dependencies.append(
            .package(url: "https://github.com/apple/swift-log.git", from: "1.0.0")
        )
    }

    return dependencies
}()

let dependencies: [Target.Dependency] = {
    var dependencies: [Target.Dependency] = [
        .product(name: "OrderedCollections", package: "swift-collections"),
        .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
    ]

    if Context.environment["ASYNCOBJECTS_ENABLE_LOGGING_LEVEL"] != nil {
        dependencies.append(.product(name: "Logging", package: "swift-log"))
    }

    return dependencies
}()

let settings: [SwiftSetting] = {
    var settings: [SwiftSetting] = []

    if Context.environment["SWIFTCI_CONCURRENCY_CHECKS"] != nil {
        settings.append(
            .unsafeFlags([
                "-Xfrontend",
                "-warn-concurrency",
                "-enable-actor-data-race-checks",
                "-require-explicit-sendable",
                "-strict-concurrency=complete"
            ])
        )
    }

    if Context.environment["SWIFTCI_WARNINGS_AS_ERRORS"] != nil {
        settings.append(.unsafeFlags(["-warnings-as-errors"]))
    }

    if Context.environment["ASYNCOBJECTS_USE_CHECKEDCONTINUATION"] != nil {
        settings.append(.define("ASYNCOBJECTS_USE_CHECKEDCONTINUATION"))
    }

    if let level = Context.environment["ASYNCOBJECTS_ENABLE_LOGGING_LEVEL"] {
        if level.caseInsensitiveCompare("TRACE") == .orderedSame {
            settings.append(.define("ASYNCOBJECTS_ENABLE_LOGGING_LEVEL_TRACE"))
        } else if level.caseInsensitiveCompare("DEBUG") == .orderedSame {
            settings.append(.define("ASYNCOBJECTS_ENABLE_LOGGING_LEVEL_DEBUG"))
        } else {
            settings.append(.define("ASYNCOBJECTS_ENABLE_LOGGING_LEVEL_INFO"))
        }
    }

    return settings
}()

let package = Package(
    name: "AsyncObjects",
    platforms: [
        .macOS(.v10_15),
        .iOS(.v13),
        .tvOS(.v13),
        .watchOS(.v6),
    ],
    products: [
        .library(name: "AsyncObjects", targets: ["AsyncObjects"]),
    ],
    dependencies: packages,
    targets: [
        .target(name: "AsyncObjects", dependencies: dependencies, swiftSettings: settings),
        .testTarget(name: "AsyncObjectsTests", dependencies: ["AsyncObjects"]),
    ]
)
