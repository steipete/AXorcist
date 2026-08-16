//
//  AXObserverCenter.swift
//  AXorcist
//
//  A centralized manager for AXObserver instances
//

import ApplicationServices
import Darwin
import Foundation

/// Centralized manager for AXObserver instances that coordinates accessibility notifications.
///
/// AXObserverCenter provides:
/// - Unified management of accessibility observers across the application
/// - Registration and lifecycle management of notification subscriptions
/// - Process-specific observer tracking
/// - Automatic cleanup of observers when processes terminate
/// - Main-actor-isolated observer operations
///
/// This center ensures efficient resource usage by reusing observers for the same
/// process and prevents memory leaks by properly cleaning up observers.
@MainActor
public final class AXObserverCenter {
    typealias ObserverSetup = @MainActor (
        _ pid: pid_t,
        _ element: Element?,
        _ notification: AXNotification) -> AXError
    typealias ObserverCleanup = @MainActor (
        _ pid: pid_t,
        _ element: Element,
        _ notification: AXNotification) -> Void
    typealias ProcessIdentityProvider = @MainActor (_ pid: pid_t) -> UInt64?

    private struct ObserverGeneration {
        let startIdentity: UInt64
    }

    private struct PendingRegistration {
        let id: UUID
        let expectedGeneration: UInt64
        let task: Task<NativeRegistrationSetupResult, Never>
        let completion: NativeRemovalCompletion
    }

    private struct NativeRegistrationState: Equatable {
        let operationID: UUID
        let processGeneration: UInt64
    }

    private struct NativeRegistrationSetupResult {
        let error: AXError
        let state: NativeRegistrationState?
    }

    private struct PendingRemoval {
        let id: UUID
        let completion: NativeRemovalCompletion
    }

    private struct ObserverWorkerKey: Hashable {
        let pid: pid_t
        let processGeneration: UInt64
    }

    private struct ObserverStateEpoch: Equatable {
        let global: UInt64
        let process: UInt64
    }

    // MARK: - Public State

    /// Shared instance
    public static let shared = AXObserverCenter()

    /// All active observers
    public var activeObservers: [AXObserverObjAndPID] {
        self.observers
    }

    /// All registered observer keys
    public var registeredKeys: [AXNotificationSubscriptionKey] {
        self.subscriptionStore.registeredKeys
    }

    // MARK: - Stored State

    private let subscriptionStore = AXObserverSubscriptionStore()
    private nonisolated let nativeWorkAdmission = ObserverNativeWorkerAdmission()
    private var observers: [AXObserverObjAndPID] = []
    private var observerGenerations: [pid_t: ObserverGeneration] = [:]
    private var pendingObserverCreations: [pid_t: PendingObserverCreation] = [:]
    private var nativeObserverWorkers: [ObserverWorkerKey: UUID] = [:]
    private var pendingRegistrations: [AXObserverRegistrationKey: PendingRegistration] = [:]
    private var pendingRemovals: [AXObserverRegistrationKey: PendingRemoval] = [:]
    private var nativeRegistrationStates: [AXObserverRegistrationKey: NativeRegistrationState] = [:]
    private var asynchronousNativeRegistrations: Set<AXObserverRegistrationKey> = []
    private var globalStateEpoch: UInt64 = 0
    private var processStateEpochs: [pid_t: UInt64] = [:]
    private let observerSetupOverride: ObserverSetup?
    private let observerCleanupOverride: ObserverCleanup?
    private let processIdentityProvider: ProcessIdentityProvider

    // MARK: - Lifecycle

    private init() {
        self.observerSetupOverride = nil
        self.observerCleanupOverride = nil
        self.processIdentityProvider = Self.nativeProcessUniqueIdentity
    }

    init(
        observerSetup: @escaping ObserverSetup,
        observerCleanup: @escaping ObserverCleanup)
    {
        self.observerSetupOverride = observerSetup
        self.observerCleanupOverride = observerCleanup
        self.processIdentityProvider = { UInt64(UInt32(bitPattern: $0)) }
    }

    init(
        observerSetup: @escaping ObserverSetup,
        observerCleanup: @escaping ObserverCleanup,
        processIdentityProvider: @escaping ProcessIdentityProvider)
    {
        self.observerSetupOverride = observerSetup
        self.observerCleanupOverride = observerCleanup
        self.processIdentityProvider = processIdentityProvider
    }
}

// MARK: - Public API

@MainActor
extension AXObserverCenter {
    /// Subscribe to one application or element notification.
    ///
    /// A nil PID is retained for source compatibility but fails explicitly because
    /// macOS has no global AX observer. Use `NotificationWatcher(globalNotification:)`
    /// for native per-application fan-out.
    public func subscribe(
        pid: pid_t? = nil,
        element: Element? = nil,
        notification: AXNotification,
        handler: @escaping AXNotificationSubscriptionHandler) -> Result<SubscriptionToken, AccessibilityError>
    {
        guard let pid else {
            let details = "macOS AXObserver requires an application PID; " +
                "use NotificationWatcher(globalNotification:) for native global fan-out"
            return .failure(.observerSetupFailed(details: details))
        }
        return self.subscribeProcess(pid: pid, element: element, notification: notification, handler: handler)
    }

