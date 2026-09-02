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
                gate.finish(with: result, releaseAdmission: { admission.release() })
            }
            Task.detached(priority: .utility) {
                try? await Task.sleep(for: timeout)
                gate.finish(with: timeoutValue, fromTimeout: true)
            }
        }
    }

    enum PendingAddDisposition: Equatable, Sendable {
        case commit
        case pendingRemoval
        case finishOnly
    }

    struct PendingNativeFirstResult: Equatable, Sendable {
        let error: AXError
        let timedOut: Bool
    }

    static func shouldLaunchNewAdd(hasInFlightPending: Bool) -> Bool {
        !hasInFlightPending
    }

    static func canLaunchNativeAdd(hasPendingAdd: Bool, hasUnconfirmedRemoval: Bool) -> Bool {
        !hasPendingAdd && !hasUnconfirmedRemoval
    }

    static func pendingAddDisposition(
        nativeError: AXError,
        stillPending: Bool,
        waiterCount: Int,
        generationMatches: Bool,
        isLate: Bool) -> PendingAddDisposition
    {
        if nativeError == .success, stillPending, generationMatches, !isLate || waiterCount > 0 {
            return .commit
        }
        if nativeError == .success {
            return .pendingRemoval
        }
        return .finishOnly
    }

    static func shouldKeepTrackingRemoval(_ error: AXError) -> Bool {
        !NativeNotificationRegistration.removalConfirmsRegistrationAbsent(error)
    }

    /// A missing identity is unknown, not a confirmed PID reuse.
    static func shouldResetObserverGeneration(observed: UInt64?, expected: UInt64) -> Bool {
        guard let observed else { return false }
        return observed != expected
    }

    static func runPendingAdd(
        admission: ObserverNativeWorkerAdmission,
        timeout: Duration = notificationWorkTimeout,
        operation: @escaping @Sendable () -> AXError,
        onFinished: @escaping @Sendable (AXError) -> Void) async -> PendingNativeFirstResult
    {
        let first = NativeAddTokenBox()
        let error = await self.perform(
            admission: admission,
            refusalValue: .cannotComplete,
            timeout: timeout,
            onFirstResult: { fromTimeout in
                if fromTimeout {
                    first.markTimedOutFirst()
                }
            },
            onLateResult: onFinished,
            operation: operation)
        return PendingNativeFirstResult(error: error, timedOut: first.didTimeOutFirst)
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
        onFirstResult: (@Sendable (_ fromTimeout: Bool) -> Void)? = nil,
        onLateResult: (@Sendable (Value) -> Void)? = nil,
        operation: @escaping @Sendable () -> Value) async -> Value
    {
        let acquired = await admission.acquireCleanup(timeout: timeout)
        guard acquired else { return timeoutValue }
        return await withCheckedContinuation { continuation in
            let gate = FirstResultGate(
                continuation: continuation,
                onFirstResult: onFirstResult,
                onLateResult: onLateResult)
            Thread.detachNewThread {
                let result = autoreleasepool { operation() }
                gate.finish(with: result, releaseAdmission: { admission.release() })
            }
            Task.detached(priority: .utility) {
                try? await Task.sleep(for: timeout)
                gate.finish(with: timeoutValue, fromTimeout: true)
            }
        }
    }

    /// Timeout bounds the waiter only. The pending record stays until the
    /// native remove reports its own result.
    static func shouldFinalizePendingRemoval(firstResultFromTimeout: Bool) -> Bool {
        !firstResultFromTimeout
    }

    static func runPendingCleanup(
        admission: ObserverNativeWorkerAdmission,
        timeout: Duration = notificationWorkTimeout,
        operation: @escaping @Sendable () -> AXError,
        onFinished: @escaping @Sendable (AXError) -> Void) async
    {
        let first = NativeAddTokenBox()
        let error = await self.performCleanup(
            admission: admission,
            timeoutValue: .cannotComplete,
            timeout: timeout,
            onFirstResult: { fromTimeout in
                if fromTimeout {
                    first.markTimedOutFirst()
                }
            },
            onLateResult: onFinished,
            operation: operation)
        guard self.shouldFinalizePendingRemoval(firstResultFromTimeout: first.didTimeOutFirst) else {
            return
        }
        onFinished(error)
    }
}

