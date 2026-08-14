import ApplicationServices
import Darwin
import Foundation

nonisolated enum ObserverNativeWork {
    private struct ProcessUniqueIdentifierInfo {
        var executableUUIDHigh: UInt64 = 0
        var executableUUIDLow: UInt64 = 0
        var uniqueIdentifier: UInt64 = 0
        var parentUniqueIdentifier: UInt64 = 0
        var identifierVersion: Int32 = 0
        var originalParentIdentifierVersion: Int32 = 0
        var reserved2: UInt64 = 0
        var reserved3: UInt64 = 0
    }

    static func processUniqueIdentity(_ processIdentifier: pid_t) -> UInt64? {
        guard processIdentifier > 0 else { return nil }
        var info = ProcessUniqueIdentifierInfo()
        let expectedSize = Int32(MemoryLayout<ProcessUniqueIdentifierInfo>.stride)
        guard proc_pidinfo(
            processIdentifier,
            17, // PROC_PIDUNIQIDENTIFIERINFO from XNU's proc_info_private.h
            0,
            &info,
            expectedSize) == expectedSize,
            info.uniqueIdentifier != 0
        else { return nil }
        return info.uniqueIdentifier
    }

    static func boundedProcessUniqueIdentity(
        _ processIdentifier: pid_t,
        admission: ObserverNativeWorkerAdmission) async -> UInt64?
    {
        await self.firstResult(
            timeout: .milliseconds(100),
            timeoutValue: UInt64?.none,
            admission: admission)
        {
            self.processUniqueIdentity(processIdentifier)
        }
    }

    static func firstResult<Value: Sendable>(
        timeout: Duration,
        timeoutValue: Value,
        admission: ObserverNativeWorkerAdmission,
        operation: @escaping @Sendable () -> Value) async -> Value
    {
        guard admission.tryAcquire() else { return timeoutValue }
        return await withCheckedContinuation { continuation in
            let gate = FirstResultGate(continuation: continuation)
            Thread.detachNewThread {
                let result = autoreleasepool { operation() }
                admission.release()
                gate.finish(with: result)
            }
            Task.detached(priority: .utility) {
                try? await Task.sleep(for: timeout)
                gate.finish(with: timeoutValue)
            }
        }
    }

    static func perform<Value: Sendable>(
        admission: ObserverNativeWorkerAdmission,
        refusalValue: Value,
        operation: @escaping @Sendable () -> Value) async -> Value
    {
        guard admission.tryAcquire() else { return refusalValue }
        return await withCheckedContinuation { continuation in
            Thread.detachNewThread {
                let result = autoreleasepool { operation() }
                admission.release()
                continuation.resume(returning: result)
            }
        }
    }

    static func performCleanup<Value: Sendable>(
        admission: ObserverNativeWorkerAdmission,
        operation: @escaping @Sendable () -> Value) async -> Value
    {
        await admission.acquireCleanup()
        return await withCheckedContinuation { continuation in
            Thread.detachNewThread {
                let result = autoreleasepool { operation() }
                admission.release()
                continuation.resume(returning: result)
            }
        }
    }

    static func performSynchronously<Value>(
        admission: ObserverNativeWorkerAdmission,
        refusalValue: Value,
        operation: () -> Value) -> Value
    {
        guard admission.tryAcquire() else { return refusalValue }
        defer { admission.release() }
        return operation()
    }

    static func tryPerformCleanupSynchronously<Value>(
        admission: ObserverNativeWorkerAdmission,
        operation: () -> Value) -> Value?
    {
        guard admission.tryAcquireCleanup() else { return nil }
        defer { admission.release() }
        return operation()
    }
}

final nonisolated class ObserverNativeWorkerAdmission: @unchecked Sendable {
    static let maximumConcurrentWorkers = 8
    static let maximumRegularWorkers = ObserverNativeWorkerAdmission.maximumConcurrentWorkers - 1

    private let lock = NSLock()
    private var activeWorkerCount = 0
    private var cleanupWaiters: [CheckedContinuation<Void, Never>] = []

    func tryAcquire() -> Bool {
        self.lock.withLock {
            guard self.activeWorkerCount < Self.maximumRegularWorkers else { return false }
            self.activeWorkerCount += 1
            return true
        }
    }

    func tryAcquireCleanup() -> Bool {
        self.lock.withLock {
            guard self.activeWorkerCount < Self.maximumConcurrentWorkers else { return false }
            self.activeWorkerCount += 1
            return true
        }
    }

    func acquireCleanup() async {
        await withCheckedContinuation { continuation in
            let acquired = self.lock.withLock {
                if self.activeWorkerCount < Self.maximumConcurrentWorkers {
                    self.activeWorkerCount += 1
                    return true
                }
                self.cleanupWaiters.append(continuation)
                return false
            }
            if acquired {
                continuation.resume()
            }
        }
    }

    func release() {
        let waiter = self.lock.withLock { () -> CheckedContinuation<Void, Never>? in
            precondition(self.activeWorkerCount > 0)
            if !self.cleanupWaiters.isEmpty {
                return self.cleanupWaiters.removeFirst()
            }
            self.activeWorkerCount -= 1
            return nil
        }
        waiter?.resume()
    }

    var activeCount: Int {
        self.lock.withLock { self.activeWorkerCount }
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

    func wait(until deadline: ContinuousClock.Instant) -> AXError? {
        let clock = ContinuousClock()
        self.condition.lock()
        while self.result == nil, clock.now < deadline {
            self.condition.wait(until: Date(timeIntervalSinceNow: 0.01))
        }
        let result = self.result
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