    func subscribeProcess(
        pid: pid_t,
        element: Element? = nil,
        notification: AXNotification,
        handler: @escaping AXNotificationSubscriptionHandler) -> Result<SubscriptionToken, AccessibilityError>
    {
        guard pid > 0 else {
            return .failure(.observerSetupFailed(
                details: "macOS AXObserver requires an application PID greater than zero"))
        }
        guard let expectedGeneration = self.processIdentityProvider(pid) else {
            return .failure(.observerSetupFailed(
                details: "Could not resolve the process generation for PID \(pid)"))
        }
        self.prepareObserverGeneration(for: pid, currentIdentity: expectedGeneration)

        let registration = self.registrationKey(pid: pid, element: element, notification: notification)
        let awaitedRemoval = self.finishPendingRemovalSynchronously(registration)
        guard awaitedRemoval != false else {
            return .failure(.observerSetupFailed(
                details: "Timed out awaiting observer cleanup for PID \(pid)"))
        }
        guard awaitedRemoval != true || self.processIdentityProvider(pid) == expectedGeneration else {
            self.resetObserverGeneration(for: pid, ifMatching: expectedGeneration)
            return .failure(.observerSetupFailed(
                details: "Process generation changed while awaiting observer cleanup for PID \(pid)"))
        }
        let expectedEpoch = self.currentStateEpoch(for: pid)
        let joinedRegistration = self.finishPendingRegistrationSynchronously(
            registration,
            expectedGeneration: expectedGeneration,
            expectedEpoch: expectedEpoch)
        let hasNativeRegistration = self.nativeRegistrationStates[registration]?.processGeneration == expectedGeneration
        let setupError = if let joinedRegistration {
            joinedRegistration
        } else if hasNativeRegistration {
            AXError.success
        } else {
            self.setupUnderlyingObserver(registration, expectedGeneration: expectedGeneration)
        }
        guard setupError == .success else {
            let errorMessage = "Failed to setup underlying AXObserver for \(describePid(pid)) " +
                "notification \(notification.rawValue) (AXError \(setupError.rawValue))"
            axErrorLog(errorMessage)
            return .failure(.observerSetupFailed(details: errorMessage))
        }
        if joinedRegistration == nil, !hasNativeRegistration {
            self.nativeRegistrationStates[registration] = NativeRegistrationState(
                operationID: UUID(),
                processGeneration: expectedGeneration)
        }
        if joinedRegistration != nil {
            self.asynchronousNativeRegistrations.insert(registration)
        } else if !hasNativeRegistration {
            self.asynchronousNativeRegistrations.remove(registration)
        }

        return .success(self.subscriptionStore.add(registration: registration, handler: handler))
    }

    func subscribeProcessAsync(
        pid: pid_t,
        element: Element? = nil,
        notification: AXNotification,
        handler: @escaping AXNotificationSubscriptionHandler) async -> Result<SubscriptionToken, AccessibilityError>
    {
        if self.observerSetupOverride != nil {
            return self.subscribeProcess(
                pid: pid,
                element: element,
                notification: notification,
                handler: handler)
        }
        guard pid > 0 else {
            return .failure(.observerSetupFailed(
                details: "macOS AXObserver requires an application PID greater than zero"))
        }
        guard let expectedGeneration = await ObserverNativeWork.boundedProcessUniqueIdentity(
            pid,
            admission: self.nativeWorkAdmission)
        else {
            return .failure(.observerSetupFailed(
                details: "Could not resolve the process generation for PID \(pid)"))
        }
        let expectedEpoch = self.prepareObserverEpoch(for: pid, currentIdentity: expectedGeneration)

        let registration = self.registrationKey(pid: pid, element: element, notification: notification)
        let deadline = ContinuousClock().now.advanced(by: .seconds(2))
        while ContinuousClock().now < deadline {
            if let result = await self.attemptSubscribeProcessAsync(
                pid: pid,
                registration: registration,
                expectedGeneration: expectedGeneration,
                expectedEpoch: expectedEpoch,
                handler: handler)
            {
                return result
            }
        }
        return .failure(.observerSetupFailed(
            details: "Timed out registering a bounded AXObserver for PID \(pid)"))
    }

    private func attemptSubscribeProcessAsync(
        pid: pid_t,
        registration: AXObserverRegistrationKey,
        expectedGeneration: UInt64,
        expectedEpoch: ObserverStateEpoch,
        handler: @escaping AXNotificationSubscriptionHandler) async -> Result<SubscriptionToken, AccessibilityError>?
    {
        await self.finishPendingRemoval(registration)
        guard self.currentStateEpoch(for: pid) == expectedEpoch else {
            return .failure(.observerSetupFailed(
                details: "Observer state changed while registering PID \(pid)"))
        }

        let setupResult = if let state = self.nativeRegistrationStates[registration],
                             state.processGeneration == expectedGeneration
        {
            NativeRegistrationSetupResult(error: .success, state: state)
        } else {
            await self.setupRegistrationAsync(registration, expectedGeneration: expectedGeneration)
        }
        if self.pendingRemovals[registration] != nil {
            return nil
        }
        guard setupResult.error == .success,
              self.currentStateEpoch(for: pid) == expectedEpoch,
              self.observerGenerations[pid]?.startIdentity == expectedGeneration
        else {
            return self.asyncSetupFailure(
                pid: pid,
                notification: registration.subscription.notification,
                error: setupResult.error)
        }
        guard let state = setupResult.state, self.nativeRegistrationStates[registration] == state else { return nil }
        self.asynchronousNativeRegistrations.insert(registration)
        return .success(self.subscriptionStore.add(registration: registration, handler: handler))
    }

