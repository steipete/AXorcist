import ApplicationServices
import Foundation
import os

// MARK: - Element timeout helpers

extension Element {
    /// Retrieve the main menu element if available.
    @MainActor
    public func menuBar() -> Element? {
        guard let menuBar: AXUIElement = attribute(Attribute<AXUIElement>.mainMenu) else { return nil }
        return Element(menuBar)
    }

    /// Set a messaging timeout for this element to prevent hangs.
    @MainActor
    public func setMessagingTimeout(_ timeout: Float) {
        let error = AXUIElementSetMessagingTimeout(self.underlyingElement, timeout)
        if error != .success {
            Logger(subsystem: "boo.peekaboo.axorcist", category: "AXTimeout")
                .warning("Failed to set messaging timeout: \(error.rawValue)")
        }
    }

    /// Get windows with timeout protection.
    @MainActor
    public func windowsWithTimeout(timeout: Float = 2.0) -> [Element]? {
        self.setMessagingTimeout(timeout)
        let windows = self.windows()
        self.setMessagingTimeout(0)
        return windows
    }

    /// Get menu bar with timeout protection.
    @MainActor
    public func menuBarWithTimeout(timeout: Float = 2.0) -> Element? {
        self.setMessagingTimeout(timeout)
        let menuBar = self.menuBar()
        self.setMessagingTimeout(0)
        return menuBar
    }
}

/// Global timeout configuration for all AX operations.
public enum AXTimeoutConfiguration {
    /// Set the global messaging timeout for all AX operations.
    @MainActor
    public static func setGlobalTimeout(_ timeout: Float) {
        let systemWide = AXUIElementCreateSystemWide()
        let error = AXUIElementSetMessagingTimeout(systemWide, timeout)
        let logger = Logger(subsystem: "boo.peekaboo.axorcist", category: "AXTimeout")
        if error != .success {
            logger.warning("Failed to set global AX timeout: \(error.rawValue)")
        } else {
            logger.info("Set global AX timeout to \(timeout, format: .fixed(precision: 2)) seconds")
        }
    }
}

/// Wrapper for AX operations with automatic retry on timeout.
public struct AXTimeoutWrapper {
    private let maxRetries: Int
    private let retryDelay: TimeInterval

    public init(maxRetries: Int = 3, retryDelay: TimeInterval = 0.5) {
        self.maxRetries = maxRetries
        self.retryDelay = retryDelay
    }

    /// Execute an AX operation with timeout protection and retry logic.
    @MainActor
    public func execute<T>(_ operation: () throws -> T?) async throws -> T? {
        var lastError: (any Error)?

        for attempt in 0..<self.maxRetries {
            do {
                if let result = try operation() {
                    return result
                }
            } catch {
                lastError = error
                Logger(subsystem: "boo.peekaboo.axorcist", category: "AXTimeout")
                    .debug("AX operation failed (attempt \(attempt + 1)/\(self.maxRetries)): \(String(describing: error))")

                if attempt < self.maxRetries - 1 {
                    try await Task.sleep(nanoseconds: UInt64(self.retryDelay * 1_000_000_000))
                }
            }
        }

        if let error = lastError {
            throw error
        }
        return nil
    }
}

public enum AXTimeoutHelper {
    /// Async timeout helper reused by downstreams (e.g., ScreenCaptureService)
    /// to keep timeout logic in one place.
    @MainActor
    public static func withTimeout<T: Sendable>(
        seconds: TimeInterval,
        operation: @escaping @Sendable () async throws -> T) async throws -> T
    {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }

            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw AXTimeoutError.operationTimedOut(duration: seconds)
            }

            guard let result = try await group.next() else {
                throw AXTimeoutError.operationTimedOut(duration: seconds)
            }

            group.cancelAll()
            return result
        }
    }
}

public enum AXTimeoutError: Error, Sendable, CustomStringConvertible {
    case operationTimedOut(duration: TimeInterval)

    public var description: String {
        switch self {
        case let .operationTimedOut(duration):
            return "Operation timed out after \(duration)s"
        }
    }
}
