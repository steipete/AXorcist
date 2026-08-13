import ApplicationServices
import Darwin
import Foundation
import Testing
@testable import axorc
@testable import AXorcist

@Suite("Observer lifecycle")
@MainActor
struct ObserverLifecycleTests {
    @Test
    func `application PID uses the native element identity`() {
        let processIdentifier = getpid()
        let element = Element(AXUIElementCreateApplication(processIdentifier))

        #expect(element.pid() == processIdentifier)
    }

    @Test
    func `CLI recognizes the current observe success response`() {
        #expect(CLIFrontend.responseSucceeded("{\"command_id\":\"observe\",\"status\":\"success\"}"))
        #expect(CLIFrontend.responseSucceeded("{\"command_id\":\"observe\",\"status\":\"error\"}") == false)
    }

    @Test
    func `observe and stop use the same registry without clearing unrelated subscriptions`() throws {
        let registry = RecordingObservationRegistry()
        let target = Element(AXUIElementCreateSystemWide())
        let unrelatedToken = try registry.subscribe(
            pid: 7,
            element: nil,
            notification: .titleChanged)
        { _, _, _, _ in }.get()
        var resolvedRole: String?
        let axorcist = AXorcist(
            observationRegistry: registry,
            observationTargetResolver: { _, locator, _ in
                resolvedRole = locator.criteria.first?.value
                return (target, nil)
            })
        let observe = ObserveCommand(
            appIdentifier: "fixture",
            locator: Locator(criteria: [
                Criterion(attribute: "AXRole", value: AXRoleNames.kAXButtonRole, matchType: .exact),
            ]),
            notifications: [AXNotification.valueChanged.rawValue],
            notificationName: .valueChanged)

        let observeResponse = axorcist.runCommand(AXCommandEnvelope(
            commandID: "observe-owner",
            command: .observe(observe)))

        #expect(observeResponse.status == "success")
        #expect(resolvedRole == AXRoleNames.kAXButtonRole)
        #expect(registry.activeSubscriptionCount == 2)

        CommandExecutor.stopObservations(axorcist: axorcist)

        #expect(registry.unsubscribeCallCount == 1)
        #expect(registry.activeSubscriptionCount == 1)
        #expect(registry.contains(unrelatedToken))
    }

    @Test
    func `callback can unsubscribe itself during dispatch`() throws {
        var cleanupCount = 0
        var cleanedElement: Element?
        let center = AXObserverCenter(
            observerSetup: { _, _, _ in .success },
            observerCleanup: { _, element, _ in
                cleanupCount += 1
                cleanedElement = element
            })
        var callbackCount = 0
        var token: SubscriptionToken?
        let observedElement = Element(AXUIElementCreateApplication(42))
        let subscription = center.subscribe(
            pid: 42,
            element: observedElement,
            notification: .valueChanged)
        { _, _, _, _ in
            callbackCount += 1
            if let token {
                try? center.unsubscribe(token: token)
            }
        }
        token = try subscription.get()

        center.processNotification(
            pid: 42,
            notification: .valueChanged,
            rawElement: observedElement.underlyingElement,
            nsUserInfo: nil)

        #expect(callbackCount == 1)
        #expect(cleanupCount == 1)
        #expect(cleanedElement == observedElement)
        #expect(center.isKeyRegistered(pid: 42, notification: .valueChanged) == false)
    }

    @Test
    func `element registrations dispatch only to their exact target`() {
        let store = AXObserverSubscriptionStore()
        let subscription = AXNotificationSubscriptionKey(pid: 91, notification: .valueChanged)
        let firstElement = Element(AXUIElementCreateApplication(91))
        let secondElement = Element(AXUIElementCreateApplication(92))
        var firstCount = 0
        var secondCount = 0
        var processCount = 0
        _ = store.add(
            registration: AXObserverRegistrationKey(
                subscription: subscription,
                element: firstElement,
                scope: .element))
        { _, _, _, _ in firstCount += 1 }
        _ = store.add(
            registration: AXObserverRegistrationKey(
                subscription: subscription,
                element: secondElement,
                scope: .element))
        { _, _, _, _ in secondCount += 1 }
        _ = store.add(
            registration: AXObserverRegistrationKey(
                subscription: subscription,
                element: firstElement,
                scope: .process))
        { _, _, _, _ in processCount += 1 }

        store.dispatch(
            pid: 91,
            notification: .valueChanged,
            rawElement: firstElement.underlyingElement,
            userInfo: nil)

        #expect(firstCount == 1)
        #expect(secondCount == 0)
        #expect(processCount == 1)
    }