    private func asyncSetupFailure(
        pid: pid_t,
        notification: AXNotification,
        error: AXError) -> Result<SubscriptionToken, AccessibilityError>
    {
        let details = "Failed to setup bounded AXObserver for \(describePid(pid)) " +
            "notification \(notification.rawValue) (AXError \(error.rawValue))"
        return .failure(.observerSetupFailed(details: details))
    }

    public func unsubscribe(token: SubscriptionToken) throws {
        let removal: AXObserverSubscriptionStore.Removal
        do {
            removal = try self.subscriptionStore.remove(token: token)
        } catch {
            axErrorLog("Unsubscribe failed: Token ID \(token.id) not found.")
            throw error
        }

        axInfoLog(
            logSegments(
                "Successfully unsubscribed handler (token: \(token.id)) " +
                    "for \(describePid(removal.registration.subscription.pid))",
                "notification: \(removal.registration.subscription.notification.rawValue)"))
        guard removal.removedLastHandler else { return }

        axDebugLog(
            logSegments(
                "No handlers left for \(describePid(removal.registration.subscription.pid))",
                "notification: \(removal.registration.subscription.notification.rawValue). " +
                    "Registration removed from subscriptions"))
        self.cleanupUnderlyingObserverNotification(removal.registration)
    }

    public func removeAllObservers() {
        axInfoLog("Removing all observers and subscriptions globally.")
        self.advanceStateEpoch()
        for pending in self.pendingObserverCreations.values {
            pending.task.cancel()
        }
        for pending in self.pendingRegistrations.values {
            pending.task.cancel()
        }
        self.pendingObserverCreations.removeAll()
        self.pendingRegistrations.removeAll()
        self.pendingRemovals.removeAll()
        self.nativeRegistrationStates.removeAll()
        self.asynchronousNativeRegistrations.removeAll()
        self.processStateEpochs.removeAll()
        self.subscriptionStore.removeAll()

        for record in self.observers {
            let source = AXObserverGetRunLoopSource(record.observer)
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .defaultMode)
            CFRunLoopSourceInvalidate(source)
        }
        self.observers.removeAll()
        self.observerGenerations.removeAll()
        axInfoLog("All observers and subscriptions have been cleared.")
    }

    public func removeAllObservers(for pid: pid_t) {
        axInfoLog("Removing all observers and subscriptions for PID \(pid)")
        self.advanceStateEpoch(for: pid)
        self.cancelPendingWork(for: pid)
        for token in self.subscriptionStore.tokens(for: pid) {
            try? self.unsubscribe(token: token)
        }
        self.removeObserverIfUnused(targetPid: pid)
    }

    public func isKeyRegistered(pid: pid_t?, notification: AXNotification) -> Bool {
        guard let pid else { return false }
        return self.subscriptionStore.contains(pid: pid, notification: notification)
    }
}

// MARK: - Canonical Registry

@MainActor
extension AXObserverCenter: AXObservationRegistry {}

// MARK: - Private Helpers

@MainActor
extension AXObserverCenter {
    // MARK: - Internal AXObserver Management (previously addObserver / removeObserver)

    private func registrationKey(
        pid: pid_t,
        element: Element?,
        notification: AXNotification) -> AXObserverRegistrationKey
    {
        let observedElement = Element(self.elementForObservation(
            pid: pid,
            element: element,
            notification: notification))
        let scope: AXObserverRegistrationKey.Scope = element == nil
            ? .process
            : self.registrationScope(pid: pid, observedElement: observedElement)
        return AXObserverRegistrationKey(
            subscription: AXNotificationSubscriptionKey(pid: pid, notification: notification),
            element: observedElement,
            scope: scope)
    }

    private func registrationScope(pid: pid_t, observedElement: Element) -> AXObserverRegistrationKey.Scope {
        let applicationElement = Element(AXUIElement.application(pid: pid))
        return observedElement == applicationElement ? .process : .element
    }