final nonisolated class ObserverNativeWorkerAdmission: @unchecked Sendable {
    static let maximumConcurrentWorkers = 8
    static let maximumRegularWorkers = ObserverNativeWorkerAdmission.maximumConcurrentWorkers - 1
    static let cleanupAdmissionTimeout = ObserverNativeWork.notificationWorkTimeout

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

    func acquireCleanup(timeout: Duration = cleanupAdmissionTimeout) async -> Bool {
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

    func finish(
        with value: Value,
        fromTimeout: Bool = false,
        releaseAdmission: (@Sendable () -> Void)? = nil)
    {
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
            if !fromTimeout {
                releaseAdmission?()
            }
            continuation.resume(returning: value)
            return
        }
        if let late = outcome.1 {
            self.onLateResult?(late)
            releaseAdmission?()
        }
    }
}

final nonisolated class ObserverAsyncStartGate: @unchecked Sendable {
    private let lock = NSLock()
    private var isOpen = false
    private var waiter: CheckedContinuation<Void, Never>?

    func wait() async {
        await withCheckedContinuation { continuation in
            let resumeNow = self.lock.withLock { () -> Bool in
                if self.isOpen {
                    return true
                }
                self.waiter = continuation
                return false
            }
            if resumeNow {
                continuation.resume()
            }
        }
    }

    func open() {
        let waiter = self.lock.withLock { () -> CheckedContinuation<Void, Never>? in
            self.isOpen = true
            defer { self.waiter = nil }
            return self.waiter
        }
        waiter?.resume()
    }
}

nonisolated class NativeWorkCompletion<Value: Sendable>: @unchecked Sendable {
    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Value, Never>
    }

    private let condition = NSCondition()
    private let timeoutValue: Value
    private var result: Value?
    private var waiters: [Waiter] = []
    private var parkedWaiterCount = 0
    private var finishedWaiterCount = 0
    private var finishedSynchronousWaiterCount = 0

    init(timeoutValue: Value) {
        self.timeoutValue = timeoutValue
    }

    @discardableResult
    func parkWaiter() -> Bool {
        self.condition.lock()
        defer { self.condition.unlock() }
        guard self.result == nil else { return false }
        self.parkedWaiterCount += 1
        return true
    }

    func unparkWaiter() {
        self.condition.lock()
        if self.parkedWaiterCount > 0 {
            self.parkedWaiterCount -= 1
        }
        self.condition.unlock()
    }

    func wait(until deadline: ContinuousClock.Instant) -> Value? {
        let clock = ContinuousClock()
        self.condition.lock()
        while self.result == nil, clock.now < deadline {
            self.condition.wait(until: Date(timeIntervalSinceNow: 0.01))
        }
        let result = self.result
        self.condition.unlock()
        return result
    }

    func currentResult() -> Value? {
        self.condition.withLock { self.result }
    }

    var waiterCount: Int {
        self.condition.withLock { self.waiters.count + self.parkedWaiterCount }
    }

    var waiterCountAtFinish: Int {
        self.condition.withLock { self.finishedWaiterCount }
    }

    var synchronousWaiterCountAtFinish: Int {
        self.condition.withLock { self.finishedSynchronousWaiterCount }
    }

    @discardableResult
    func finish(with result: Value) -> Int {
        self.condition.lock()
        guard self.result == nil else {
            self.condition.unlock()
            return 0
        }
        self.result = result
        self.finishedWaiterCount = self.waiters.count + self.parkedWaiterCount
        self.finishedSynchronousWaiterCount = self.parkedWaiterCount
        let waiters = self.waiters
        self.waiters.removeAll()
        self.condition.broadcast()
        self.condition.unlock()
        for waiter in waiters {
            waiter.continuation.resume(returning: result)
        }
        return waiters.count
    }

    func value(timeout: Duration = .milliseconds(750)) async -> Value {
        let waiterID = UUID()
        return await withCheckedContinuation { continuation in
            self.condition.lock()
            if let result = self.result {
                self.condition.unlock()
                continuation.resume(returning: result)
                return
            }
            self.waiters.append(Waiter(id: waiterID, continuation: continuation))
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
        waiter.continuation.resume(returning: self.timeoutValue)
    }
}

