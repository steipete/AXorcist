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
    func `retired add identities are not retained`() {
        let table = NativeAddAttemptTable()
        let firstIdentity = NativeAddIdentity(
            observerBits: 21,
            elementBits: 22,
            notification: "AXCreated")
        let secondIdentity = NativeAddIdentity(
            observerBits: 23,
            elementBits: 24,
            notification: "AXTitleChanged")
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
