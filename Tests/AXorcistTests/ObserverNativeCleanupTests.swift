import ApplicationServices
import Darwin
import Foundation
import Testing
@testable import AXorcist

@Suite("Observer native cleanup")
struct ObserverNativeCleanupTests {
    @Test
    func `cleanup timeout keeps pending until the late native remove returns`() async {
        let admission = ObserverNativeWorkerAdmission()
        let release = DispatchSemaphore(value: 0)
        let first = NativeAddTokenBox()
        let completion = NativeRemovalCompletion()
        let result = await ObserverNativeWork.performCleanup(
            admission: admission,
            timeoutValue: AXError.cannotComplete,
            timeout: .milliseconds(30),
            onFirstResult: { fromTimeout in
                if fromTimeout {
                    first.markTimedOutFirst()
                }
            },
            onLateResult: { late in
                completion.finish(with: late)
            },
            operation: {
                release.wait()
                return AXError.success
            })

        #expect(result == .cannotComplete)
        #expect(first.didTimeOutFirst)
        #expect(!ObserverNativeWork.shouldFinalizePendingRemoval(firstResultFromTimeout: true))
        let retryWait = await completion.value(timeout: .milliseconds(20))
        #expect(retryWait == .cannotComplete)
        #expect(completion.currentResult() == nil)

        release.signal()
        let deadline = ContinuousClock().now.advanced(by: .seconds(1))
        while completion.currentResult() == nil, ContinuousClock().now < deadline {
            await Task.yield()
        }
        #expect(completion.currentResult() == .success)
        #expect(await completion.value(timeout: .milliseconds(20)) == .success)
        #expect(ObserverNativeWork.shouldFinalizePendingRemoval(firstResultFromTimeout: false))
    }

    @Test
    func `runPendingCleanup finalizes immediately when cleanup admission fails`() async {
        let admission = ObserverNativeWorkerAdmission()
        for _ in 0..<ObserverNativeWorkerAdmission.maximumRegularWorkers {
            #expect(admission.tryAcquire())
        }
        #expect(admission.tryAcquireCleanup())
        let finished = LateResultBox()
        await ObserverNativeWork.runPendingCleanup(
            admission: admission,
            timeout: .milliseconds(30),
            operation: { AXError.success },
            onFinished: { error in
                finished.store(error)
            })
        #expect(finished.value == .cannotComplete)
        #expect(ObserverNativeWork.shouldFinalizePendingRemoval(firstResultFromTimeout: false))
    }

    @Test
    func `runPendingCleanup finalizes only after the native remove`() async {
        let admission = ObserverNativeWorkerAdmission()
        let release = DispatchSemaphore(value: 0)
        let finished = LateResultBox()
        let work = Task {
            await ObserverNativeWork.runPendingCleanup(
                admission: admission,
                timeout: .milliseconds(30),
                operation: {
                    release.wait()
                    return AXError.success
                },
                onFinished: { error in
                    finished.store(error)
                })
        }

        try? await Task.sleep(for: .milliseconds(50))
        #expect(finished.value == nil)
        release.signal()
        let deadline = ContinuousClock().now.advanced(by: .seconds(1))
        while finished.value == nil, ContinuousClock().now < deadline {
            await Task.yield()
        }
        await work.value
        #expect(finished.value == .success)
    }

    @Test
    func `late result rollback holds the worker admission slot`() async {
        let admission = ObserverNativeWorkerAdmission()
        for _ in 0..<(ObserverNativeWorkerAdmission.maximumRegularWorkers - 1) {
            #expect(admission.tryAcquire())
        }
        let release = DispatchSemaphore(value: 0)
        let holdLate = DispatchSemaphore(value: 0)
        let activeDuringLate = LateCountBox()
        let enteredLate = LateCountBox()
        let work = Task {
            await ObserverNativeWork.perform(
                admission: admission,
                refusalValue: -1,
                timeout: .milliseconds(30),
                onLateResult: { _ in
                    activeDuringLate.store(admission.activeCount)
                    enteredLate.store(1)
                    holdLate.wait()
                },
                operation: {
                    release.wait()
                    return 1
                })
        }

        #expect(await work.value == -1)
        #expect(admission.activeCount == ObserverNativeWorkerAdmission.maximumRegularWorkers)
        #expect(!admission.tryAcquire())

        release.signal()
        let enteredDeadline = ContinuousClock().now.advanced(by: .seconds(1))
        while enteredLate.value == 0, ContinuousClock().now < enteredDeadline {
            await Task.yield()
        }
        #expect(enteredLate.value == 1)
        #expect(activeDuringLate.value == ObserverNativeWorkerAdmission.maximumRegularWorkers)
        #expect(!admission.tryAcquire())

        holdLate.signal()
        let releasedDeadline = ContinuousClock().now.advanced(by: .seconds(1))
        while admission.activeCount != ObserverNativeWorkerAdmission.maximumRegularWorkers - 1,
              ContinuousClock().now < releasedDeadline
        {
            await Task.yield()
        }
        #expect(admission.tryAcquire())
    }

