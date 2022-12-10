// swift-tools-version: 5.6

import PackageDescription
import class Foundation.ProcessInfo

var dependencies: [Target.Dependency] = {
    var dependencies: [Target.Dependency] = [
        .product(name: "OrderedCollections", package: "swift-collections")
    ]

    if ProcessInfo.processInfo.environment["ASYNCOBJECTS_ENABLE_LOGGING_LEVEL"] != nil {
        dependencies.append(.product(name: "Logging", package: "swift-log"))
    }

    return dependencies
}()

var settings: [SwiftSetting] = {
    var settings: [SwiftSetting] = []

    if ProcessInfo.processInfo.environment["SWIFTCI_CONCURRENCY_CHECKS"] != nil {
        settings.append(
            .unsafeFlags([
                "-Xfrontend",
                "-warn-concurrency",
                "-enable-actor-data-race-checks",
                "-require-explicit-sendable",
            ])
        )
    }

    if ProcessInfo.processInfo.environment["SWIFTCI_WARNINGS_AS_ERRORS"] != nil {
        settings.append(.unsafeFlags(["-warnings-as-errors"]))
    }

    if ProcessInfo.processInfo.environment["ASYNCOBJECTS_USE_CHECKEDCONTINUATION"] != nil {
        settings.append(.define("ASYNCOBJECTS_USE_CHECKEDCONTINUATION"))
    }

    if let level = ProcessInfo.processInfo.environment["ASYNCOBJECTS_ENABLE_LOGGING_LEVEL"] {
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
        .library(name: "AsyncObjects", targets: ["AsyncObjects"]),
    ],
    dependencies: [
        .package(url: "\(appleGitHub)/swift-collections.git", from: "1.0.0"),
        .package(url: "\(appleGitHub)/swift-docc-plugin", from: "1.0.0"),
        .package(url: "\(appleGitHub)/swift-format", from: "0.50700.0"),
        .package(url: "\(appleGitHub)/swift-log.git", from: "1.0.0"),
    ],
    targets: [
        .target(name: "AsyncObjects", dependencies: dependencies, swiftSettings: settings),
        .testTarget(name: "AsyncObjectsTests", dependencies: ["AsyncObjects"]),
    ]
)