final nonisolated class NativeRemovalCompletion: NativeWorkCompletion<AXError>, @unchecked Sendable {
    init() {
        super.init(timeoutValue: .cannotComplete)
    }
}

nonisolated enum NativeAddResolutionOwner: Equatable, Sendable {
    case synchronous
    case asynchronous
    case alreadyFinished
}

final nonisolated class NativeAddCompletion: @unchecked Sendable {
    private enum ResolutionState {
        case waitingForNative
        case queuedAsynchronous
        case synchronous
        case resolvingAsynchronously
        case resolved
    }

    private let condition = NSCondition()
    private let resolved = NativeWorkCompletion<ObserverNativeWork.PendingNativeFirstResult>(
        timeoutValue: ObserverNativeWork.PendingNativeFirstResult(
            error: .cannotComplete,
            timedOut: true))
    private var nativeResult: ObserverNativeWork.PendingNativeFirstResult?
    private var synchronousWaiterActive = false
    private var waiterCountWhenNativeFinished = 0
    private var resolutionState = ResolutionState.waitingForNative

    func beginSynchronousWait() -> Bool {
        self.condition.lock()
        defer { self.condition.unlock() }
        switch self.resolutionState {
        case .waitingForNative where !self.synchronousWaiterActive:
            self.synchronousWaiterActive = true
            return true
        case .queuedAsynchronous:
            self.resolutionState = .synchronous
            self.synchronousWaiterActive = true
            return true
        case .waitingForNative, .synchronous, .resolvingAsynchronously, .resolved:
            return false
        }
    }

    func finishNative(with result: ObserverNativeWork.PendingNativeFirstResult) -> NativeAddResolutionOwner {
        self.condition.lock()
        guard self.nativeResult == nil else {
            self.condition.unlock()
            return .alreadyFinished
        }
        self.nativeResult = result
        self.waiterCountWhenNativeFinished = self.resolved.waiterCount + (self.synchronousWaiterActive ? 1 : 0)
        let owner: NativeAddResolutionOwner = self.synchronousWaiterActive ? .synchronous : .asynchronous
        self.resolutionState = self.synchronousWaiterActive ? .synchronous : .queuedAsynchronous
        self.condition.broadcast()
        self.condition.unlock()
        return owner
    }

    func waitForNativeResult(until deadline: ContinuousClock.Instant) -> ObserverNativeWork.PendingNativeFirstResult? {
        let clock = ContinuousClock()
        self.condition.lock()
        while self.nativeResult == nil, clock.now < deadline {
            self.condition.wait(until: Date(timeIntervalSinceNow: 0.01))
        }
        let result = self.nativeResult
        self.synchronousWaiterActive = false
        self.condition.unlock()
        return result
    }

    func beginAsynchronousResolution() -> Bool {
        self.condition.lock()
        defer { self.condition.unlock() }
        guard self.resolutionState == .queuedAsynchronous else { return false }
        self.resolutionState = .resolvingAsynchronously
        return true
    }

    func publishResolved(_ result: ObserverNativeWork.PendingNativeFirstResult) {
        self.condition.withLock {
            self.resolutionState = .resolved
            self.synchronousWaiterActive = false
        }
        self.resolved.finish(with: result)
    }

    func currentResult() -> ObserverNativeWork.PendingNativeFirstResult? {
        self.resolved.currentResult()
    }

    func value(timeout: Duration = .milliseconds(750)) async -> ObserverNativeWork.PendingNativeFirstResult {
        await self.resolved.value(timeout: timeout)
    }

    var waiterCountAtNativeFinish: Int {
        self.condition.withLock { self.waiterCountWhenNativeFinished }
    }

    var resolutionWaiterCount: Int {
        self.resolved.waiterCount
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

    var work: ObserverNativeRegistrationWork {
        ObserverNativeRegistrationWork(add: self.add, remove: self.remove)
    }
}

nonisolated struct ObserverNativeRegistrationWork: Sendable {
    let add: @Sendable () -> AXError
    let remove: @Sendable () -> AXError
}
