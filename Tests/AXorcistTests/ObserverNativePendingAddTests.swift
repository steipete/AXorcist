import ApplicationServices
import Foundation
import Testing
@testable import AXorcist

@Suite("Observer pending add")
struct ObserverNativePendingAddTests {
    @Test
    func `in-flight pending add refuses a second launch`() {
        #expect(!ObserverNativeWork.shouldLaunchNewAdd(hasInFlightPending: true))
        #expect(ObserverNativeWork.shouldLaunchNewAdd(hasInFlightPending: false))
        #expect(!ObserverNativeWork.canLaunchNativeAdd(hasPendingAdd: true, hasUnconfirmedRemoval: false))
        #expect(!ObserverNativeWork.canLaunchNativeAdd(hasPendingAdd: false, hasUnconfirmedRemoval: true))
        #expect(ObserverNativeWork.canLaunchNativeAdd(hasPendingAdd: false, hasUnconfirmedRemoval: false))
    }

    @Test
    func `in-time success commits without a completion waiter`() {
        #expect(
            ObserverNativeWork.pendingAddDisposition(
                nativeError: .success,
                stillPending: true,
                waiterCount: 0,
                generationMatches: true,
                isLate: false) == .commit)
    }

    @Test
    func `sync join parks a waiter so late success commits`() {
        let completion = NativeAddCompletion()
        #expect(completion.beginSynchronousWait())
        let outcome = ObserverNativeWork.PendingNativeFirstResult(error: .success, timedOut: true)
        #expect(completion.finishNative(with: outcome) == .synchronous)
        #expect(completion.waiterCountAtNativeFinish == 1)
        #expect(
            ObserverNativeWork.pendingAddDisposition(
                nativeError: .success,
                stillPending: true,
                waiterCount: completion.waiterCountAtNativeFinish,
                generationMatches: true,
                isLate: true) == .commit)
        #expect(completion.waitForNativeResult(
            until: ContinuousClock().now.advanced(by: .seconds(1))) == outcome)
    }

    @Test
    func `native result does not wake async joiners before resolution`() async {
        let completion = NativeAddCompletion()
        let returned = PendingAddResultBox()
        let waiter = Task {
            let outcome = await completion.value(timeout: .seconds(30))
            returned.store(outcome.error)
            return outcome
        }
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(5))
        while completion.resolutionWaiterCount == 0, clock.now < deadline {
            await Task.yield()
        }
        #expect(completion.resolutionWaiterCount == 1)
        let native = ObserverNativeWork.PendingNativeFirstResult(error: .success, timedOut: false)

        #expect(completion.finishNative(with: native) == .asynchronous)
        for _ in 0..<10 {
            await Task.yield()
        }
        #expect(returned.value == nil)

        let resolved = ObserverNativeWork.PendingNativeFirstResult(error: .cannotComplete, timedOut: false)
        completion.publishResolved(resolved)
        #expect(await waiter.value == resolved)
    }

    @Test
    func `timed out async joiner no longer authorizes a late commit`() async {
        let completion = NativeAddCompletion()
        let waiter = Task {
            await completion.value(timeout: .milliseconds(20))
        }
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(1))
        while completion.resolutionWaiterCount == 0, clock.now < deadline {
            await Task.yield()
        }
        #expect(completion.finishNative(with: ObserverNativeWork.PendingNativeFirstResult(
            error: .success,
            timedOut: true)) == .asynchronous)

        #expect(await waiter.value.error == .cannotComplete)
        #expect(completion.resolutionWaiterCount == 0)
    }

    @Test
    func `sync deadline atomically hands a later native result to async resolution`() {
        let completion = NativeAddCompletion()
        #expect(completion.beginSynchronousWait())
        let clock = ContinuousClock()

        #expect(completion.waitForNativeResult(until: clock.now) == nil)
        #expect(completion.finishNative(with: ObserverNativeWork.PendingNativeFirstResult(
            error: .success,
            timedOut: true)) == .asynchronous)
    }

    @Test
    func `sync join can claim a native-ready result before async resolution starts`() {
        let completion = NativeAddCompletion()
        let outcome = ObserverNativeWork.PendingNativeFirstResult(error: .success, timedOut: true)
        #expect(completion.finishNative(with: outcome) == .asynchronous)

        #expect(completion.beginSynchronousWait())
        #expect(completion.waitForNativeResult(
            until: ContinuousClock().now.advanced(by: .seconds(1))) == outcome)
        #expect(!completion.beginAsynchronousResolution())
    }

    @Test @MainActor
    func `resolved setup never adopts another process generation`() {
        let center = AXObserverCenter(
            observerSetup: { _, _, _ in .success },
            observerCleanup: { _, _, _ in })
        let registration = AXObserverRegistrationKey(
            subscription: AXNotificationSubscriptionKey(pid: 42, notification: .valueChanged),
            element: Element(AXUIElementCreateApplication(42)),
            scope: .process)
        center.nativeRegistrationStates[registration] = AXObserverCenter.NativeRegistrationState(
            operationID: UUID(),
            processGeneration: 2)
        let completion = NativeAddCompletion()
        completion.publishResolved(ObserverNativeWork.PendingNativeFirstResult(
            error: .success,
            timedOut: false))

        let result = center.registrationSetupResult(
            registration,
            expectedGeneration: 1,
            completion: completion,
            fallbackError: .success)

        #expect(result.error == .cannotComplete)
        #expect(result.state == nil)
    }

    @Test
    func `late success with a waiting joiner commits`() {
        #expect(
            ObserverNativeWork.pendingAddDisposition(
                nativeError: .success,
                stillPending: true,
                waiterCount: 1,
                generationMatches: true,
                isLate: true) == .commit)
    }

    @Test
    func `timeout retry fails then late success is pending removal`() {
        #expect(
            ObserverNativeWork.pendingAddDisposition(
                nativeError: .success,
                stillPending: true,
                waiterCount: 0,
                generationMatches: true,
                isLate: true) == .pendingRemoval)
    }

    @Test
    func `late success after generation mismatch is pending removal`() {
        #expect(
            ObserverNativeWork.pendingAddDisposition(
                nativeError: .success,
                stillPending: true,
                waiterCount: 1,
                generationMatches: false,
                isLate: true) == .pendingRemoval)
        #expect(ObserverNativeWork.shouldResetObserverGeneration(observed: 2, expected: 1))
    }

    @Test
    func `unknown process identity does not reset the observer generation`() {
        #expect(!ObserverNativeWork.shouldResetObserverGeneration(observed: nil, expected: 1))
        #expect(!ObserverNativeWork.shouldResetObserverGeneration(observed: 1, expected: 1))
        #expect(
            ObserverNativeWork.pendingAddDisposition(
                nativeError: .success,
                stillPending: true,
                waiterCount: 1,
                generationMatches: false,
                isLate: true) == .pendingRemoval)
    }

    @Test
    func `failed rollback keeps tracking until absence is confirmed`() {
        #expect(ObserverNativeWork.shouldKeepTrackingRemoval(.cannotComplete))
        #expect(ObserverNativeWork.shouldKeepTrackingRemoval(.failure))
        #expect(!ObserverNativeWork.shouldKeepTrackingRemoval(.success))
        #expect(!ObserverNativeWork.shouldKeepTrackingRemoval(.notificationNotRegistered))
    }

    @Test
    func `runPendingAdd timeout does not finalize until the late native add`() async {
        let release = DispatchSemaphore(value: 0)
        let finished = PendingAddResultBox()
        let first = await ObserverNativeWork.runPendingAdd(
            admission: ObserverNativeWorkerAdmission(),
            timeout: .milliseconds(30),
            operation: {
                release.wait()
                return .success
            },
            onFinished: { error in
                finished.store(error)
            })

        #expect(first.timedOut)
        #expect(first.error == .cannotComplete)
        #expect(finished.value == nil)
        release.signal()
        let deadline = ContinuousClock().now.advanced(by: .seconds(1))
        while finished.value == nil, ContinuousClock().now < deadline {
            await Task.yield()
        }
        #expect(finished.value == .success)
        #expect(
            ObserverNativeWork.pendingAddDisposition(
                nativeError: .success,
                stillPending: true,
                waiterCount: 0,
                generationMatches: true,
                isLate: true) == .pendingRemoval)
    }

    @Test
    func `timeout then refused retry then late success stays owned for rollback`() async {
        let release = DispatchSemaphore(value: 0)
        let finished = PendingAddResultBox()
        let first = await ObserverNativeWork.runPendingAdd(
            admission: ObserverNativeWorkerAdmission(),
            timeout: .milliseconds(30),
            operation: {
                release.wait()
                return .success
            },
            onFinished: { error in
                finished.store(error)
            })
        #expect(first.timedOut)
        #expect(!ObserverNativeWork.shouldLaunchNewAdd(hasInFlightPending: true))
        #expect(
            ObserverNativeWork.pendingAddDisposition(
                nativeError: .success,
                stillPending: true,
                waiterCount: 0,
                generationMatches: true,
                isLate: true) == .pendingRemoval)

        release.signal()
        let deadline = ContinuousClock().now.advanced(by: .seconds(1))
        while finished.value == nil, ContinuousClock().now < deadline {
            await Task.yield()
        }
        #expect(finished.value == .success)
    }

    @Test
    func `late success rollback failure keeps pending until native remove reports`() async {
        let addRelease = DispatchSemaphore(value: 0)
        let removeRelease = DispatchSemaphore(value: 0)
        let addFinished = PendingAddResultBox()
        let removeFinished = PendingAddResultBox()
        let first = await ObserverNativeWork.runPendingAdd(
            admission: ObserverNativeWorkerAdmission(),
            timeout: .milliseconds(30),
            operation: {
                addRelease.wait()
                return .success
            },
            onFinished: { error in
                addFinished.store(error)
            })
        #expect(first.timedOut)
        addRelease.signal()
        let addDeadline = ContinuousClock().now.advanced(by: .seconds(1))
        while addFinished.value == nil, ContinuousClock().now < addDeadline {
            await Task.yield()
        }
        #expect(addFinished.value == .success)
        #expect(
            ObserverNativeWork.pendingAddDisposition(
                nativeError: .success,
                stillPending: true,
                waiterCount: 0,
                generationMatches: true,
                isLate: true) == .pendingRemoval)

        let cleanup = Task {
            await ObserverNativeWork.runPendingCleanup(
                admission: ObserverNativeWorkerAdmission(),
                timeout: .milliseconds(30),
                operation: {
                    removeRelease.wait()
                    return .cannotComplete
                },
                onFinished: { error in
                    removeFinished.store(error)
                })
        }
        try? await Task.sleep(for: .milliseconds(50))
        #expect(removeFinished.value == nil)
        removeRelease.signal()
        await cleanup.value
        let removeDeadline = ContinuousClock().now.advanced(by: .seconds(1))
        while removeFinished.value == nil, ContinuousClock().now < removeDeadline {
            await Task.yield()
        }
        #expect(removeFinished.value == .cannotComplete)
        #expect(ObserverNativeWork.shouldKeepTrackingRemoval(.cannotComplete))
    }
}

private final nonisolated class PendingAddResultBox: @unchecked Sendable {
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
