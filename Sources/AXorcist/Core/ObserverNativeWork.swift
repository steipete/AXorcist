import ApplicationServices
import Foundation

nonisolated enum ObserverNativeWorkerAdmission {
    static let maximumConcurrentWorkers = 8

    static func allowsStartingWorker(activeWorkerCount: Int) -> Bool {
        activeWorkerCount < self.maximumConcurrentWorkers
    }
}

nonisolated struct SendableObserver: @unchecked Sendable {
    let value: AXObserver
}

nonisolated struct SendableObserverCallback: @unchecked Sendable {
    let value: AXObserverCallbackWithInfo
}

nonisolated enum NativeObserverCreation: @unchecked Sendable {
    case created(SendableObserver)
    case failed(AXError)
    case timedOut
}

final nonisolated class FirstResultGate<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Never>?

    init(continuation: CheckedContinuation<Value, Never>) {
        self.continuation = continuation
    }

    func finish(with value: Value) {
        let continuation = self.lock.withLock {
            defer { self.continuation = nil }
            return self.continuation
        }
        continuation?.resume(returning: value)
    }
}

final nonisolated class NativeRemovalCompletion: @unchecked Sendable {
    private let condition = NSCondition()
    private var result: AXError?
    private var continuations: [CheckedContinuation<AXError, Never>] = []

    func finish(with result: AXError) {
        self.condition.lock()
        guard self.result == nil else {
            self.condition.unlock()
            return
        }
        self.result = result
        let continuations = self.continuations
        self.continuations.removeAll()
        self.condition.broadcast()
        self.condition.unlock()
        for continuation in continuations {
            continuation.resume(returning: result)
        }
    }

    func wait() -> AXError {
        self.condition.lock()
        while self.result == nil {
            self.condition.wait()
        }
        let result = self.result ?? .failure
        self.condition.unlock()
        return result
    }

    func currentResult() -> AXError? {
        self.condition.withLock { self.result }
    }

    func value() async -> AXError {
        await withCheckedContinuation { continuation in
            self.condition.lock()
            if let result = self.result {
                self.condition.unlock()
                continuation.resume(returning: result)
            } else {
                self.continuations.append(continuation)
                self.condition.unlock()
            }
        }
    }
}

nonisolated struct NativeNotificationRegistration: @unchecked Sendable {
    let observer: AXObserver
    let element: AXUIElement
    let notification: CFString
    let refcon: UnsafeMutableRawPointer
    let appliesMessagingTimeout: Bool

    static func removalConfirmsRegistrationAbsent(_ error: AXError) -> Bool {
        error == .success || error == .notificationNotRegistered
    }

    static func normalizedAdditionResult(_ error: AXError) -> AXError {
        error == .notificationAlreadyRegistered ? .success : error
    }

    func add() -> AXError {
        guard self.applyTimeoutIfNeeded() else {
            return .cannotComplete
        }
        defer { self.resetTimeoutIfNeeded() }
        let error = AXObserverAddNotification(
            self.observer,
            self.element,
            self.notification,
            self.refcon)
        return Self.normalizedAdditionResult(error)
    }

    func remove() -> AXError {
        guard self.applyTimeoutIfNeeded() else {
            return .cannotComplete
        }
        defer { self.resetTimeoutIfNeeded() }
        return AXObserverRemoveNotification(self.observer, self.element, self.notification)
    }

    private func applyTimeoutIfNeeded() -> Bool {
        !self.appliesMessagingTimeout || AXUIElementSetMessagingTimeout(self.element, 0.5) == .success
    }

    private func resetTimeoutIfNeeded() {
        guard self.appliesMessagingTimeout else { return }
        AXUIElementSetMessagingTimeout(self.element, 0)
    }
}
