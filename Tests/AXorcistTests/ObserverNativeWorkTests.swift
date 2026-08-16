import ApplicationServices
import Foundation
import Testing
@testable import AXorcist

@Suite("Observer native work")
struct ObserverNativeWorkTests {
    @Test
    func `native registration result semantics remain fail closed`() {
        #expect(NativeNotificationRegistration.removalConfirmsRegistrationAbsent(.success))
        #expect(NativeNotificationRegistration.removalConfirmsRegistrationAbsent(.notificationNotRegistered))
        #expect(!NativeNotificationRegistration.removalConfirmsRegistrationAbsent(.cannotComplete))
        #expect(NativeNotificationRegistration.normalizedAdditionResult(.notificationAlreadyRegistered) == .success)
        #expect(NativeNotificationRegistration.normalizedAdditionResult(.cannotComplete) == .cannotComplete)
    }

    @Test
    func `native observer worker admission is process bounded`() {
        let admission = ObserverNativeWorkerAdmission()
        for _ in 0..<ObserverNativeWorkerAdmission.maximumRegularWorkers {
            #expect(admission.tryAcquire())
        }
        #expect(!admission.tryAcquire())
        #expect(admission.tryAcquireCleanup())
        #expect(admission.activeCount == ObserverNativeWorkerAdmission.maximumConcurrentWorkers)
        #expect(!admission.tryAcquireCleanup())
        admission.release()
        #expect(admission.tryAcquireCleanup())
    }

    @Test
    func `cleanup queues without spawning beyond saturation`() async {
        let admission = ObserverNativeWorkerAdmission()
        for _ in 0..<ObserverNativeWorkerAdmission.maximumRegularWorkers {
            #expect(admission.tryAcquire())
        }
        #expect(admission.tryAcquireCleanup())
        let waiter = Task {
            await admission.acquireCleanup()
            return admission.activeCount
        }
        await Task.yield()

        admission.release()

        #expect(await waiter.value == ObserverNativeWorkerAdmission.maximumConcurrentWorkers)
        admission.release()
    }

    @Test
    func `native work releases admission before resuming its caller`() async {
        let admission = ObserverNativeWorkerAdmission()
        for _ in 0..<(ObserverNativeWorkerAdmission.maximumRegularWorkers - 1) {
            #expect(admission.tryAcquire())
        }

        let result = await ObserverNativeWork.perform(
            admission: admission,
            refusalValue: -1,
            operation: { 42 })

        #expect(result == 42)
        #expect(admission.tryAcquire())
        for _ in 0..<ObserverNativeWorkerAdmission.maximumRegularWorkers {
            admission.release()
        }
    }

    @Test
    func `synchronous cleanup distinguishes saturation from a native result`() {
        let admission = ObserverNativeWorkerAdmission()
        for _ in 0..<ObserverNativeWorkerAdmission.maximumRegularWorkers {
            #expect(admission.tryAcquire())
        }
        #expect(admission.tryAcquireCleanup())
        var executed = false

        let refused = ObserverNativeWork.tryPerformCleanupSynchronously(admission: admission) {
            executed = true
            return AXError.success
        }
        #expect(refused == nil)
        #expect(!executed)

        admission.release()
        let admitted = ObserverNativeWork.tryPerformCleanupSynchronously(admission: admission) {
            executed = true
            return AXError.success
        }
        #expect(admitted == .success)
        #expect(executed)
    }

    @Test
    func `synchronous native removal join has a monotonic deadline`() {
        let completion = NativeRemovalCompletion()
        let clock = ContinuousClock()
        let start = clock.now

        #expect(completion.wait(until: start.advanced(by: .milliseconds(20))) == nil)
        #expect(start.duration(to: clock.now) < .seconds(1))
    }

    @Test @MainActor
    func `removal completion signals while main actor synchronously waits`() {
        let completion = NativeRemovalCompletion()
        Task.detached {
            completion.finish(with: .success)
        }
        let clock = ContinuousClock()

        let result = completion.wait(until: clock.now.advanced(by: .seconds(1)))

        #expect(result == .success)
    }

    @Test @MainActor
    func `observer creation completion signals while main actor pumps run loop`() {
        let completion = NativeObserverCreationCompletion()
        Task.detached {
            completion.finish(with: .timedOut)
        }
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(1))

        while completion.currentResult() == nil, clock.now < deadline {
            _ = RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
        }

