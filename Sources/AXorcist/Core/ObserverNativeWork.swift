import ApplicationServices
import Darwin
import Foundation

nonisolated enum ObserverNativeWork {
    static let notificationWorkTimeout: Duration = .milliseconds(500)

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
        onAdmitted: (@Sendable () -> Void)? = nil,
        onFirstResult: (@Sendable (_ fromTimeout: Bool) -> Void)? = nil,
        onLateResult: (@Sendable (Value) -> Void)? = nil,
        operation: @escaping @Sendable () -> Value) async -> Value
    {
        guard admission.tryAcquire() else { return timeoutValue }
        onAdmitted?()
        return await withCheckedContinuation { continuation in
            let gate = FirstResultGate(
                continuation: continuation,
                onFirstResult: onFirstResult,
                onLateResult: onLateResult)
            Thread.detachNewThread {
                let result = autoreleasepool { operation() }
                admission.release()
                gate.finish(with: result)
            }
            Task.detached(priority: .utility) {
                try? await Task.sleep(for: timeout)
                gate.finish(with: timeoutValue, fromTimeout: true)
            }
        }
    }

    static func addNotification(
        _ registration: NativeNotificationRegistration,
        admission: ObserverNativeWorkerAdmission) async -> AXError
    {
        let identity = registration.addIdentity
        let attempt = NativeAddTokenBox()
        let result = await self.perform(
            admission: admission,
            refusalValue: AXError.cannotComplete,
            onAdmitted: {
                attempt.store(NativeAddAttempts.begin(identity))
            },
            onFirstResult: { fromTimeout in
                if fromTimeout {
                    attempt.markTimedOutFirst()
                }
            },
            onLateResult: { late in
                if self.shouldRemoveLateSuccessfulAdd(
                    late,
                    attemptIsCurrent: NativeAddAttempts.isCurrent(identity, token: attempt.value))
                {
                    _ = registration.remove()
                }
                NativeAddAttempts.retire(identity, token: attempt.value)
            },
            operation: registration.add)
        if !attempt.didTimeOutFirst {
            NativeAddAttempts.retire(identity, token: attempt.value)
        }
        return result
    }

    static func shouldRemoveLateSuccessfulAdd(_ late: AXError, attemptIsCurrent: Bool) -> Bool {
        late == .success && attemptIsCurrent
    }

    static func perform<Value: Sendable>(
        admission: ObserverNativeWorkerAdmission,
        refusalValue: Value,
        timeout: Duration = notificationWorkTimeout,
        onAdmitted: (@Sendable () -> Void)? = nil,
        onFirstResult: (@Sendable (_ fromTimeout: Bool) -> Void)? = nil,
        onLateResult: (@Sendable (Value) -> Void)? = nil,
        operation: @escaping @Sendable () -> Value) async -> Value
    {
        await self.firstResult(
            timeout: timeout,
            timeoutValue: refusalValue,
            admission: admission,
            onAdmitted: onAdmitted,
            onFirstResult: onFirstResult,
            onLateResult: onLateResult,
            operation: operation)
    }

    static func performCleanup<Value: Sendable>(
        admission: ObserverNativeWorkerAdmission,
        timeoutValue: Value,
        timeout: Duration = notificationWorkTimeout,
        operation: @escaping @Sendable () -> Value) async -> Value
    {
        let acquired = await admission.acquireCleanup(timeout: timeout)
        guard acquired else { return timeoutValue }
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
    private var cleanupWaiters: [CleanupWaiter] = []

    private struct CleanupWaiter {
        let id: UUID
        let continuation: CheckedContinuation<Bool, Never>
    }

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
        let acquired = await self.acquireCleanup(timeout: .seconds(365 * 24 * 60 * 60))
        precondition(acquired, "unbounded cleanup admission must eventually acquire")
    }

    func acquireCleanup(timeout: Duration) async -> Bool {
        await withCheckedContinuation { continuation in
            let id = UUID()
            let acquired = self.lock.withLock {
                if self.activeWorkerCount < Self.maximumConcurrentWorkers {
                    self.activeWorkerCount += 1
                    return true
                }
                self.cleanupWaiters.append(CleanupWaiter(id: id, continuation: continuation))
                return false
            }
            if acquired {
                continuation.resume(returning: true)
                return
            }
            Task.detached(priority: .utility) {
                try? await Task.sleep(for: timeout)
                self.timeoutCleanupWaiter(id: id)
            }
        }
    }

    private func timeoutCleanupWaiter(id: UUID) {
        let waiter = self.lock.withLock { () -> CleanupWaiter? in
            guard let index = self.cleanupWaiters.firstIndex(where: { $0.id == id }) else {
                return nil
            }
            return self.cleanupWaiters.remove(at: index)
        }
        waiter?.continuation.resume(returning: false)
    }

    func release() {
        let waiter = self.lock.withLock { () -> CleanupWaiter? in
            precondition(self.activeWorkerCount > 0)
            if !self.cleanupWaiters.isEmpty {
                return self.cleanupWaiters.removeFirst()
            }
            self.activeWorkerCount -= 1
            return nil
        }
        waiter?.continuation.resume(returning: true)
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

struct PendingObserverCreation {
    let id: UUID
    let expectedGeneration: UInt64
    let task: Task<NativeObserverCreation, Never>
    let completion: NativeObserverCreationCompletion

    static func timedOut(id: UUID, expectedGeneration: UInt64) -> Self {
        let completion = NativeObserverCreationCompletion()
        completion.finish(with: .timedOut)
        let task = Task<NativeObserverCreation, Never> { .timedOut }
        return Self(
            id: id,
            expectedGeneration: expectedGeneration,
            task: task,
            completion: completion)
    }
}

final nonisolated class FirstResultGate<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Never>?
    private var delivered = false
    private let onFirstResult: (@Sendable (Bool) -> Void)?
    private let onLateResult: (@Sendable (Value) -> Void)?

    init(
        continuation: CheckedContinuation<Value, Never>,
        onFirstResult: (@Sendable (Bool) -> Void)? = nil,
        onLateResult: (@Sendable (Value) -> Void)? = nil)
    {
        self.continuation = continuation
        self.onFirstResult = onFirstResult
        self.onLateResult = onLateResult
    }

    func finish(with value: Value, fromTimeout: Bool = false) {
        let outcome = self.lock.withLock { () -> (CheckedContinuation<Value, Never>?, Value?, Bool) in
            if !self.delivered {
                self.delivered = true
                let continuation = self.continuation
                self.continuation = nil
                return (continuation, nil, fromTimeout)
            }
            if fromTimeout {
                return (nil, nil, false)
            }
            return (nil, value, false)
        }
        if let continuation = outcome.0 {
            self.onFirstResult?(outcome.2)
            continuation.resume(returning: value)
        }
        if let late = outcome.1 {
            self.onLateResult?(late)
        }
    }
}

