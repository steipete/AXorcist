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