    /// Ensures an AXObserver is created for the exact registration target.
    private func setupRegistrationAsync(
        _ registration: AXObserverRegistrationKey,
        expectedGeneration: UInt64) async -> NativeRegistrationSetupResult
    {
        if let pending = self.pendingRegistrations[registration],
           pending.expectedGeneration == expectedGeneration
        {
            return await pending.task.value
        }
        if let stalePending = self.pendingRegistrations.removeValue(forKey: registration) {
            stalePending.task.cancel()
        }
        let id = UUID()
        let completion = NativeRemovalCompletion()
        let task = Task { @MainActor in
            let error = await self.setupUnderlyingObserverAsync(
                registration,
                operationID: id,
                expectedGeneration: expectedGeneration)
            let state = error == .success
                ? NativeRegistrationState(operationID: id, processGeneration: expectedGeneration)
                : nil
            if let state {
                self.nativeRegistrationStates[registration] = state
            }
            completion.finish(with: error)
            return NativeRegistrationSetupResult(error: error, state: state)
        }
        self.pendingRegistrations[registration] = PendingRegistration(
            id: id,
            expectedGeneration: expectedGeneration,
            task: task,
            completion: completion)
        let result = await task.value
        if self.pendingRegistrations[registration]?.id == id {
            self.pendingRegistrations.removeValue(forKey: registration)
        }
        if result.error != AXError.success {
            self.removeObserverIfUnused(targetPid: registration.subscription.pid)
        }
        return result
    }