        guard case .timedOut = completion.currentResult() else {
            Issue.record("Expected off-actor observer creation completion")
            return
        }
    }

    @Test
    func `timed out observer creation completes synchronously`() {
        let pending = PendingObserverCreation.timedOut(id: UUID(), expectedGeneration: 1)

        guard case .timedOut = pending.completion.currentResult() else {
            Issue.record("Expected the timeout sentinel to be immediately observable")
            return
        }
    }

    @Test
    func `perform fails closed when native notification work never returns`() async {
        let admission = ObserverNativeWorkerAdmission()
        let never = DispatchSemaphore(value: 0)
        let result = await ObserverNativeWork.perform(
            admission: admission,
            refusalValue: AXError.cannotComplete,
            timeout: .milliseconds(50))
        {
            never.wait()
            return .success
        }

        #expect(result == .cannotComplete)
    }

    @Test
    func `performCleanup fails closed when native notification work never returns`() async {
        let admission = ObserverNativeWorkerAdmission()
        let never = DispatchSemaphore(value: 0)
        let result = await ObserverNativeWork.performCleanup(
            admission: admission,
            timeoutValue: AXError.cannotComplete,
            timeout: .milliseconds(50))
        {
            never.wait()
            return AXError.success
        }

        #expect(result == .cannotComplete)
    }

    @Test
    func `removal completion value fails closed when the native result never arrives`() async {
        let completion = NativeRemovalCompletion()

        let result = await completion.value(timeout: .milliseconds(50))

        #expect(result == .cannotComplete)
        #expect(completion.currentResult() == nil)
    }

    @Test
    func `removal timeout does not finalize a later native result`() async {
        let completion = NativeRemovalCompletion()
        let timedOut = await completion.value(timeout: .milliseconds(20))
        completion.finish(with: .success)

        #expect(timedOut == .cannotComplete)
        #expect(completion.currentResult() == .success)
        #expect(await completion.value(timeout: .milliseconds(20)) == .success)
        #expect(completion.currentResult() != timedOut)
    }

    @Test
    func `performCleanup admission is bounded when workers are saturated`() async {
        let admission = ObserverNativeWorkerAdmission()
        for _ in 0..<ObserverNativeWorkerAdmission.maximumRegularWorkers {
            #expect(admission.tryAcquire())
        }
        #expect(admission.tryAcquireCleanup())
        #expect(admission.activeCount == ObserverNativeWorkerAdmission.maximumConcurrentWorkers)

        let result = await ObserverNativeWork.performCleanup(
            admission: admission,
            timeoutValue: AXError.cannotComplete,
            timeout: .milliseconds(40))
        {
            AXError.success
        }

        #expect(result == .cannotComplete)
        #expect(admission.activeCount == ObserverNativeWorkerAdmission.maximumConcurrentWorkers)
    }

    @Test
    func `add attempt is reserved only after worker admission`() async {
        let admission = ObserverNativeWorkerAdmission()
        for _ in 0..<ObserverNativeWorkerAdmission.maximumRegularWorkers {
            #expect(admission.tryAcquire())
        }
        let admitted = LateRemoveCounter()
        let result = await ObserverNativeWork.perform(
            admission: admission,
            refusalValue: AXError.cannotComplete,
            onAdmitted: {
                admitted.increment()
            },
            operation: { AXError.success })

        #expect(result == .cannotComplete)
        #expect(!admitted.didRemove)
    }

    @Test
    func `add attempt table retires only the current generation`() throws {
        let table = NativeAddAttemptTable()
        let identity = try #require(makeTestAddIdentity(pid: 7, notification: "AXCreated"))
        let first = table.begin(identity)
        let second = table.begin(identity)
        table.retire(identity, first)
        #expect(table.isCurrent(identity, second))
        table.retire(identity, second)
        #expect(!table.isCurrent(identity, second))
    }

    @Test
    func `retired add attempt token is not reused by a later begin`() throws {
        let table = NativeAddAttemptTable()
        let identity = try #require(makeTestAddIdentity(pid: 9, notification: "AXTitleChanged"))
        let timedOut = table.begin(identity)
        let successfulRetry = table.begin(identity)
        table.retire(identity, successfulRetry)
        let laterRetry = table.begin(identity)
        #expect(laterRetry != timedOut)
        #expect(table.isCurrent(identity, laterRetry))
        #expect(!table.isCurrent(identity, timedOut))
    }

    @Test
    func `late add cleanup skips remove after a newer attempt starts`() async throws {
        let table = NativeAddAttemptTable()
        let identity = try #require(
            makeTestAddIdentity(pid: 1, notification: "AXFocusedUIElementChanged"))
        let first = table.begin(identity)
        let removed = LateRemoveCounter()
        let release = DispatchSemaphore(value: 0)
        let result = await ObserverNativeWork.perform(
            admission: ObserverNativeWorkerAdmission(),
            refusalValue: AXError.cannotComplete,
            timeout: .milliseconds(30),
            onLateResult: { late in
                removed.markLate()
                if ObserverNativeWork.shouldRemoveLateSuccessfulAdd(
                    late,
                    attemptIsCurrent: table.isCurrent(identity, first))
                {
                    removed.increment()
                }
            },
            operation: {
                release.wait()
                return .success
            })

        #expect(result == .cannotComplete)
        _ = table.begin(identity)
        release.signal()
        let deadline = ContinuousClock().now.advanced(by: .seconds(1))
        while !removed.sawLate, ContinuousClock().now < deadline {
            await Task.yield()
        }
        #expect(removed.sawLate)
        #expect(!removed.didRemove)
    }

    @Test
    func `late add cleanup removes when the timed-out attempt is still current`() async throws {
        let table = NativeAddAttemptTable()
        let identity = try #require(makeTestAddIdentity(pid: 3, notification: "AXValueChanged"))
        let first = table.begin(identity)
        let removed = LateRemoveCounter()
        let release = DispatchSemaphore(value: 0)
        let result = await ObserverNativeWork.perform(
            admission: ObserverNativeWorkerAdmission(),
            refusalValue: AXError.cannotComplete,
            timeout: .milliseconds(30),
            onLateResult: { late in
                removed.markLate()
                if ObserverNativeWork.shouldRemoveLateSuccessfulAdd(
                    late,
                    attemptIsCurrent: table.isCurrent(identity, first))
                {
                    removed.increment()
                }
            },
            operation: {
                release.wait()
                return .success
            })

        #expect(result == .cannotComplete)
        release.signal()
        let deadline = ContinuousClock().now.advanced(by: .seconds(1))
        while !removed.sawLate, ContinuousClock().now < deadline {
            await Task.yield()
        }
        #expect(removed.didRemove)
    }

    @Test
    func `late add cleanup skips remove after a retired token would have been reused`() async throws {
        let table = NativeAddAttemptTable()
        let identity = try #require(makeTestAddIdentity(pid: 11, notification: "AXSelectedTextChanged"))
        let timedOut = table.begin(identity)
        let removed = LateRemoveCounter()
        let release = DispatchSemaphore(value: 0)
        let result = await ObserverNativeWork.perform(
            admission: ObserverNativeWorkerAdmission(),
            refusalValue: AXError.cannotComplete,
            timeout: .milliseconds(30),
            onLateResult: { late in
                removed.markLate()
                if ObserverNativeWork.shouldRemoveLateSuccessfulAdd(
                    late,
                    attemptIsCurrent: table.isCurrent(identity, timedOut))
                {
                    removed.increment()
                }
            },
            operation: {
                release.wait()
                return .success
            })

        #expect(result == .cannotComplete)
        let successfulRetry = table.begin(identity)
        table.retire(identity, successfulRetry)
        let laterRetry = table.begin(identity)
        #expect(laterRetry != timedOut)
        release.signal()
        let deadline = ContinuousClock().now.advanced(by: .seconds(1))
        while !removed.sawLate, ContinuousClock().now < deadline {
            await Task.yield()
        }
        #expect(removed.sawLate)
        #expect(!removed.didRemove)
        #expect(table.isCurrent(identity, laterRetry))
    }

    @Test
    func `late successful add is reported after a timeout`() async {
        let admission = ObserverNativeWorkerAdmission()
        let release = DispatchSemaphore(value: 0)
        let lateBox = LateResultBox()
        let result = await ObserverNativeWork.perform(
            admission: admission,
            refusalValue: AXError.cannotComplete,
            timeout: .milliseconds(30),
            onLateResult: { late in
                lateBox.store(late)
            },
            operation: {
                release.wait()
                return .success
            })

        #expect(result == .cannotComplete)
        release.signal()
        let deadline = ContinuousClock().now.advanced(by: .seconds(1))
        while lateBox.value == nil, ContinuousClock().now < deadline {
            await Task.yield()
        }
        #expect(lateBox.value == .success)
    }
}

private final nonisolated class LateRemoveCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = 0
    private var lateSeen = false

    func markLate() {
        self.lock.lock()
        self.lateSeen = true
        self.lock.unlock()
    }

    func increment() {
        self.lock.lock()
        self.stored += 1
        self.lock.unlock()
    }

    var didRemove: Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.stored > 0
    }

    var sawLate: Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.lateSeen
    }
}

private final nonisolated class LateResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: AXError?

    func store(_ value: AXError) {
        self.lock.lock()
        self.stored = value
        self.lock.unlock()
    }

    var value: AXError? {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.stored
    }
}
