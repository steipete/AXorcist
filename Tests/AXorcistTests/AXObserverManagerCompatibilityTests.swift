import ApplicationServices
import Foundation
import Testing
@testable import AXorcist

@Suite("AXObserverManager compatibility")
@MainActor
struct AXObserverManagerCompatibilityTests {
    @Test
    func `raw callback identity is preserved and same-key replacement stays logical`() throws {
        let calls = CompatibilityObserverCalls()
        let center = self.makeCenter(calls: calls)
        let manager = AXObserverManager(observationCenter: center)
        let element = Element(AXUIElementCreateApplication(getpid()))
        let observer = try self.makeObserver()
        let userInfo = ["source": "exact"] as CFDictionary
        var firstCallbackCount = 0
        let capture = RawObserverCallbackCapture()

        try manager.addObserver(for: element, notification: .valueChanged) { _, _, _, _ in
            firstCallbackCount += 1
        }
        try manager.addObserver(
            for: element,
            notification: .valueChanged,
            callback: capture.record)
        center.processNotification(AXObserverNotificationEvent(
            observer: observer,
            pid: getpid(),
            notification: .valueChanged,
            notificationString: AXNotification.valueChanged.rawValue as CFString,
            rawElement: element.underlyingElement,
            rawUserInfo: userInfo,
            userInfo: ["source": "exact"]))

        #expect(calls.setupCount == 1)
        #expect(firstCallbackCount == 0)
        #expect(capture.observer === observer)
        #expect(capture.element === element.underlyingElement)
        #expect(capture.notification == AXNotification.valueChanged.rawValue as CFString)
        #expect(capture.userInfo === userInfo)

        try manager.removeObserver(for: element, notification: .valueChanged)
        #expect(calls.cleanupCount == 1)
        #expect(!center.isKeyRegistered(pid: getpid(), notification: .valueChanged))
    }

    @Test
    func `remove all affects only compatibility-manager tokens`() throws {
        let calls = CompatibilityObserverCalls()
        let center = self.makeCenter(calls: calls)
        let manager = AXObserverManager(observationCenter: center)
        let element = Element(AXUIElementCreateApplication(getpid()))
        let unrelated = try center.subscribe(
            pid: getpid(),
            element: element,
            notification: .titleChanged,
            handler: { _, _, _, _ in }).get()
        try manager.addObserver(for: element, notification: .valueChanged) { _, _, _, _ in }

        manager.removeAllObservers()

        #expect(!center.isKeyRegistered(pid: getpid(), notification: .valueChanged))
        #expect(center.isKeyRegistered(pid: getpid(), notification: .titleChanged))
        #expect(calls.cleanupCount == 1)
        try center.unsubscribe(token: unrelated)
        #expect(calls.cleanupCount == 2)
    }

    @Test
    func `native add failures retain the legacy typed error`() {
        let center = AXObserverCenter(
            observerSetup: { _, _, _ in .cannotComplete },
            observerCleanup: { _, _, _ in })
        let manager = AXObserverManager(observationCenter: center)
        let element = Element(AXUIElementCreateApplication(getpid()))

        do {
            try manager.addObserver(for: element, notification: .valueChanged) { _, _, _, _ in }
            Issue.record("Expected the compatibility add to fail")
        } catch let error as AXObserverManager.ObserverError {
            guard case .addNotificationFailed(.cannotComplete) = error else {
                Issue.record("Expected addNotificationFailed(.cannotComplete), got \(error)")
                return
            }
        } catch {
            Issue.record("Expected AXObserverManager.ObserverError, got \(error)")
        }
    }

    @Test
    func `native remove failure is bounded and retains the compatibility registration for retry`() throws {
        let removals = CompatibilityRemovalSequence()
        let generation = UInt64(UInt32(bitPattern: getpid()))
        let center = AXObserverCenter(
            processIdentityProvider: { _ in generation },
            nativeRegistrationWorkProvider: { _, _ in
                ObserverNativeRegistrationWork(
                    add: { .success },
                    remove: removals.next)
            })
        let manager = AXObserverManager(observationCenter: center)
        let element = Element(AXUIElementCreateApplication(getpid()))
        try manager.addObserver(for: element, notification: .valueChanged) { _, _, _, _ in }

        #expect(throws: AXObserverManager.ObserverError.self) {
            try manager.removeObserver(for: element, notification: .valueChanged)
        }
        #expect(center.isKeyRegistered(pid: getpid(), notification: .valueChanged))

        try manager.removeObserver(for: element, notification: .valueChanged)
        #expect(!center.isKeyRegistered(pid: getpid(), notification: .valueChanged))
        #expect(removals.callCount == 2)
    }

    private func makeCenter(calls: CompatibilityObserverCalls) -> AXObserverCenter {
        AXObserverCenter(
            observerSetup: { _, _, _ in
                calls.recordSetup()
                return .success
            },
            observerCleanup: { _, _, _ in
                calls.recordCleanup()
            })
    }

    private func makeObserver() throws -> AXObserver {
        var observer: AXObserver?
        let callback: AXObserverCallbackWithInfo = { _, _, _, _, _ in }
        let error = AXObserverCreateWithInfoCallback(getpid(), callback, &observer)
        guard error == .success, let observer else {
            throw AXObserverManager.ObserverError.couldNotCreateObserver
        }
        return observer
    }
}

private final class CompatibilityObserverCalls {
    private(set) var setupCount = 0
    private(set) var cleanupCount = 0

    func recordSetup() {
        self.setupCount += 1
    }

    func recordCleanup() {
        self.cleanupCount += 1
    }
}

@MainActor
private final class RawObserverCallbackCapture {
    private(set) var observer: AXObserver?
    private(set) var element: AXUIElement?
    private(set) var notification: CFString?
    private(set) var userInfo: CFDictionary?

    func record(
        observer: AXObserver,
        element: AXUIElement,
        notification: CFString,
        userInfo: CFDictionary?)
    {
        self.observer = observer
        self.element = element
        self.notification = notification
        self.userInfo = userInfo
    }
}

private final nonisolated class CompatibilityRemovalSequence: @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0

    func next() -> AXError {
        self.lock.withLock {
            self.calls += 1
            return self.calls == 1 ? .cannotComplete : .success
        }
    }

    var callCount: Int {
        self.lock.withLock { self.calls }
    }
}
