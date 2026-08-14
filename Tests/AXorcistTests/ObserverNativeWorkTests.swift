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
}
