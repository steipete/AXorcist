import Foundation
import os

/// Immutable policy for one accessibility-tree traversal request.
public nonisolated struct AXTraversalOptions: Sendable, Equatable {
    /// The library defaults used when a caller does not provide an explicit policy.
    public nonisolated static let standard = AXTraversalOptions(
        timeout: 30,
        scanAll: false,
        stopAtFirstMatch: true)

    public let timeout: TimeInterval
    public let scanAll: Bool
    public let stopAtFirstMatch: Bool

    public nonisolated init(
        timeout: TimeInterval = AXTraversalOptions.standard.timeout,
        scanAll: Bool = AXTraversalOptions.standard.scanAll,
        stopAtFirstMatch: Bool = AXTraversalOptions.standard.stopAtFirstMatch)
    {
        self.timeout = timeout
        self.scanAll = scanAll
        self.stopAtFirstMatch = stopAtFirstMatch
    }

    nonisolated static func snapshotDefaults() -> AXTraversalOptions {
        axTraversalDefaultsStore.withLock { $0 }
    }

    nonisolated static func replaceDefaults(_ options: AXTraversalOptions) {
        axTraversalDefaultsStore.withLock { $0 = options }
    }
}

private nonisolated let axTraversalDefaultsStore = OSAllocatedUnfairLock(initialState: AXTraversalOptions.standard)

/// Legacy process default. Prefer passing ``AXTraversalOptions`` to each request.
@available(*, deprecated, message: "Pass AXTraversalOptions to each traversal request instead.")
public nonisolated var axorcTraversalTimeout: TimeInterval {
    get { AXTraversalOptions.snapshotDefaults().timeout }
    set {
        axTraversalDefaultsStore.withLock {
            $0 = AXTraversalOptions(
                timeout: newValue,
                scanAll: $0.scanAll,
                stopAtFirstMatch: $0.stopAtFirstMatch)
        }
    }
}

/// Legacy process default. Prefer passing ``AXTraversalOptions`` to each request.
@available(*, deprecated, message: "Pass AXTraversalOptions to each traversal request instead.")
public nonisolated var axorcScanAll: Bool {
    get { AXTraversalOptions.snapshotDefaults().scanAll }
    set {
        axTraversalDefaultsStore.withLock {
            $0 = AXTraversalOptions(
                timeout: $0.timeout,
                scanAll: newValue,
                stopAtFirstMatch: $0.stopAtFirstMatch)
        }
    }
}

/// Legacy process default. Prefer passing ``AXTraversalOptions`` to each request.
@available(*, deprecated, message: "Pass AXTraversalOptions to each traversal request instead.")
public nonisolated var axorcStopAtFirstMatch: Bool {
    get { AXTraversalOptions.snapshotDefaults().stopAtFirstMatch }
    set {
        axTraversalDefaultsStore.withLock {
            $0 = AXTraversalOptions(
                timeout: $0.timeout,
                scanAll: $0.scanAll,
                stopAtFirstMatch: newValue)
        }
    }
}
