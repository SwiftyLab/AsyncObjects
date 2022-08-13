# AsyncObjects

[![API Docs](http://img.shields.io/badge/Read_the-docs-2196f3.svg)](https://swiftylab.github.io/AsyncObjects/documentation/asyncobjects/)
[![Swift Package Manager Compatible](https://img.shields.io/github/v/tag/SwiftyLab/AsyncObjects?label=SPM&color=orange)](https://badge.fury.io/gh/SwiftyLab%2FAsyncObjects)
[![Carthage compatible](https://img.shields.io/badge/Carthage-compatible-4BC51D.svg)](https://github.com/Carthage/Carthage)
[![Swift](https://img.shields.io/badge/Swift-5.6+-orange)](https://img.shields.io/badge/Swift-5-DE5D43)
[![Platforms](https://img.shields.io/badge/Platforms-all-sucess)](https://img.shields.io/badge/Platforms-all-sucess)
[![CI/CD](https://github.com/SwiftyLab/AsyncObjects/actions/workflows/main.yml/badge.svg?event=push)](https://github.com/SwiftyLab/AsyncObjects/actions/workflows/main.yml)
[![Maintainability](https://api.codeclimate.com/v1/badges/37183c809818826c1bcf/maintainability)](https://codeclimate.com/github/SwiftyLab/AsyncObjects/maintainability)
[![codecov](https://codecov.io/gh/SwiftyLab/AsyncObjects/branch/main/graph/badge.svg?token=jKxMv5oFeA)](https://codecov.io/gh/SwiftyLab/AsyncObjects)
<!-- [![CocoaPods Compatible](https://img.shields.io/cocoapods/v/AsyncObjects.svg?label=CocoaPods&color=C90005)](https://badge.fury.io/co/AsyncObjects) -->
<!-- [![CodeQL](https://github.com/SwiftyLab/AsyncObjects/actions/workflows/codeql-analysis.yml/badge.svg?event=schedule)](https://github.com/SwiftyLab/AsyncObjects/actions/workflows/codeql-analysis.yml) -->

Several synchronization primitives and task synchronization mechanisms introduced to aid in modern swift concurrency.

## Overview

While Swift's modern structured concurrency provides safer way of managing concurrency, it lacks many synchronization and task management features in its current state. **AsyncObjects** aims to close the functionality gap by providing following features:

- Easier task cancellation with ``CancellationSource``.
- Introducing traditional synchronization primitives that work in non-blocking way with ``AsyncSemaphore``, ``AsyncEvent`` and ``AsyncCountdownEvent``.
- Bridging with Grand Central Dispatch and allowing usage of GCD specific patterns with ``TaskOperation`` and ``TaskQueue``.
- Transferring data between multiple task boundaries with ``Future``.
