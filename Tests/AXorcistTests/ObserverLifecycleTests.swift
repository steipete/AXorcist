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
    func `PID zero cannot create a native global AX observer`() {
        var observer: AXObserver?
        let callback: AXObserverCallbackWithInfo = { _, _, _, _, _ in }

        let error = AXObserverCreateWithInfoCallback(0, callback, &observer)

        #expect(error != .success)
        #expect(observer == nil)
    }

    @Test
    func `native process identity can inspect root launchd without BSD info privilege`() throws {
        let firstIdentity = try #require(AXObserverCenter.nativeProcessUniqueIdentity(1))
        let secondIdentity = try #require(AXObserverCenter.nativeProcessUniqueIdentity(1))

        #expect(firstIdentity == secondIdentity)
    }

    @Test
    func `observer center rejects PID zero before native setup`() {
        var setupCalled = false
        let center = AXObserverCenter(
            observerSetup: { _, _, _ in
                setupCalled = true
                return .success
            },
            observerCleanup: { _, _, _ in })

        let result = center.subscribe(pid: 0, notification: .focusedUIElementChanged) { _, _, _, _ in }

        if case .failure = result {
            #expect(!setupCalled)
        } else {
            Issue.record("Expected PID zero to be refused")
        }
    }

    @Test
    func `observer center subscribe method reference remains unambiguous`() {
        typealias Subscribe = (
            pid_t?,
            Element?,
            AXNotification,
            @escaping AXNotificationSubscriptionHandler) -> Result<SubscriptionToken, AccessibilityError>
        let center = AXObserverCenter(
            observerSetup: { _, _, _ in .success },
            observerCleanup: { _, _, _ in })
        let subscribe: Subscribe = center.subscribe

        let result = subscribe(nil, nil, .focusedUIElementChanged) { _, _, _, _ in }

        if case .failure = result {} else {
            Issue.record("Expected the source-compatible nil PID call to fail explicitly")
        }
    }

    @Test
    func `observer center resets shared registrations when a PID generation changes`() throws {
        let processGeneration = ProcessGenerationBox(100)
        var setupCount = 0
        let center = AXObserverCenter(
            observerSetup: { _, _, _ in
                setupCount += 1
                return .success
            },
            observerCleanup: { _, _, _ in },
            processIdentityProvider: { _ in processGeneration.value })
        let first = try center.subscribe(pid: 42, notification: .focusedUIElementChanged) { _, _, _, _ in }.get()
        let second = try center.subscribe(pid: 42, notification: .focusedUIElementChanged) { _, _, _, _ in }.get()
        #expect(setupCount == 1)

        processGeneration.value = 101
        let replacement = try center.subscribe(
            pid: 42,
            notification: .focusedUIElementChanged)
        { _, _, _, _ in }.get()

        #expect(setupCount == 2)
        #expect(throws: AccessibilityError.self) {
            try center.unsubscribe(token: first)
        }
        #expect(throws: AccessibilityError.self) {
            try center.unsubscribe(token: second)
        }
        try center.unsubscribe(token: replacement)
    }

    @Test
    func `unknown process generation refuses setup without purging existing subscriptions`() throws {
        let processGeneration = ProcessGenerationBox(100)
        var setupCount = 0
        let center = AXObserverCenter(
            observerSetup: { _, _, _ in
                setupCount += 1
                return .success
            },
            observerCleanup: { _, _, _ in },
            processIdentityProvider: { _ in processGeneration.value })
        let existing = try center.subscribe(
            pid: 42,
            notification: .focusedUIElementChanged)
        { _, _, _, _ in }.get()

        processGeneration.value = nil
        let unavailable = center.subscribe(pid: 42, notification: .titleChanged) { _, _, _, _ in }

        if case .failure = unavailable {} else {
            Issue.record("Expected unavailable process identity to refuse setup")
        }
        #expect(setupCount == 1)
        #expect(center.isKeyRegistered(pid: 42, notification: .focusedUIElementChanged))
        try center.unsubscribe(token: existing)
    }

    @Test
    func `observer creation refuses a process generation change during setup`() {
        let processGenerations = ProcessGenerationSequence([100, 101])
        var setupCount = 0
        let center = AXObserverCenter(
            observerSetup: { _, _, _ in
                setupCount += 1
                return .success
            },
            observerCleanup: { _, _, _ in },
            processIdentityProvider: { _ in processGenerations.next() })

        let result = center.subscribe(pid: 42, notification: .focusedUIElementChanged) { _, _, _, _ in }

        if case .failure = result {} else {
            Issue.record("Expected a mid-setup generation change to refuse the observer")
        }
        #expect(setupCount == 1)
        #expect(!center.isKeyRegistered(pid: 42, notification: .focusedUIElementChanged))
    }

    @Test
    func `post-setup generation change purges shared stale registrations`() throws {
        let processGenerations = ProcessGenerationSequence([100, 100, 100, 100, 101])
        var setupCount = 0
        let center = AXObserverCenter(
            observerSetup: { _, _, _ in
                setupCount += 1
                return .success
            },
            observerCleanup: { _, _, _ in },
            processIdentityProvider: { _ in processGenerations.next() })
        let first = try center.subscribe(pid: 42, notification: .focusedUIElementChanged) { _, _, _, _ in }.get()
        let second = try center.subscribe(pid: 42, notification: .focusedUIElementChanged) { _, _, _, _ in }.get()

        let replacement = center.subscribe(pid: 42, notification: .titleChanged) { _, _, _, _ in }

        if case .failure = replacement {} else {
            Issue.record("Expected post-setup generation drift to refuse registration")
        }
        #expect(setupCount == 2)
        #expect(!center.isKeyRegistered(pid: 42, notification: .focusedUIElementChanged))
        #expect(throws: AccessibilityError.self) {
            try center.unsubscribe(token: first)
        }
        #expect(throws: AccessibilityError.self) {
            try center.unsubscribe(token: second)
        }
    }

    @Test
    func `failed setup still purges a confirmed stale generation`() throws {
        let processGenerations = ProcessGenerationSequence([100, 100, 100, 100, 101])
        let center = AXObserverCenter(
            observerSetup: { _, _, notification in
                notification == .titleChanged ? .cannotComplete : .success
            },
            observerCleanup: { _, _, _ in },
            processIdentityProvider: { _ in processGenerations.next() })
        let first = try center.subscribe(pid: 42, notification: .focusedUIElementChanged) { _, _, _, _ in }.get()
        let second = try center.subscribe(pid: 42, notification: .focusedUIElementChanged) { _, _, _, _ in }.get()

        let replacement = center.subscribe(pid: 42, notification: .titleChanged) { _, _, _, _ in }

        if case .failure = replacement {} else {
            Issue.record("Expected failed setup with generation drift to refuse registration")
        }
        #expect(!center.isKeyRegistered(pid: 42, notification: .focusedUIElementChanged))
        #expect(throws: AccessibilityError.self) {
            try center.unsubscribe(token: first)
        }
        #expect(throws: AccessibilityError.self) {
            try center.unsubscribe(token: second)
        }
    }

    @Test
    func `CLI recognizes the current observe success response`() {
        #expect(CLIFrontend.responseSucceeded("{\"command_id\":\"observe\",\"status\":\"success\"}"))
        #expect(CLIFrontend.responseSucceeded("{\"command_id\":\"observe\",\"status\":\"error\"}") == false)
    }

    @Test
    func `observe and stop use the same registry without clearing unrelated subscriptions`() throws {
        let registry = RecordingObservationRegistry()
        let target = Element(AXUIElementCreateApplication(getpid()))
        let unrelatedToken = try registry.subscribeProcess(
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
    func `application observation derives its PID when the caller omits it`() throws {
        let registry = RecordingObservationRegistry()
        let target = Element(AXUIElementCreateApplication(getpid()))
        let axorcist = AXorcist(
            observationRegistry: registry,
            observationTargetResolver: { _, _, _ in (target, nil) })

        _ = try axorcist.subscribeToObservation(
            pid: nil,
            element: target,
            notification: .valueChanged)
        { _, _, _, _ in }.get()

        #expect(registry.subscribedProcessIdentifiers == [getpid()])
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
    func `process registration identity does not compare accessibility elements`() {
        let subscription = AXNotificationSubscriptionKey(pid: 91, notification: .valueChanged)
        let firstElement = Element(AXUIElementCreateApplication(91))
        let unrelatedElement = Element(AXUIElementCreateApplication(92))
        let first = AXObserverRegistrationKey(
            subscription: subscription,
            element: firstElement,
            scope: .process)
        let second = AXObserverRegistrationKey(
            subscription: subscription,
            element: unrelatedElement,
            scope: .process)

        #expect(first == second)
        #expect(Set([first, second]).count == 1)
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

        let weakWatcher = WeakReference(watcher)
        watcher = nil
        #expect(weakWatcher.value == nil)
        for _ in 0..<10 where registry.unsubscribeCallCount == 0 {
            await Task.yield()
        }

        #expect(registry.unsubscribeCallCount == 1)
        #expect(registry.activeSubscriptionCount == 0)
    }

    @Test
    func `process watcher can restart immediately after stopping`() throws {
        var setupCount = 0
        var cleanupCount = 0
        let center = AXObserverCenter(
            observerSetup: { _, _, _ in
                setupCount += 1
                return .success
            },
            observerCleanup: { _, _, _ in cleanupCount += 1 })
        let watcher = NotificationWatcher(
            forPID: 42,
            notification: .valueChanged,
            registry: center,
            handler: { _, _, _, _ in })

        try watcher.start()
        watcher.stop()
        try watcher.start()

        #expect(watcher.isActive)
        #expect(setupCount == 2)
        #expect(cleanupCount == 1)
        watcher.stop()
    }
}

@MainActor
extension ObserverLifecycleTests {
    @Test
    func `global watcher fans out by PID and follows native application lifecycle`() async throws {
        let registry = RecordingObservationRegistry()
        let applicationMonitor = RecordingGlobalApplicationMonitor(runningProcessIdentifiers: [42, 41])
        let watcher = NotificationWatcher(
            globalNotification: .focusedUIElementChanged,
            registry: registry,
            applicationMonitor: applicationMonitor)
        { _, _, _, _ in }

        try watcher.start()
        for _ in 0..<20 where registry.activeProcessIdentifiers.count < 2 {
            await Task.yield()
        }

        #expect(watcher.isActive)
        #expect(registry.subscribedProcessIdentifiers.sorted() == [41, 42])
        #expect(!registry.subscribedProcessIdentifiers.contains(0))

        applicationMonitor.launch(processIdentifier: 43)
        applicationMonitor.launch(processIdentifier: 43)
        for _ in 0..<20 where !registry.activeProcessIdentifiers.contains(43) {
            await Task.yield()
        }
        #expect(registry.subscribedProcessIdentifiers.sorted() == [41, 42, 43])

        applicationMonitor.terminate(processIdentifier: 42)
        #expect(registry.activeProcessIdentifiers == [41, 43])

        watcher.stop()
        #expect(!watcher.isActive)
        #expect(registry.activeProcessIdentifiers.isEmpty)
        #expect(applicationMonitor.stopCount == 1)
    }

    @Test
    func `global watcher retries a transient launched application failure`() async throws {
        let registry = RecordingObservationRegistry(remainingFailureCounts: [42: 1])
        let applicationMonitor = RecordingGlobalApplicationMonitor(runningProcessIdentifiers: [41])
        let watcher = NotificationWatcher(
            globalNotification: .focusedUIElementChanged,
            registry: registry,
            applicationMonitor: applicationMonitor,
            retrySleep: { _ in },
            handler: { _, _, _, _ in })
        try watcher.start()

        applicationMonitor.launch(processIdentifier: 42)
        for _ in 0..<20 where !registry.activeProcessIdentifiers.contains(42) {
            await Task.yield()
        }

        #expect(registry.attemptCount(for: 42) == 2)
        #expect(registry.activeProcessIdentifiers.contains(42))
        watcher.stop()
    }

    @Test
    func `slow application readiness triggers registration before fallback retry`() async throws {
        let registry = RecordingObservationRegistry(remainingFailureCounts: [42: 1])
        let applicationMonitor = RecordingGlobalApplicationMonitor(runningProcessIdentifiers: [41])
        let watcher = NotificationWatcher(
            globalNotification: .focusedUIElementChanged,
            registry: registry,
            applicationMonitor: applicationMonitor,
            retrySleep: { _ in try await Task.sleep(for: .seconds(60)) },
            handler: { _, _, _, _ in })
        try watcher.start()

        applicationMonitor.launch(processIdentifier: 42)
        applicationMonitor.ready(processIdentifier: 42)
        for _ in 0..<10 where !registry.activeProcessIdentifiers.contains(42) {
            await Task.yield()
        }

        #expect(registry.attemptCount(for: 42) == 2)
        #expect(registry.activeProcessIdentifiers.contains(42))
        watcher.stop()
    }

    @Test
    func `failed initial application waits for its first backoff`() async throws {
        let registry = RecordingObservationRegistry(failingProcessIdentifiers: [42])
        let applicationMonitor = RecordingGlobalApplicationMonitor(runningProcessIdentifiers: [41, 42])
        let watcher = NotificationWatcher(
            globalNotification: .focusedUIElementChanged,
            registry: registry,
            applicationMonitor: applicationMonitor,
            retrySleep: { _ in try await Task.sleep(for: .seconds(60)) },
            handler: { _, _, _, _ in })

        try watcher.start()
        for _ in 0..<20 where registry.attemptCount(for: 41) == 0 || registry.attemptCount(for: 42) == 0 {
            await Task.yield()
        }

        #expect(registry.attemptCount(for: 41) == 1)
        #expect(registry.attemptCount(for: 42) == 1)
        watcher.stop()
    }

    @Test
    func `global observer retry schedule spans slow application startup`() {
        #expect(AXGlobalObserverRetryPolicy.delays == [.milliseconds(500), .seconds(2), .seconds(8)])
        #expect(AXGlobalObserverRetryPolicy.maximumAttempts == 3)
    }

    @Test
    func `global watcher bounds persistent launched application retries`() async throws {
        let registry = RecordingObservationRegistry(failingProcessIdentifiers: [42])
        let applicationMonitor = RecordingGlobalApplicationMonitor(runningProcessIdentifiers: [41])
        let watcher = NotificationWatcher(
            globalNotification: .focusedUIElementChanged,
            registry: registry,
            applicationMonitor: applicationMonitor,
            retrySleep: { _ in },
            handler: { _, _, _, _ in })
        try watcher.start()

        applicationMonitor.launch(processIdentifier: 42)
        for _ in 0..<50 where registry.attemptCount(for: 42) < 4 {
            await Task.yield()
        }
        let boundedAttemptCount = registry.attemptCount(for: 42)
        for _ in 0..<10 {
            await Task.yield()
        }

        #expect(boundedAttemptCount == 4)
        #expect(registry.attemptCount(for: 42) == boundedAttemptCount)
        #expect(!registry.activeProcessIdentifiers.contains(42))
        watcher.stop()
    }

    @Test
    func `termination cancels retry before a replacement reuses the PID`() async throws {
        let registry = RecordingObservationRegistry(remainingFailureCounts: [42: 1])
        let applicationMonitor = RecordingGlobalApplicationMonitor(runningProcessIdentifiers: [41])
        let watcher = NotificationWatcher(
            globalNotification: .focusedUIElementChanged,
            registry: registry,
            applicationMonitor: applicationMonitor,
            retrySleep: { _ in try await Task.sleep(for: .seconds(60)) },
            handler: { _, _, _, _ in })
        try watcher.start()

        applicationMonitor.launch(processIdentifier: 42)
        applicationMonitor.terminate(processIdentifier: 42)
        applicationMonitor.launch(processIdentifier: 42)
        for _ in 0..<10 {
            await Task.yield()
        }

        #expect(registry.attemptCount(for: 42) == 2)
        #expect(registry.activeProcessIdentifiers.contains(42))
        watcher.stop()
    }

    @Test
    func `watcher deinit cancels a sleeping global registration retry`() async throws {
        let registry = RecordingObservationRegistry(remainingFailureCounts: [42: 1])
        let applicationMonitor = RecordingGlobalApplicationMonitor(runningProcessIdentifiers: [41])
        var watcher: NotificationWatcher? = NotificationWatcher(
            globalNotification: .focusedUIElementChanged,
            registry: registry,
            applicationMonitor: applicationMonitor,
            retrySleep: { _ in try await Task.sleep(for: .seconds(60)) },
            handler: { _, _, _, _ in })
        try watcher?.start()
        applicationMonitor.launch(processIdentifier: 42)

        let weakWatcher = WeakReference(watcher)
        watcher = nil
        for _ in 0..<20 where applicationMonitor.stopCount == 0 {
            await Task.yield()
        }

        #expect(weakWatcher.value == nil)
        #expect(applicationMonitor.stopCount == 1)
        #expect(registry.attemptCount(for: 42) == 1)
        #expect(registry.activeProcessIdentifiers.isEmpty)
    }

    @Test
    func `global watcher remains active when every current application rejects registration`() async throws {
        let registry = RecordingObservationRegistry(failingProcessIdentifiers: [41, 42])
        let applicationMonitor = RecordingGlobalApplicationMonitor(runningProcessIdentifiers: [41, 42])
        let watcher = NotificationWatcher(
            globalNotification: .focusedUIElementChanged,
            registry: registry,
            applicationMonitor: applicationMonitor,
            retrySleep: { _ in },
            handler: { _, _, _, _ in })

        try watcher.start()
        for _ in 0..<100 where registry.attemptCount(for: 41) < 4 || registry.attemptCount(for: 42) < 4 {
            await Task.yield()
        }

        #expect(watcher.isActive)
        #expect(registry.activeProcessIdentifiers.isEmpty)
        #expect(registry.attemptCount(for: 41) == 4)
        #expect(registry.attemptCount(for: 42) == 4)
        watcher.stop()
        #expect(applicationMonitor.stopCount == 1)
    }

    @Test
    func `global watcher startup does not await a wedged application registration`() async throws {
        let registry = SuspendingObservationRegistry()
        let applicationMonitor = RecordingGlobalApplicationMonitor(runningProcessIdentifiers: [41, 42])
        let watcher = NotificationWatcher(
            globalNotification: .focusedUIElementChanged,
            registry: registry,
            applicationMonitor: applicationMonitor,
            handler: { _, _, _, _ in })

        try watcher.start()
        #expect(watcher.isActive)
        for _ in 0..<20 where registry.pendingProcessIdentifiers.isEmpty ||
            !registry.activeProcessIdentifiers.contains(41)
        {
            await Task.yield()
        }
        #expect(registry.pendingProcessIdentifiers == [42])
        #expect(registry.activeProcessIdentifiers == [41])

        watcher.stop()
        #expect(!watcher.isActive)
        #expect(applicationMonitor.stopCount == 1)

        registry.resume(processIdentifier: 42)
        for _ in 0..<20 where registry.unsubscribeCallCount < 2 {
            await Task.yield()
        }
        #expect(registry.unsubscribeCallCount == 2)
        #expect(registry.activeProcessIdentifiers.isEmpty)
    }

    @Test
    func `global watcher restart keeps only the replacement suspended registration`() async throws {
        let registry = SuspendingObservationRegistry()
        let applicationMonitor = RecordingGlobalApplicationMonitor(runningProcessIdentifiers: [42])
        let watcher = NotificationWatcher(
            globalNotification: .focusedUIElementChanged,
            registry: registry,
            applicationMonitor: applicationMonitor,
            handler: { _, _, _, _ in })

        try watcher.start()
        for _ in 0..<20 where registry.pendingCount(for: 42) < 1 {
            await Task.yield()
        }
        watcher.stop()
        try watcher.start()
        for _ in 0..<20 where registry.pendingCount(for: 42) < 2 {
            await Task.yield()
        }

        registry.resume(processIdentifier: 42)
        for _ in 0..<20 where registry.unsubscribeCallCount == 0 {
            await Task.yield()
        }
        registry.resume(processIdentifier: 42)
        for _ in 0..<20 where registry.activeProcessIdentifiers.isEmpty {
            await Task.yield()
        }

        #expect(watcher.isActive)
        #expect(registry.unsubscribeCallCount == 1)
        #expect(registry.activeProcessIdentifiers == [42])
        watcher.stop()
        #expect(registry.activeProcessIdentifiers.isEmpty)
    }

    @Test
    func `AXorcist deinit unregisters its owned tokens`() async {
        let registry = RecordingObservationRegistry()
        let target = Element(AXUIElementCreateApplication(getpid()))
        var axorcist: AXorcist? = AXorcist(
            observationRegistry: registry,
            observationTargetResolver: { _, _, _ in (target, nil) })
        let observe = ObserveCommand(
            appIdentifier: "fixture",
            notifications: [AXNotification.valueChanged.rawValue],
            notificationName: .valueChanged)
        _ = axorcist?.runCommand(AXCommandEnvelope(commandID: "deinit-owner", command: .observe(observe)))
        #expect(registry.activeSubscriptionCount == 1)

        let weakAXorcist = WeakReference(axorcist)
        axorcist = nil
        #expect(weakAXorcist.value == nil)
        for _ in 0..<10 where registry.unsubscribeCallCount == 0 {
            await Task.yield()
        }

        #expect(registry.unsubscribeCallCount == 1)
        #expect(registry.activeSubscriptionCount == 0)
    }
}

@MainActor
private final class WeakReference<Value: AnyObject> {
    weak var value: Value?

    init(_ value: Value?) {
        self.value = value
    }
}

@MainActor
private final class RecordingObservationRegistry: AXObservationRegistry {
    private var subscriptions: [SubscriptionToken: AXNotificationSubscriptionHandler] = [:]
    private var processIdentifiersByToken: [SubscriptionToken: pid_t] = [:]
    private let failingProcessIdentifiers: Set<pid_t>
    private var remainingFailureCounts: [pid_t: Int]

    private(set) var unsubscribeCallCount = 0
    private(set) var subscribedProcessIdentifiers: [pid_t] = []

    init(
        failingProcessIdentifiers: Set<pid_t> = [],
        remainingFailureCounts: [pid_t: Int] = [:])
    {
        self.failingProcessIdentifiers = failingProcessIdentifiers
        self.remainingFailureCounts = remainingFailureCounts
    }

    var activeSubscriptionCount: Int {
        self.subscriptions.count
    }

    var activeProcessIdentifiers: [pid_t] {
        self.processIdentifiersByToken.values.sorted()
    }

    func contains(_ token: SubscriptionToken) -> Bool {
        self.subscriptions[token] != nil
    }

    func attemptCount(for processIdentifier: pid_t) -> Int {
        self.subscribedProcessIdentifiers.count { $0 == processIdentifier }
    }

    func subscribeProcess(
        pid: pid_t,
        element _: Element?,
        notification _: AXNotification,
        handler: @escaping AXNotificationSubscriptionHandler) -> Result<SubscriptionToken, AccessibilityError>
    {
        self.subscribedProcessIdentifiers.append(pid)
        let remainingFailures = self.remainingFailureCounts[pid, default: 0]
        if remainingFailures > 0 {
            self.remainingFailureCounts[pid] = remainingFailures - 1
        }
        guard !self.failingProcessIdentifiers.contains(pid), remainingFailures == 0 else {
            return .failure(.observerSetupFailed(details: "Fixture rejected PID \(pid)"))
        }
        let token = SubscriptionToken(id: UUID())
        self.subscriptions[token] = handler
        self.processIdentifiersByToken[token] = pid
        return .success(token)
    }

    func unsubscribe(token: SubscriptionToken) throws {
        self.unsubscribeCallCount += 1
        guard self.subscriptions.removeValue(forKey: token) != nil else {
            throw AccessibilityError.tokenNotFound(tokenId: token.id)
        }
        self.processIdentifiersByToken.removeValue(forKey: token)
    }
}

@MainActor
private final class SuspendingObservationRegistry: AXObservationRegistry {
    private let suspendedProcessIdentifiers: Set<pid_t> = [42]
    private var continuations: [pid_t: [CheckedContinuation<Void, Never>]] = [:]
    private var processIdentifiersByToken: [SubscriptionToken: pid_t] = [:]

    private(set) var unsubscribeCallCount = 0

    var pendingProcessIdentifiers: [pid_t] {
        self.continuations.compactMap { $0.value.isEmpty ? nil : $0.key }.sorted()
    }

    var activeProcessIdentifiers: [pid_t] {
        self.processIdentifiersByToken.values.sorted()
    }

    func subscribeProcess(
        pid: pid_t,
        element _: Element?,
        notification _: AXNotification,
        handler _: @escaping AXNotificationSubscriptionHandler) -> Result<SubscriptionToken, AccessibilityError>
    {
        .success(self.recordSubscription(processIdentifier: pid))
    }

    func subscribeProcessAsync(
        pid: pid_t,
        element _: Element?,
        notification _: AXNotification,
        handler _: @escaping AXNotificationSubscriptionHandler) async -> Result<SubscriptionToken, AccessibilityError>
    {
        guard self.suspendedProcessIdentifiers.contains(pid) else {
            return .success(self.recordSubscription(processIdentifier: pid))
        }
        await withCheckedContinuation { continuation in
            self.continuations[pid, default: []].append(continuation)
        }
        return .success(self.recordSubscription(processIdentifier: pid))
    }

    func unsubscribe(token: SubscriptionToken) throws {
        self.unsubscribeCallCount += 1
        guard self.processIdentifiersByToken.removeValue(forKey: token) != nil else {
            throw AccessibilityError.tokenNotFound(tokenId: token.id)
        }
    }

    func resume(processIdentifier: pid_t) {
        guard var pending = self.continuations[processIdentifier], !pending.isEmpty else { return }
        let continuation = pending.removeFirst()
        self.continuations[processIdentifier] = pending
        continuation.resume()
    }

    func pendingCount(for processIdentifier: pid_t) -> Int {
        self.continuations[processIdentifier]?.count ?? 0
    }

    private func recordSubscription(processIdentifier: pid_t) -> SubscriptionToken {
        let token = SubscriptionToken(id: UUID())
        self.processIdentifiersByToken[token] = processIdentifier
        return token
    }
}

@MainActor
private final class RecordingGlobalApplicationMonitor: AXGlobalApplicationMonitoring {
    private(set) var runningProcessIdentifiers: [pid_t]
    private(set) var stopCount = 0
    private var onLaunch: (@MainActor (pid_t) -> Void)?
    private var onTermination: (@MainActor (pid_t) -> Void)?

    init(runningProcessIdentifiers: [pid_t]) {
        self.runningProcessIdentifiers = runningProcessIdentifiers
    }

    func start(
        onLaunch: @escaping @MainActor (pid_t) -> Void,
        onTermination: @escaping @MainActor (pid_t) -> Void)
    {
        self.onLaunch = onLaunch
        self.onTermination = onTermination
        for processIdentifier in self.runningProcessIdentifiers.sorted() {
            onLaunch(processIdentifier)
        }
    }

    func stop() {
        self.stopCount += 1
        self.onLaunch = nil
        self.onTermination = nil
    }

    func launch(processIdentifier: pid_t) {
        if !self.runningProcessIdentifiers.contains(processIdentifier) {
            self.runningProcessIdentifiers.append(processIdentifier)
        }
        self.onLaunch?(processIdentifier)
    }

    func terminate(processIdentifier: pid_t) {
        self.runningProcessIdentifiers.removeAll { $0 == processIdentifier }
        self.onTermination?(processIdentifier)
    }

    func ready(processIdentifier: pid_t) {
        self.onLaunch?(processIdentifier)
    }
}

@MainActor
private final class ProcessGenerationBox {
    var value: UInt64?

    init(_ value: UInt64?) {
        self.value = value
    }
}

@MainActor
private final class ProcessGenerationSequence {
    private var values: [UInt64?]

    init(_ values: [UInt64?]) {
        self.values = values
    }

    func next() -> UInt64? {
        self.values.isEmpty ? nil : self.values.removeFirst()
    }
}
