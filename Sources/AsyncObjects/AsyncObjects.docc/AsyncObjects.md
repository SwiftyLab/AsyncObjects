# ``AsyncObjects``

Several synchronization primitives and task synchronization mechanisms introduced to aid in modern swift concurrency.

## Overview

While Swift's modern structured concurrency provides safer way of managing concurrency, it lacks many synchronization and task management features in its current state. **AsyncObjects** aims to close the functionality gap by providing following features:

- Easier task cancellation with ``CancellationSource``.
- Introducing traditional synchronization primitives that work in non-blocking way with ``AsyncSemaphore``, ``AsyncEvent`` and ``AsyncCountdownEvent``.
- Bridging with Grand Central Dispatch and allowing usage of GCD specific patterns with ``TaskOperation`` and ``TaskQueue``.
- Transferring data between multiple task boundaries with ``Future``.

## Requirements

| Platform | Minimum Swift Version | Installation | Status |
| --- | --- | --- | --- |
| iOS 13.0+ / macOS 10.15+ / tvOS 13.0+ / watchOS 6.0+ | 5.6 | CocoaPods, Carthage, Swift Package Manager, Manual | Fully Tested |
| Linux | 5.6 | Swift Package Manager | Fully Tested |
| Windows | 5.6 | Swift Package Manager | Fully Tested |

## Installation

### CocoaPods

[CocoaPods](https://cocoapods.org) is a dependency manager for Cocoa projects. For usage and installation instructions, visit their website. To integrate `AsyncObjects` into your Xcode project using CocoaPods, specify it in your `Podfile`:

```ruby
pod 'AsyncObjects'
```

Optionally, you can also use the pre-built XCFramework from the GitHub releases page by replacing `{version}` with the required version you want to use:

```ruby
pod 'AsyncObjects', :http => 'https://github.com/SwiftyLab/AsyncObjects/releases/download/v{version}/AsyncObjects-{version}.xcframework.zip'
```

### Carthage

[Carthage](https://github.com/Carthage/Carthage) is a decentralized dependency manager that builds your dependencies and provides you with binary frameworks. To integrate `AsyncObjects` into your Xcode project using Carthage, specify it in your `Cartfile`:

```ogdl
github "SwiftyLab/AsyncObjects"
```

### Swift Package Manager

The [Swift Package Manager](https://swift.org/package-manager/) is a tool for automating the distribution of Swift code and is integrated into the `swift` compiler.

Once you have your Swift package set up, adding `AsyncObjects` as a dependency is as easy as adding it to the `dependencies` value of your `Package.swift`.

```swift
.package(url: "https://github.com/SwiftyLab/AsyncObjects.git", from: "1.0.0"),
```

Optionally, you can also use the pre-built XCFramework from the GitHub releases page by replacing `{version}` and `{checksum}` with the required version and checksum of artifact you want to use, but in this case dependencies must be added separately:

```swift
.binaryTarget(name: "AsyncObjects", url: "https://github.com/SwiftyLab/AsyncObjects/releases/download/v{version}/AsyncObjects-{version}.xcframework.zip", checksum: "{checksum}"),
```

### Manually

If you prefer not to use any of the aforementioned dependency managers, you can integrate `AsyncObjects` into your project manually.

#### Git Submodule

- Open up Terminal, `cd` into your top-level project directory, and run the following command "if" your project is not initialized as a git repository:

  ```bash
  $ git init
  ```

- Add `AsyncObjects` as a git [submodule](https://git-scm.com/docs/git-submodule) by running the following command:

  ```bash
  $ git submodule add https://github.com/SwiftyLab/AsyncObjects.git
  ```

- Open the new `AsyncObjects` folder, and drag the `AsyncObjects.xcodeproj` into the Project Navigator of your application's Xcode project or existing workspace.

    > It should appear nested underneath your application's blue project icon. Whether it is above or below all the other Xcode groups does not matter.

- Select the `AsyncObjects.xcodeproj` in the Project Navigator and verify the deployment target satisfies that of your application target (should be less or equal).
- Next, select your application project in the Project Navigator (blue project icon) to navigate to the target configuration window and select the application target under the `Targets` heading in the sidebar.
- In the tab bar at the top of that window, open the "General" panel.
- Click on the `+` button under the `Frameworks and Libraries` section.
- You will see `AsyncObjects.xcodeproj` folder with `AsyncObjects.framework` nested inside.
- Select the `AsyncObjects.framework` and that's it!

  > The `AsyncObjects.framework` is automagically added as a target dependency, linked framework and embedded framework in build phase which is all you need to build on the simulator and a device.

#### XCFramework

You can also directly download the pre-built artifact from the GitHub releases page:

- Download the artifact from the GitHub releases page of the format `AsyncObjects-{version}.xcframework.zip` where `{version}` is the version you want to use.
- Extract the XCFramework from the archive, and drag the `AsyncObjects.xcframework` into the Project Navigator of your application's target folder in your Xcode project.
- Select `Copy items if needed` and that's it!

  > The `AsyncObjects.xcframework` is automagically added in the embedded `Frameworks and Libraries` section, an in turn the linked framework in build phase. The dependencies aren't provided with the XCFramework and must be added separately.

## Topics

### Synchronization Primitives

- ``AsyncSemaphore``
- ``AsyncEvent``
- ``AsyncCountdownEvent``

### Tasks Synchronization

- ``CancellationSource``
- ``TaskOperation``
- ``TaskQueue``

### Data Transfer

- ``Future``