final nonisolated class NativeRemovalCompletion: @unchecked Sendable {
    private struct RemovalWaiter {
        let id: UUID
        let continuation: CheckedContinuation<AXError, Never>
    }

    private let condition = NSCondition()
    private var result: AXError?
    private var waiters: [RemovalWaiter] = []

    func finish(with result: AXError) {
        self.condition.lock()
        guard self.result == nil else {
            self.condition.unlock()
            return
        }
        self.result = result
        let waiters = self.waiters
        self.waiters.removeAll()
        self.condition.broadcast()
        self.condition.unlock()
        for waiter in waiters {
            waiter.continuation.resume(returning: result)
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

    func value(timeout: Duration = .milliseconds(750)) async -> AXError {
        let waiterID = UUID()
        return await withCheckedContinuation { continuation in
            self.condition.lock()
            if let result = self.result {
                self.condition.unlock()
                continuation.resume(returning: result)
                return
            }
            self.waiters.append(RemovalWaiter(id: waiterID, continuation: continuation))
            self.condition.unlock()
            Task.detached(priority: .utility) {
                try? await Task.sleep(for: timeout)
                self.timeoutWaiter(id: waiterID)
            }
        }
    }

    private func timeoutWaiter(id: UUID) {
        self.condition.lock()
        guard self.result == nil,
              let index = self.waiters.firstIndex(where: { $0.id == id })
        else {
            self.condition.unlock()
            return
        }
        let waiter = self.waiters.remove(at: index)
        self.condition.unlock()
        waiter.continuation.resume(returning: .cannotComplete)
    }
}

final nonisolated class NativeObserverCreationCompletion: @unchecked Sendable {
    private let condition = NSCondition()
    private var result: NativeObserverCreation?

    func finish(with result: NativeObserverCreation) {
        self.condition.withLock {
            guard self.result == nil else { return }
            self.result = result
            self.condition.broadcast()
        }
    }

    func currentResult() -> NativeObserverCreation? {
        self.condition.withLock { self.result }
    }
}

nonisolated struct NativeAddIdentity: Hashable, Sendable {
    let observerBits: UInt
    let elementBits: UInt
    let notification: String
}

nonisolated enum NativeAddAttempts {
    private static let table = NativeAddAttemptTable()

    static func begin(_ identity: NativeAddIdentity) -> UInt64 {
        self.table.begin(identity)
    }

    static func isCurrent(_ identity: NativeAddIdentity, token: UInt64?) -> Bool {
        guard let token else { return false }
        return self.table.isCurrent(identity, token)
    }

    static func retire(_ identity: NativeAddIdentity, token: UInt64?) {
        guard let token else { return }
        self.table.retire(identity, token)
    }
}

final nonisolated class NativeAddTokenBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: UInt64?
    private var timedOutFirst = false

    func store(_ value: UInt64) {
        self.lock.lock()
        self.stored = value
        self.lock.unlock()
    }

    func markTimedOutFirst() {
        self.lock.lock()
        self.timedOutFirst = true
        self.lock.unlock()
    }

    var value: UInt64? {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.stored
    }

    var didTimeOutFirst: Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.timedOutFirst
    }
}

final nonisolated class NativeAddAttemptTable: @unchecked Sendable {
    private let lock = NSLock()
    private var generations: [NativeAddIdentity: UInt64] = [:]

    func begin(_ identity: NativeAddIdentity) -> UInt64 {
        self.lock.lock()
        defer { self.lock.unlock() }
        let next = (self.generations[identity] ?? 0) + 1
        self.generations[identity] = next
        return next
    }

    func isCurrent(_ identity: NativeAddIdentity, _ token: UInt64) -> Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.generations[identity] == token
    }

    func retire(_ identity: NativeAddIdentity, _ token: UInt64) {
        self.lock.lock()
        defer { self.lock.unlock() }
        if self.generations[identity] == token {
            self.generations.removeValue(forKey: identity)
        }
    }
}

nonisolated struct NativeNotificationRegistration: @unchecked Sendable {
    let observer: AXObserver
    let element: AXUIElement
    let notification: CFString
    let refcon: UnsafeMutableRawPointer
    let appliesMessagingTimeout: Bool

    var addIdentity: NativeAddIdentity {
        NativeAddIdentity(
            observerBits: UInt(truncatingIfNeeded: CFHash(self.observer)),
            elementBits: UInt(truncatingIfNeeded: CFHash(self.element)),
            notification: self.notification as String)
    }

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
