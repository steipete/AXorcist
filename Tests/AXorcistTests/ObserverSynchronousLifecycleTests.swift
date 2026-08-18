import ApplicationServices
import Foundation
import Testing
@testable import AXorcist

@Suite("Synchronous observer lifecycle", .serialized)
@MainActor
struct ObserverSynchronousLifecycleTests {
    @Test
    func `synchronous subscribe fails closed while a late add remains owned for rollback`() async {
        let addRelease = DispatchSemaphore(value: 0)
        let calls = ObserverWorkCalls()
        let center = self.makeCenter(
            add: {
                calls.recordAdd()
                addRelease.wait()
                return .success
            },
            remove: {
                calls.recordRemove()
                return .success
            })
        let clock = ContinuousClock()
        let started = clock.now

        let result = center.subscribe(
            pid: getpid(),
            element: Element(AXUIElementCreateSystemWide()),
            notification: .valueChanged,
            handler: { _, _, _, _ in })

        #expect(started.duration(to: clock.now) < .seconds(3))
        guard case .failure = result else {
            Issue.record("Expected a bounded synchronous registration failure")
            addRelease.signal()
            return
        }
        #expect(calls.addCount == 1)
        #expect(center.pendingRegistrations.count == 1)
        #expect(center.registeredKeys.isEmpty)

        addRelease.signal()
        await self.waitForPendingWorkToDrain(center)

        #expect(calls.removeCount == 1)
        #expect(center.pendingRegistrations.isEmpty)
        #expect(center.pendingRemovals.isEmpty)
        #expect(center.nativeRegistrationStates.isEmpty)
    }

    @Test
    func `late add commits while the synchronous waiter is still live`() async throws {
        let addRelease = DispatchSemaphore(value: 0)
        let calls = ObserverWorkCalls()
        let center = self.makeCenter(
            add: {
                calls.recordAdd()
                addRelease.wait()
                return .success
            },
            remove: {
                calls.recordRemove()
                return .success
            })
        Task.detached {
            try? await Task.sleep(for: .milliseconds(650))
            addRelease.signal()
        }
        let clock = ContinuousClock()
        let started = clock.now

        let token = try center.subscribe(
            pid: getpid(),
            element: Element(AXUIElementCreateSystemWide()),
            notification: .valueChanged,
            handler: { _, _, _, _ in }).get()

        #expect(started.duration(to: clock.now) < .seconds(2))
        #expect(calls.addCount == 1)
        #expect(center.nativeRegistrationStates.count == 1)
        try center.unsubscribe(token: token)
        await self.waitForPendingWorkToDrain(center)
        #expect(calls.removeCount == 1)
    }

    @Test
    func `synchronous retry joins one in-flight add instead of launching a duplicate`() async throws {
        let addRelease = DispatchSemaphore(value: 0)
        let calls = ObserverWorkCalls()
        let center = self.makeCenter(
            add: {
                calls.recordAdd()
                addRelease.wait()
                return .success
            },
            remove: {
                calls.recordRemove()
                return .success
            })
        let element = Element(AXUIElementCreateSystemWide())
        let first = center.subscribe(
            pid: getpid(),
            element: element,
            notification: .valueChanged,
            handler: { _, _, _, _ in })
        guard case .failure = first else {
            Issue.record("Expected the first bounded join to time out")
            addRelease.signal()
            return
        }
        Task.detached {
            try? await Task.sleep(for: .milliseconds(100))
            addRelease.signal()
        }

        let token = try center.subscribe(
            pid: getpid(),
            element: element,
            notification: .valueChanged,
            handler: { _, _, _, _ in }).get()

        #expect(calls.addCount == 1)
        try center.unsubscribe(token: token)
        await self.waitForPendingWorkToDrain(center)
        #expect(calls.removeCount == 1)
    }

    @Test
    func `synchronous unsubscribe returns while native removal remains pending`() async throws {
        let removeRelease = DispatchSemaphore(value: 0)
        let calls = ObserverWorkCalls()
        let center = self.makeCenter(
            add: {
                calls.recordAdd()
                return .success
            },
            remove: {
                calls.recordRemove()
                if calls.removeCount == 1 {
                    removeRelease.wait()
                }
                return .success
            })
        let element = Element(AXUIElementCreateSystemWide())
        let token = try center.subscribe(
            pid: getpid(),
            element: element,
            notification: .valueChanged,
            handler: { _, _, _, _ in }).get()
        let clock = ContinuousClock()
        let started = clock.now

        try center.unsubscribe(token: token)

        #expect(started.duration(to: clock.now) < .seconds(1))
        #expect(center.pendingRemovals.count == 1)
        let refused = center.subscribe(
            pid: getpid(),
            element: element,
            notification: .valueChanged,
            handler: { _, _, _, _ in })
        guard case .failure = refused else {
            Issue.record("Expected resubscribe to refuse unconfirmed removal")
            removeRelease.signal()
            return
        }
        #expect(calls.addCount == 1)
        removeRelease.signal()
        await self.waitForPendingWorkToDrain(center)
        #expect(calls.removeCount == 1)
        #expect(center.nativeRegistrationStates.isEmpty)

        let replacement = try center.subscribe(
            pid: getpid(),
            element: element,
            notification: .valueChanged,
            handler: { _, _, _, _ in }).get()
        #expect(calls.addCount == 2)
        try center.unsubscribe(token: replacement)
        await self.waitForPendingWorkToDrain(center)
        #expect(calls.removeCount == 2)
    }

    private func makeCenter(
        add: @escaping @Sendable () -> AXError,
        remove: @escaping @Sendable () -> AXError) -> AXObserverCenter
    {
        let generation = UInt64(UInt32(bitPattern: getpid()))
        return AXObserverCenter(
            processIdentityProvider: { _ in generation },
            nativeRegistrationWorkProvider: { _, _ in
                ObserverNativeRegistrationWork(add: add, remove: remove)
            })
    }

    private func waitForPendingWorkToDrain(_ center: AXObserverCenter) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(10))
        while !center.pendingRegistrations.isEmpty || !center.pendingRemovals.isEmpty,
              clock.now < deadline
        {
            await Task.yield()
        }
    }
}

private final nonisolated class ObserverWorkCalls: @unchecked Sendable {
    private let lock = NSLock()
    private var adds = 0
    private var removes = 0

    func recordAdd() {
        self.lock.withLock { self.adds += 1 }
    }

    func recordRemove() {
        self.lock.withLock { self.removes += 1 }
    }

    var addCount: Int {
        self.lock.withLock { self.adds }
    }

    var removeCount: Int {
        self.lock.withLock { self.removes }
    }
}
