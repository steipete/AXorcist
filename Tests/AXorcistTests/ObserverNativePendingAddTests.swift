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
        let completion = NativeRemovalCompletion()
        #expect(completion.waiterCount == 0)
        completion.parkWaiter()
        #expect(completion.waiterCount == 1)
        #expect(
            ObserverNativeWork.pendingAddDisposition(
                nativeError: .success,
                stillPending: true,
                waiterCount: completion.waiterCount,
                generationMatches: true,
                isLate: true) == .commit)
        completion.unparkWaiter()
        #expect(completion.waiterCount == 0)
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