    @Test
    func `shared registration cleans up its exact target after the final token`() throws {
        var setupCount = 0
        var cleanedElement: Element?
        let center = AXObserverCenter(
            observerSetup: { _, _, _ in
                setupCount += 1
                return .success
            },
            observerCleanup: { _, element, _ in cleanedElement = element })
        let observedElement = Element(AXUIElementCreateApplication(73))
        let first = try center.subscribe(
            pid: 73,
            element: nil,
            notification: .valueChanged)
        { _, _, _, _ in }.get()
        let second = try center.subscribe(
            pid: 73,
            element: observedElement,
            notification: .valueChanged)
        { _, _, _, _ in }.get()

        #expect(setupCount == 1)
        try center.unsubscribe(token: first)
        #expect(cleanedElement == nil)
        #expect(center.isKeyRegistered(pid: 73, notification: .valueChanged))

        try center.unsubscribe(token: second)
        #expect(cleanedElement == observedElement)
        #expect(center.isKeyRegistered(pid: 73, notification: .valueChanged) == false)
    }

    @Test
    func `watcher deinit unregisters its token`() async throws {
        let registry = RecordingObservationRegistry()
        var watcher: NotificationWatcher? = NotificationWatcher(
            forPID: getpid(),
            notification: .valueChanged,
            registry: registry)
        { _, _, _, _ in }
        try watcher?.start()
        #expect(registry.activeSubscriptionCount == 1)

        weak let weakWatcher = watcher
        watcher = nil
        #expect(weakWatcher == nil)
        for _ in 0..<10 where registry.unsubscribeCallCount == 0 {
            await Task.yield()
        }

        #expect(registry.unsubscribeCallCount == 1)
        #expect(registry.activeSubscriptionCount == 0)
    }

    @Test
    func `AXorcist deinit unregisters its owned tokens`() async {
        let registry = RecordingObservationRegistry()
        let target = Element(AXUIElementCreateSystemWide())
        var axorcist: AXorcist? = AXorcist(
            observationRegistry: registry,
            observationTargetResolver: { _, _, _ in (target, nil) })
        let observe = ObserveCommand(
            appIdentifier: "fixture",
            notifications: [AXNotification.valueChanged.rawValue],
            notificationName: .valueChanged)
        _ = axorcist?.runCommand(AXCommandEnvelope(commandID: "deinit-owner", command: .observe(observe)))
        #expect(registry.activeSubscriptionCount == 1)

        weak let weakAXorcist = axorcist
        axorcist = nil
        #expect(weakAXorcist == nil)
        for _ in 0..<10 where registry.unsubscribeCallCount == 0 {
            await Task.yield()
        }

        #expect(registry.unsubscribeCallCount == 1)
        #expect(registry.activeSubscriptionCount == 0)
    }
}

@MainActor
private final class RecordingObservationRegistry: AXObservationRegistry {
    private var subscriptions: [SubscriptionToken: AXNotificationSubscriptionHandler] = [:]

    private(set) var unsubscribeCallCount = 0

    var activeSubscriptionCount: Int {
        self.subscriptions.count
    }

    func contains(_ token: SubscriptionToken) -> Bool {
        self.subscriptions[token] != nil
    }

    func subscribe(
        pid _: pid_t?,
        element _: Element?,
        notification _: AXNotification,
        handler: @escaping AXNotificationSubscriptionHandler) -> Result<SubscriptionToken, AccessibilityError>
    {
        let token = SubscriptionToken(id: UUID())
        self.subscriptions[token] = handler
        return .success(token)
    }

    func unsubscribe(token: SubscriptionToken) throws {
        self.unsubscribeCallCount += 1
        guard self.subscriptions.removeValue(forKey: token) != nil else {
            throw AccessibilityError.tokenNotFound(tokenId: token.id)
        }
    }
}
