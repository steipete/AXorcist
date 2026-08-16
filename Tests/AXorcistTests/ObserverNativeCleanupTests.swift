import ApplicationServices
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
    func `add attempt identity uses retained object pointers not CFHash`() throws {
        var createdObserver: AXObserver?
        let callback: AXObserverCallbackWithInfo = { _, _, _, _, _ in }
        let created = AXObserverCreateWithInfoCallback(getpid(), callback, &createdObserver)
        let observer = try #require(created == .success ? createdObserver : nil)
        let firstElement = AXUIElementCreateApplication(getpid())
        let secondElement = AXUIElementCreateApplication(getpid())
        let first = NativeAddIdentity(
            observer: observer,
            element: firstElement,
            notification: "AXCreated")
        let second = NativeAddIdentity(
            observer: observer,
            element: secondElement,
            notification: "AXCreated")
        let firstAgain = NativeAddIdentity(
            observer: observer,
            element: firstElement,
            notification: "AXCreated")
        #expect(first != second)
        #expect(first == firstAgain)

        let table = NativeAddAttemptTable()
        let firstToken = table.begin(first)
        _ = table.begin(second)
        #expect(table.isCurrent(first, firstToken))
        #expect(!table.isCurrent(second, firstToken))
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
