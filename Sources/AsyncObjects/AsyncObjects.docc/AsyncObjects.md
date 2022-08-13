# ``AsyncObjects``

Several synchronization primitives and task synchronization mechanisms introduced to aid in modern swift concurrency.

## Overview

While Swift's modern structured concurrency provides safer way of managing concurrency, it lacks many synchronization and task management features in its current state. **AsyncObjects** aims to close the functionality gap by providing following features:

- Easier task cancellation with ``CancellationSource``.
- Introducing traditional synchronization primitives that work in non-blocking way with ``AsyncSemaphore``, ``AsyncEvent`` and ``AsyncCountdownEvent``.
- Bridging with Grand Central Dispatch and allowing usage of GCD specific patterns with ``TaskOperation`` and ``TaskQueue``.
- Transferring data between multiple task boundaries with ``Future``.

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