    @Test
    func `process scoped add identities share a generation across fresh application proxies`() throws {
        var createdObserver: AXObserver?
        let callback: AXObserverCallbackWithInfo = { _, _, _, _, _ in }
        let created = AXObserverCreateWithInfoCallback(getpid(), callback, &createdObserver)
        let observer = try #require(created == .success ? createdObserver : nil)
        let processIdentifier = getpid()
        let notification = kAXFocusedUIElementChangedNotification as CFString
        let firstProxy = makeProcessAddRegistration(
            observer: observer,
            pid: processIdentifier,
            notification: notification)
        let retryProxy = makeProcessAddRegistration(
            observer: observer,
            pid: processIdentifier,
            notification: notification)
        #expect(firstProxy.addIdentity == retryProxy.addIdentity)
        #expect(ObjectIdentifier(firstProxy.element) != ObjectIdentifier(retryProxy.element))

        let table = NativeAddAttemptTable()
        let firstToken = table.begin(firstProxy.addIdentity)
        let retryToken = table.begin(retryProxy.addIdentity)
        #expect(retryToken != firstToken)
        #expect(!table.isCurrent(firstProxy.addIdentity, firstToken))
        #expect(table.isCurrent(retryProxy.addIdentity, retryToken))
    }

    @Test
    func `element scoped add identities use CFEqual not pointer identity`() throws {
        var createdObserver: AXObserver?
        let callback: AXObserverCallbackWithInfo = { _, _, _, _, _ in }
        let created = AXObserverCreateWithInfoCallback(getpid(), callback, &createdObserver)
        let observer = try #require(created == .success ? createdObserver : nil)
        let firstElement = AXUIElementCreateApplication(getpid())
        let secondElement = AXUIElementCreateApplication(getpid())
        let first = NativeAddIdentity(
            observer: observer,
            notification: "AXCreated",
            target: .element(firstElement))
        let second = NativeAddIdentity(
            observer: observer,
            notification: "AXCreated",
            target: .element(secondElement))
        #expect((first == second) == CFEqual(firstElement, secondElement))

        let other = NativeAddIdentity(
            observer: observer,
            notification: "AXCreated",
            target: .element(AXUIElementCreateApplication(1)))
        #expect(first != other)
        #expect(first != NativeAddIdentity(
            observer: observer,
            notification: "AXCreated",
            target: .process(getpid())))
    }

    @Test
    func `process scoped timeout retry is not removed by an older late success`() async throws {
        var createdObserver: AXObserver?
        let callback: AXObserverCallbackWithInfo = { _, _, _, _, _ in }
        let created = AXObserverCreateWithInfoCallback(getpid(), callback, &createdObserver)
        let observer = try #require(created == .success ? createdObserver : nil)
        let processIdentifier = getpid()
        let notification = kAXFocusedUIElementChangedNotification as CFString
        let firstRegistration = makeProcessAddRegistration(
            observer: observer,
            pid: processIdentifier,
            notification: notification)
        let retryRegistration = makeProcessAddRegistration(
            observer: observer,
            pid: processIdentifier,
            notification: notification)
        let table = NativeAddAttemptTable()
        let firstToken = table.begin(firstRegistration.addIdentity)
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
                    attemptIsCurrent: table.isCurrent(firstRegistration.addIdentity, firstToken))
                {
                    removed.increment()
                }
            },
            operation: {
                release.wait()
                return .success
            })

        #expect(result == .cannotComplete)
        let retryToken = table.begin(retryRegistration.addIdentity)
        #expect(retryToken != firstToken)
        #expect(table.isCurrent(retryRegistration.addIdentity, retryToken))
        release.signal()
        let deadline = ContinuousClock().now.advanced(by: .seconds(1))
        while !removed.sawLate, ContinuousClock().now < deadline {
            await Task.yield()
        }
        #expect(removed.sawLate)
        #expect(!removed.didRemove)
        #expect(table.isCurrent(retryRegistration.addIdentity, retryToken))
    }

    @Test
    func `retired add identities are not retained`() throws {
        let table = NativeAddAttemptTable()
        let firstIdentity = try #require(makeTestAddIdentity(pid: 21, notification: "AXCreated"))
        let secondIdentity = try #require(makeTestAddIdentity(pid: 23, notification: "AXTitleChanged"))
        let first = table.begin(firstIdentity)
        let second = table.begin(secondIdentity)
        #expect(table.retainedIdentityCount == 2)
        table.retire(firstIdentity, first)
        table.retire(secondIdentity, second)
        #expect(table.retainedIdentityCount == 0)
        let later = table.begin(firstIdentity)
        #expect(later != first)
        #expect(table.retainedIdentityCount == 1)
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

private final nonisolated class LateCountBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = 0

    func store(_ value: Int) {
        self.lock.lock()
        self.stored = value
        self.lock.unlock()
    }

    var value: Int {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.stored
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
