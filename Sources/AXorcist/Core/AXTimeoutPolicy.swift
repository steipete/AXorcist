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
        _ = self.applyMessagingTimeout(timeout)
    }

    @MainActor
    private func applyMessagingTimeout(_ timeout: Float) -> AXError {
        let error = AXUIElementSetMessagingTimeout(self.underlyingElement, timeout)
        if error != .success {
            Logger(subsystem: "boo.peekaboo.axorcist", category: "AXTimeout")
                .warning("Failed to set messaging timeout: \(error.rawValue)")
        }
        return error
    }

    /// Run one synchronous operation with a checked per-element AX messaging deadline.
    ///
    /// The operation is never called if macOS refuses the deadline. The deadline is
    /// cleared after a dispatched operation, including when the operation throws. A
    /// native failure to clear the deadline is reported instead of returning success.
    @MainActor
    public func withMessagingTimeout<Result>(
        _ timeout: Float,
        operation: (Element) throws -> Result) throws -> Result
    {
        guard AXMessagingTimeoutRegistry.begin(self) else {
            throw AXMessagingTimeoutError.nestedScope
        }
        defer { AXMessagingTimeoutRegistry.end(self) }
        return try AXMessagingTimeoutScope.perform(
            timeout: timeout,
            applyTimeout: self.applyMessagingTimeout,
            operation: { try operation(self) })
    }

    /// Get windows with timeout protection.
    @MainActor
    public func windowsWithTimeout(timeout: Float = 2.0) -> [Element]? {
        try? self.withMessagingTimeout(timeout) { $0.windows() }
    }

    /// Get menu bar with timeout protection.
    @MainActor
    public func menuBarWithTimeout(timeout: Float = 2.0) -> Element? {
        try? self.withMessagingTimeout(timeout) { $0.menuBar() }
    }
}

/// A failure to establish a bounded native Accessibility call.
public enum AXMessagingTimeoutError: Error, Equatable, Sendable, CustomStringConvertible {
    case invalidTimeout
    case nestedScope
    case systemFailure(code: Int32)
    case resetFailure(code: Int32)

    public var description: String {
        switch self {
        case .invalidTimeout:
            "AX messaging timeout must be finite and greater than zero."
        case .nestedScope:
            "An AX messaging timeout scope is already active for this element."
        case let .systemFailure(code):
            "macOS refused the AX messaging timeout (AXError \(code))."
        case let .resetFailure(code):
            "macOS refused to clear the AX messaging timeout (AXError \(code))."
        }
    }
}

@MainActor
private enum AXMessagingTimeoutRegistry {
    private static var activeElements: Set<Element> = []

    static func begin(_ element: Element) -> Bool {
        self.activeElements.insert(element).inserted
    }

    static func end(_ element: Element) {
        self.activeElements.remove(element)
    }
}

enum AXMessagingTimeoutScope {
    static func perform<Value>(
        timeout: Float,
        applyTimeout: (Float) -> AXError,
        operation: () throws -> Value) throws -> Value
    {
        guard timeout.isFinite, timeout > 0 else {
            throw AXMessagingTimeoutError.invalidTimeout
        }

        let armResult = applyTimeout(timeout)
        guard armResult == .success else {
            throw AXMessagingTimeoutError.systemFailure(code: armResult.rawValue)
        }

        let operationResult: Result<Value, any Error> = Result {
            try operation()
        }
        let resetResult = applyTimeout(0)
        guard resetResult == .success else {
            throw AXMessagingTimeoutError.resetFailure(code: resetResult.rawValue)
        }
        return try operationResult.get()
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
                    .debug(
                        "AX operation failed (attempt \(attempt + 1)/\(self.maxRetries)): \(String(describing: error))")

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
            "Operation timed out after \(duration)s"
        }
    }
}