    private func finishPendingRegistrationSynchronously(
        _ registration: AXObserverRegistrationKey,
        expectedGeneration: UInt64,
        expectedEpoch: ObserverStateEpoch) -> AXError?
    {
        guard let pending = self.pendingRegistrations[registration] else { return nil }
        guard pending.expectedGeneration == expectedGeneration else { return .cannotComplete }
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(2))
        while pending.completion.currentResult() == nil, clock.now < deadline {
            _ = RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
        }
        guard let error = pending.completion.currentResult() else { return .cannotComplete }
        let stillOwnsPending = self.pendingRegistrations[registration]?.id == pending.id
        let expectedState = NativeRegistrationState(
            operationID: pending.id,
            processGeneration: expectedGeneration)
        let alreadyCommitted = self.nativeRegistrationStates[registration] == expectedState
        guard self.currentStateEpoch(for: registration.subscription.pid) == expectedEpoch else {
            return .cannotComplete
        }
        if error == .success {
            guard self.observerGenerations[registration.subscription.pid]?.startIdentity == expectedGeneration else {
                return .cannotComplete
            }
            guard alreadyCommitted else {
                if stillOwnsPending {
                    self.pendingRegistrations.removeValue(forKey: registration)
                }
                return nil
            }
        } else if !stillOwnsPending {
            return .cannotComplete
        }
        if stillOwnsPending {
            self.pendingRegistrations.removeValue(forKey: registration)
        }
        if error != .success {
            self.removeObserverIfUnused(targetPid: registration.subscription.pid)
        }
        return error
    }

    private func setupUnderlyingObserverAsync(
        _ registration: AXObserverRegistrationKey,
        operationID: UUID,
        expectedGeneration: UInt64) async -> AXError
    {
        let targetPid = registration.subscription.pid
        guard let observer = await self.getOrCreateObserverAsync(
            for: targetPid,
            expectedGeneration: expectedGeneration)
        else {
            return .failure
        }
        let registrationWork = self.nativeNotificationRegistration(for: registration, observer: observer)
        let nativeWorkAdmission = self.nativeWorkAdmission
        let registrationTask = Task.detached(priority: .utility) {
            await ObserverNativeWork.addNotification(registrationWork, admission: nativeWorkAdmission)
        }
        let error = await registrationTask.value
        guard self.pendingRegistrations[registration]?.id == operationID,
              !Task.isCancelled
        else {
            if error == .success {
                _ = await self.removeNativeRegistration(registrationWork)
            }
            return .cannotComplete
        }
        let finalGeneration = await ObserverNativeWork.boundedProcessUniqueIdentity(
            targetPid,
            admission: self.nativeWorkAdmission)
        guard self.pendingRegistrations[registration]?.id == operationID,
              !Task.isCancelled,
              finalGeneration == expectedGeneration
        else {
            if error == .success {
                _ = await self.removeNativeRegistration(registrationWork)
            }
            self.resetObserverGeneration(for: targetPid, ifMatching: expectedGeneration)
            return .cannotComplete
        }

        self.logObserverAddResult(
            targetPid: targetPid,
            notification: registration.subscription.notification,
            error: error)
        if error != .success {
            self.removeObserverIfUnused(targetPid: targetPid)
        }
        return error
    }

    private func removeNativeRegistration(_ registration: NativeNotificationRegistration) async -> AXError {
        await ObserverNativeWork.performCleanup(
            admission: self.nativeWorkAdmission,
            timeoutValue: .cannotComplete,
            operation: registration.remove)
    }

    private func setupUnderlyingObserver(
        _ registration: AXObserverRegistrationKey,
        expectedGeneration: UInt64) -> AXError
    {
        let subscription = registration.subscription
        if let observerSetupOverride {
            let error = observerSetupOverride(subscription.pid, registration.element, subscription.notification)
            let finalGeneration = self.processIdentityProvider(subscription.pid)
            guard finalGeneration == expectedGeneration else {
                if finalGeneration != nil {
                    self.resetObserverGeneration(for: subscription.pid)
                }
                return .cannotComplete
            }
            if error == .success {
                self.recordObserverGeneration(for: subscription.pid, startIdentity: expectedGeneration)
            }
            return error
        }

        let targetPid = subscription.pid
        guard let observer = getOrCreateObserver(for: targetPid, expectedGeneration: expectedGeneration) else {
            axErrorLog("Failed to get/create AXObserver for effective PID \(targetPid) during setup.")
            return .failure
        }

        let registrationWork = self.nativeNotificationRegistration(for: registration, observer: observer)
        let error = ObserverNativeWork.performSynchronously(
            admission: self.nativeWorkAdmission,
            refusalValue: AXError.cannotComplete)
        {
            registrationWork.add()
        }

        let finalGeneration = self.processIdentityProvider(targetPid)
        guard finalGeneration == expectedGeneration else {
            if error == .success {
                let removalError = ObserverNativeWork.tryPerformCleanupSynchronously(
                    admission: self.nativeWorkAdmission,
                    operation: { registrationWork.remove() })
                if removalError == nil {
                    self.scheduleNativeRemoval(registration, cleanup: registrationWork)
                }
            }
            if finalGeneration == nil {
                self.removeObserverIfUnused(targetPid: targetPid)
            } else {
                self.resetObserverGeneration(for: targetPid)
            }
            return .cannotComplete
        }

        self.logObserverAddResult(targetPid: targetPid, notification: subscription.notification, error: error)
        if error != .success {
            self.removeObserverIfUnused(targetPid: targetPid)
        }
        return error
    }

    private func elementForObservation(
        pid: pid_t,
        element: Element?,
        notification: AXNotification) -> AXUIElement
    {
        if let specificElement = element {
            axDebugLog(
                logSegments(
                    "Observer for \(describePid(pid))",
                    "using provided specific element \(specificElement.briefDescription())",
                    "notification \(notification.rawValue)"))
            return specificElement.underlyingElement
        }

        axDebugLog(
            logSegments(
                "Application observer \(describePid(pid))",
                "Using application element",
                "notification \(notification.rawValue)"))
        return AXUIElement.application(pid: pid)
    }

    private func nativeNotificationRegistration(
        for registration: AXObserverRegistrationKey,
        observer: AXObserver) -> NativeNotificationRegistration
    {
        let processScoped = registration.scope == .process
        let element = processScoped
            ? AXUIElement.application(pid: registration.subscription.pid)
            : registration.element.underlyingElement
        return NativeNotificationRegistration(
            observer: observer,
            element: element,
            notification: registration.subscription.notification.rawValue as CFString,
            refcon: Unmanaged.passUnretained(self).toOpaque(),
            appliesMessagingTimeout: processScoped)
    }

    private func logObserverAddResult(targetPid: pid_t, notification: AXNotification, error: AXError) {
        let message = logSegments(
            "AXObserver notification \(notification.rawValue) for \(describePid(targetPid))",
            "status: \(error == .success ? "success" : "error \(error.rawValue)")")
        if error == .success {
            axInfoLog(message)
        } else {
            axErrorLog(message)
        }
    }

    /// Removes the exact system registration after its final handler unsubscribes.
    private func cleanupUnderlyingObserverNotification(_ registration: AXObserverRegistrationKey) {
        let subscription = registration.subscription
        if let observerCleanupOverride {
            observerCleanupOverride(subscription.pid, registration.element, subscription.notification)
            self.nativeRegistrationStates.removeValue(forKey: registration)
            self.asynchronousNativeRegistrations.remove(registration)
            return
        }

        let targetPid = subscription.pid
        axDebugLog(
            logSegments(
                "Cleanup check for underlying AXObserver notification for \(describePid(targetPid))",
                "notification: \(subscription.notification.rawValue)"))

        guard !self.subscriptionStore.contains(registration: registration) else {
            axDebugLog(
                logSegments(
                    "Specific subscriptions still exist for \(describePid(subscription.pid))",
                    "notification: \(subscription.notification.rawValue). AXObserver notification retained"))
            return
        }

        guard let observer = getObserver(for: targetPid) else {
            self.nativeRegistrationStates.removeValue(forKey: registration)
            self.asynchronousNativeRegistrations.remove(registration)
            axWarningLog(
                logSegments(
                    "No AXObserver found for \(describePid(targetPid)) during cleanup",
                    "notification: \(subscription.notification.rawValue)"))
            return
        }

        guard self.pendingRemovals[registration] == nil else { return }

        let cleanup = self.nativeNotificationRegistration(for: registration, observer: observer)
        guard self.asynchronousNativeRegistrations.contains(registration) else {
            guard let error = ObserverNativeWork.tryPerformCleanupSynchronously(
                admission: self.nativeWorkAdmission,
                operation: {
                    cleanup.remove()
                })
            else {
                self.asynchronousNativeRegistrations.insert(registration)
                self.scheduleNativeRemoval(registration, cleanup: cleanup)
                return
            }
            self.finalizeNativeRemoval(registration, error: error)
            return
        }
        self.scheduleNativeRemoval(registration, cleanup: cleanup)
    }

    private func scheduleNativeRemoval(
        _ registration: AXObserverRegistrationKey,
        cleanup: NativeNotificationRegistration)
    {
        let id = UUID()
        let completion = NativeRemovalCompletion()
        self.pendingRemovals[registration] = PendingRemoval(id: id, completion: completion)
        let nativeWorkAdmission = self.nativeWorkAdmission
        Task.detached(priority: .utility) {
            await ObserverNativeWork.runPendingCleanup(
                admission: nativeWorkAdmission,
                operation: cleanup.remove)
            { error in
                completion.finish(with: error)
                Task { @MainActor in
                    self.completePendingRemoval(registration, id: id, error: error)
                }
            }
        }
    }

    private func finishPendingRemoval(_ registration: AXObserverRegistrationKey) async {
        guard let pending = self.pendingRemovals[registration] else { return }
        _ = await pending.completion.value()
        guard let error = pending.completion.currentResult() else { return }
        self.completePendingRemoval(registration, id: pending.id, error: error)
    }

    private func finishPendingRemovalSynchronously(_ registration: AXObserverRegistrationKey) -> Bool? {
        guard let pending = self.pendingRemovals[registration] else { return nil }
        let clock = ContinuousClock()
        guard let error = pending.completion.wait(until: clock.now.advanced(by: .milliseconds(750))) else {
            return false
        }
        self.completePendingRemoval(registration, id: pending.id, error: error)
        return true
    }

    private func completePendingRemoval(
        _ registration: AXObserverRegistrationKey,
        id: UUID,
        error: AXError)
    {
        guard self.pendingRemovals[registration]?.id == id else { return }
        self.pendingRemovals.removeValue(forKey: registration)
        self.finalizeNativeRemoval(registration, error: error)
    }

    private func finalizeNativeRemoval(_ registration: AXObserverRegistrationKey, error: AXError) {
        let targetPid = registration.subscription.pid
        let notification = registration.subscription.notification
        self.nativeRegistrationStates.removeValue(forKey: registration)
        self.asynchronousNativeRegistrations.remove(registration)
        if NativeNotificationRegistration.removalConfirmsRegistrationAbsent(error) {
            axInfoLog(
                logSegments(
                    "Successfully removed notification from AXObserver for \(describePid(targetPid))",
                    "key: \(notification.rawValue) during cleanup"))
        } else {
            axErrorLog(
                logSegments(
                    "Failed to remove notification from AXObserver for \(describePid(targetPid))",
                    "key: \(notification.rawValue)",
                    "error: \(error.rawValue)"))
        }
        self.removeObserverIfUnused(targetPid: targetPid)
    }

    private func removeObserverIfUnused(targetPid: pid_t) {
        let hasAnySubscription = self.subscriptionStore.containsSubscriptions(forEffectivePID: targetPid)
        let hasPendingRegistration = self.pendingRegistrations.keys.contains {
            $0.subscription.pid == targetPid
        }
        guard !hasAnySubscription,
              !hasPendingRegistration,
              let observer = getObserver(for: targetPid)
        else { return }
        let source = AXObserverGetRunLoopSource(observer)
        CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .defaultMode)
        CFRunLoopSourceInvalidate(source)
        self.removePidObserverInstance(pid: targetPid)
    }

    // MARK: - Private Methods

    private func prepareObserverGeneration(for pid: pid_t, currentIdentity: UInt64) {
        guard let storedGeneration = self.observerGenerations[pid] else { return }
        guard storedGeneration.startIdentity != currentIdentity else { return }

        self.resetObserverGeneration(for: pid)
    }

    private func prepareObserverEpoch(for pid: pid_t, currentIdentity: UInt64) -> ObserverStateEpoch {
        self.prepareObserverGeneration(for: pid, currentIdentity: currentIdentity)
        return self.currentStateEpoch(for: pid)
    }

    private func resetObserverGeneration(for pid: pid_t, ifMatching expectedGeneration: UInt64? = nil) {
        if let expectedGeneration,
           self.observerGenerations[pid]?.startIdentity != expectedGeneration
        {
            return
        }
        self.advanceStateEpoch(for: pid)
        self.cancelPendingWork(for: pid, matching: expectedGeneration)
        if let observer = getObserver(for: pid) {
            let source = AXObserverGetRunLoopSource(observer)
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .defaultMode)
            CFRunLoopSourceInvalidate(source)
        }
        self.removePidObserverInstance(pid: pid)
        let removedSubscriptionCount = self.subscriptionStore.removeAll(for: pid)
        axInfoLog(
            "Reset stale AXObserver generation for PID \(pid); removed " +
                "\(removedSubscriptionCount) logical subscriptions")
    }

    private func recordObserverGeneration(for pid: pid_t, startIdentity: UInt64) {
        self.observerGenerations[pid] = ObserverGeneration(startIdentity: startIdentity)
    }

    private func getObserver(for pid: pid_t) -> AXObserver? {
        self.observers.first { $0.pid == pid }?.observer
    }

    private func getOrCreateObserver(for pid: pid_t, expectedGeneration: UInt64) -> AXObserver? {
        if let existing = getObserver(for: pid) {
            return existing
        }
        _ = self.pendingObserverCreation(for: pid, expectedGeneration: expectedGeneration)
        return self.finishPendingObserverCreationSynchronously(
            for: pid,
            expectedGeneration: expectedGeneration)
    }

    private func finishPendingObserverCreationSynchronously(
        for pid: pid_t,
        expectedGeneration: UInt64) -> AXObserver?
    {
        guard let pending = self.pendingObserverCreations[pid],
              pending.expectedGeneration == expectedGeneration
        else { return nil }
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .milliseconds(750))
        while pending.completion.currentResult() == nil, clock.now < deadline {
            _ = RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
        }
        guard let outcome = pending.completion.currentResult() else { return nil }
        guard self.pendingObserverCreations[pid]?.id == pending.id else {
            return self.observer(for: pid, matching: expectedGeneration)
        }
        guard self.processIdentityProvider(pid) == expectedGeneration else {
            self.pendingObserverCreations.removeValue(forKey: pid)
            return nil
        }
        self.pendingObserverCreations.removeValue(forKey: pid)
        if let existing = self.observer(for: pid, matching: expectedGeneration) {
            return existing
        }
        return self.commitNativeObserver(outcome, for: pid, expectedGeneration: expectedGeneration)
    }

    private func getOrCreateObserverAsync(for pid: pid_t, expectedGeneration: UInt64) async -> AXObserver? {
        if let existing = self.getObserver(for: pid) {
            return existing
        }

        let pending = self.pendingObserverCreation(for: pid, expectedGeneration: expectedGeneration)
        let outcome = await pending.task.value
        guard self.pendingObserverCreations[pid]?.id == pending.id else {
            return self.observer(for: pid, matching: expectedGeneration)
        }
        let finalGeneration = await ObserverNativeWork.boundedProcessUniqueIdentity(
            pid,
            admission: self.nativeWorkAdmission)
        guard self.pendingObserverCreations[pid]?.id == pending.id else {
            return self.observer(for: pid, matching: expectedGeneration)
        }
        self.pendingObserverCreations.removeValue(forKey: pid)
        if let existing = self.observer(for: pid, matching: expectedGeneration) {
            return existing
        }
        guard finalGeneration == expectedGeneration else {
            axWarningLog("Discarded AXObserver creation for reused or terminated PID \(pid)")
            return nil
        }

        return self.commitNativeObserver(outcome, for: pid, expectedGeneration: expectedGeneration)
    }

    private func pendingObserverCreation(
        for pid: pid_t,
        expectedGeneration: UInt64) -> PendingObserverCreation
    {
        if let pending = self.pendingObserverCreations[pid],
           pending.expectedGeneration == expectedGeneration
        {
            return pending
        }
        self.pendingObserverCreations.removeValue(forKey: pid)?.task.cancel()
        let id = UUID()
        let completion = NativeObserverCreationCompletion()
        let workerKey = ObserverWorkerKey(pid: pid, processGeneration: expectedGeneration)
        if self.nativeObserverWorkers[workerKey] != nil {
            let pending = PendingObserverCreation.timedOut(
                id: id,
                expectedGeneration: expectedGeneration)
            self.pendingObserverCreations[pid] = pending
            return pending
        }
        guard self.nativeWorkAdmission.tryAcquire() else {
            let pending = PendingObserverCreation.timedOut(
                id: id,
                expectedGeneration: expectedGeneration)
            self.pendingObserverCreations[pid] = pending
            return pending
        }

        self.nativeObserverWorkers[workerKey] = id
        let callback = SendableObserverCallback(value: self.makeObserverCallback())
        let nativeWorkAdmission = self.nativeWorkAdmission
        let workerFinished: @Sendable () -> Void = { [weak self] in
            nativeWorkAdmission.release()
            Task { @MainActor in
                self?.finishNativeObserverWorker(workerKey, id: id)
            }
        }
        let task = Task.detached(priority: .utility) {
            let outcome = await Self.createNativeObserver(
                for: pid,
                callback: callback,
                timeout: .milliseconds(500),
                workerFinished: workerFinished)
            completion.finish(with: outcome)
            return outcome
        }
        let pending = PendingObserverCreation(
            id: id,
            expectedGeneration: expectedGeneration,
            task: task,
            completion: completion)
        self.pendingObserverCreations[pid] = pending
        return pending
    }

    private func observer(for pid: pid_t, matching expectedGeneration: UInt64) -> AXObserver? {
        guard self.observerGenerations[pid]?.startIdentity == expectedGeneration else { return nil }
        return self.getObserver(for: pid)
    }

    private func finishNativeObserverWorker(_ workerKey: ObserverWorkerKey, id: UUID) {
        guard self.nativeObserverWorkers[workerKey] == id else { return }
        self.nativeObserverWorkers.removeValue(forKey: workerKey)
    }

    private func commitNativeObserver(
        _ outcome: NativeObserverCreation,
        for pid: pid_t,
        expectedGeneration: UInt64) -> AXObserver?
    {
        switch outcome {
        case let .created(observer):
            let source = AXObserverGetRunLoopSource(observer.value)
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
            self.observers.append(AXObserverObjAndPID(observer: observer.value, pid: pid))
            self.recordObserverGeneration(for: pid, startIdentity: expectedGeneration)
            axDebugLog("Created bounded observer for PID \(pid)")
            return observer.value
        case let .failed(error):
            axErrorLog("Failed to create observer for PID \(pid), error: \(error.rawValue)")
            return nil
        case .timedOut:
            axWarningLog("Timed out creating observer for PID \(pid)")
            return nil
        }
    }

    private nonisolated static func createNativeObserver(
        for pid: pid_t,
        callback: SendableObserverCallback,
        timeout: Duration,
        workerFinished: @escaping @Sendable () -> Void) async -> NativeObserverCreation
    {
        await withCheckedContinuation { continuation in
            let gate = FirstResultGate(continuation: continuation)
            Thread.detachNewThread {
                let outcome = autoreleasepool { () -> NativeObserverCreation in
                    var observer: AXObserver?
                    let error = AXObserverCreateWithInfoCallback(pid, callback.value, &observer)
                    guard error == .success, let observer else {
                        return .failed(error)
                    }
                    return .created(SendableObserver(value: observer))
                }
                workerFinished()
                gate.finish(with: outcome)
            }
            Task.detached(priority: .utility) {
                try? await Task.sleep(for: timeout)
                gate.finish(with: .timedOut)
            }
        }
    }

    private func cancelPendingWork(for pid: pid_t, matching expectedGeneration: UInt64? = nil) {
        if let pending = self.pendingObserverCreations[pid],
           expectedGeneration == nil || pending.expectedGeneration == expectedGeneration
        {
            self.pendingObserverCreations.removeValue(forKey: pid)?.task.cancel()
        }
        let registrations = self.pendingRegistrations.filter { registration, pending in
            registration.subscription.pid == pid &&
                (expectedGeneration == nil || pending.expectedGeneration == expectedGeneration)
        }.map(\.key)
        for registration in registrations {
            self.pendingRegistrations.removeValue(forKey: registration)?.task.cancel()
        }
        let removals = self.pendingRemovals.keys.filter { $0.subscription.pid == pid }
        for registration in removals {
            self.pendingRemovals.removeValue(forKey: registration)
        }
    }

    private func advanceStateEpoch() {
        self.globalStateEpoch &+= 1
    }

    private func advanceStateEpoch(for pid: pid_t) {
        self.processStateEpochs[pid, default: 0] &+= 1
    }

    private func currentStateEpoch(for pid: pid_t) -> ObserverStateEpoch {
        ObserverStateEpoch(
            global: self.globalStateEpoch,
            process: self.processStateEpochs[pid, default: 0])
    }

    private func makeObserverCallback() -> AXObserverCallbackWithInfo {
        { _, element, notificationCFString, userInfo, refcon in
            guard let refcon else { return }
            let center = Unmanaged<AXObserverCenter>.fromOpaque(refcon).takeUnretainedValue()
            center.handleObserverCallback(
                element: element,
                notificationCFString: notificationCFString,
                userInfo: userInfo)
        }
    }

    private func handleObserverCallback(
        element: AXUIElement,
        notificationCFString: CFString,
        userInfo: CFDictionary?)
    {
        var elementPID: pid_t = 0
        AXUIElementGetPid(element, &elementPID)

        guard let axNotification = AXNotification(rawValue: notificationCFString as String) else {
            axWarningLog(
                logSegments(
                    "Received unknown notification string: \(notificationCFString as String)",
                    "for \(describePid(elementPID))",
                    "Cannot call handler"))
            return
        }

        let nsUserInfo = self.convertUserInfoDictionary(userInfo)
        Task { @MainActor in
            self.processNotification(
                pid: elementPID,
                notification: axNotification,
                rawElement: element,
                nsUserInfo: nsUserInfo)
        }
    }

    private func removePidObserverInstance(pid: pid_t) {
        self.observers.removeAll { $0.pid == pid }
        self.observerGenerations.removeValue(forKey: pid)
        self.nativeRegistrationStates = self.nativeRegistrationStates.filter {
            $0.key.subscription.pid != pid
        }
        self.asynchronousNativeRegistrations = self.asynchronousNativeRegistrations.filter {
            $0.subscription.pid != pid
        }
        axDebugLog("Removed AXObserver instance for effective PID \(pid).")
    }

    nonisolated static func nativeProcessUniqueIdentity(_ processIdentifier: pid_t) -> UInt64? {
        ObserverNativeWork.processUniqueIdentity(processIdentifier)
    }

    // MARK: - Main Notification Processing (Called by global callbacks)

    func processNotification(
        pid: pid_t,
        notification: AXNotification,
        rawElement: AXUIElement,
        nsUserInfo: [String: Any]?)
    {
        self.subscriptionStore.dispatch(
            pid: pid,
            notification: notification,
            rawElement: rawElement,
            userInfo: nsUserInfo)
    }

    private func convertUserInfoDictionary(_ userInfo: CFDictionary?) -> [String: Any]? {
        guard let cfUserInfo = userInfo as CFDictionary? else { return nil }
        guard let cfDict = cfUserInfo as? [CFString: CFTypeRef] else {
            axWarningLog("Could not cast userInfo CFDictionary to Dictionary<CFString, CFTypeRef>")
            return nil
        }

        var tempDict = [String: Any]()
        for (key, value) in cfDict {
            tempDict[key as String] = convertCFValueToSwift(value)
        }
        return tempDict
    }
}
