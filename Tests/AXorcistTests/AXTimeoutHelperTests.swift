import ApplicationServices
import Darwin
import Foundation
import Testing
@testable import AXorcist

@Suite("AXTimeoutHelper")
struct AXTimeoutHelperTests {
    @MainActor
    @Test
    func `completes before timeout`() async throws {
        let value: Int = try await AXTimeoutHelper.withTimeout(seconds: 0.2) {
            try await Task.sleep(nanoseconds: 50_000_000)
            return 7
        }
        #expect(value == 7)
    }

    @MainActor
    @Test
    func `throws on timeout`() async {
        do {
            _ = try await AXTimeoutHelper.withTimeout(seconds: 0.05) {
                try await Task.sleep(nanoseconds: 200_000_000)
                return 1
            }
            Issue.record("Expected timeout but succeeded")
        } catch let error as AXTimeoutError {
            #expect(String(describing: error).contains("timed out"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test(arguments: ["windows", "menu bar", "child element"])
    func `checked messaging scope skips protected AX reads when deadline cannot be armed`(read: String) {
        var timeoutHistory: [Float] = []
        var dispatchedReads: [String] = []

        #expect(throws: AXMessagingTimeoutError.systemFailure(code: AXError.failure.rawValue)) {
            try AXMessagingTimeoutScope.perform(
                timeout: 0.25,
                applyTimeout: { timeout in
                    timeoutHistory.append(timeout)
                    return .failure
                },
                operation: {
                    dispatchedReads.append(read)
                })
        }

        #expect(timeoutHistory == [0.25])
        #expect(dispatchedReads.isEmpty)
    }

    @Test
    func `checked messaging scope clears an armed deadline after success`() throws {
        var timeoutHistory: [Float] = []

        let result = try AXMessagingTimeoutScope.perform(
            timeout: 0.5,
            applyTimeout: { timeout in
                timeoutHistory.append(timeout)
                return .success
            },
            operation: { 42 })

        #expect(result == 42)
        #expect(timeoutHistory == [0.5, 0])
    }

    @Test
    func `checked messaging scope clears an armed deadline after operation failure`() {
        enum ProbeError: Error {
            case failed
        }

        var timeoutHistory: [Float] = []
        #expect(throws: ProbeError.self) {
            try AXMessagingTimeoutScope.perform(
                timeout: 0.5,
                applyTimeout: { timeout in
                    timeoutHistory.append(timeout)
                    return .success
                },
                operation: {
                    throw ProbeError.failed
                })
        }

        #expect(timeoutHistory == [0.5, 0])
    }

    @Test
    func `checked messaging scope reports reset failure instead of returning success`() {
        var timeoutHistory: [Float] = []

        #expect(throws: AXMessagingTimeoutError.resetFailure(code: AXError.failure.rawValue)) {
            try AXMessagingTimeoutScope.perform(
                timeout: 0.5,
                applyTimeout: { timeout in
                    timeoutHistory.append(timeout)
                    return timeout == 0 ? .failure : .success
                },
                operation: { 42 })
        }

        #expect(timeoutHistory == [0.5, 0])
    }

    @Test
    func `checked messaging scope prioritizes reset failure after operation failure`() {
        enum ProbeError: Error {
            case failed
        }

        var timeoutHistory: [Float] = []
        #expect(throws: AXMessagingTimeoutError.resetFailure(code: AXError.failure.rawValue)) {
            try AXMessagingTimeoutScope.perform(
                timeout: 0.5,
                applyTimeout: { timeout in
                    timeoutHistory.append(timeout)
                    return timeout == 0 ? .failure : .success
                },
                operation: {
                    throw ProbeError.failed
                })
        }

        #expect(timeoutHistory == [0.5, 0])
    }

    @Test(arguments: [Float.zero, -0.1, -.infinity, .infinity, .nan])
    func `checked messaging scope rejects invalid deadlines before the system call`(timeout: Float) {
        var appliedTimeouts: [Float] = []
        var dispatched = false

        #expect(throws: AXMessagingTimeoutError.invalidTimeout) {
            try AXMessagingTimeoutScope.perform(
                timeout: timeout,
                applyTimeout: { value in
                    appliedTimeouts.append(value)
                    return .success
                },
                operation: {
                    dispatched = true
                })
        }

        #expect(appliedTimeouts.isEmpty)
        #expect(!dispatched)
    }

    @Test
    @MainActor
    func `element messaging scope refuses dispatch when the native deadline fails`() {
        let invalidApplication = Element(AXUIElementCreateApplication(-1))
        var dispatched = false

        #expect(throws: AXMessagingTimeoutError.systemFailure(code: AXError.invalidUIElement.rawValue)) {
            try invalidApplication.withMessagingTimeout(0.5) { _ in
                dispatched = true
            }
        }

        #expect(!dispatched)
    }

    @Test
    @MainActor
    func `element messaging scope refuses same-element reentrancy`() throws {
        let element = Element(AXUIElementCreateApplication(getpid()))

        _ = try element.withMessagingTimeout(0.5) { outerElement in
            #expect(throws: AXMessagingTimeoutError.nestedScope) {
                try outerElement.withMessagingTimeout(0.25) { _ in
                    Issue.record("Nested operation must not run")
                }
            }
        }
    }

    @Test
    @MainActor
    func `element messaging scope releases ownership after a thrown operation`() throws {
        enum ProbeError: Error {
            case failed
        }

        let element = Element(AXUIElementCreateApplication(getpid()))
        #expect(throws: ProbeError.self) {
            try element.withMessagingTimeout(0.5) { _ in
                throw ProbeError.failed
            }
        }

        let result = try element.withMessagingTimeout(0.5) { _ in 42 }
        #expect(result == 42)
    }

    @Test
    @MainActor
    func `different elements keep independent messaging scopes`() throws {
        let application = Element(AXUIElementCreateApplication(getpid()))
        let systemWide = Element(AXUIElementCreateSystemWide())

        let result = try application.withMessagingTimeout(0.5) { _ in
            try systemWide.withMessagingTimeout(0.5) { _ in 42 }
        }
        #expect(result == 42)
    }
}
