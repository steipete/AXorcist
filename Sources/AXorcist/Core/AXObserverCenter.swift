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

    /// Layout from XNU's API-stable `proc_uniqidentifierinfo`.
    private struct ProcessUniqueIdentifierInfo {
        var executableUUIDHigh: UInt64 = 0
        var executableUUIDLow: UInt64 = 0
        var uniqueIdentifier: UInt64 = 0
        var parentUniqueIdentifier: UInt64 = 0
        var identifierVersion: Int32 = 0
        var originalParentIdentifierVersion: Int32 = 0
        var reserved2: UInt64 = 0
        var reserved3: UInt64 = 0
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
    private var observers: [AXObserverObjAndPID] = []
    private var observerGenerations: [pid_t: ObserverGeneration] = [:]
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
        let elementDescriptionForLog = element?.briefDescription() ?? "N/A"
        axDebugLog(
            logSegments(
                "Subscribe request for \(describePid(pid))",
                "Element: \(elementDescriptionForLog)",
                "notification: \(notification.rawValue)"))

        let registration = self.registrationKey(pid: pid, element: element, notification: notification)
        let setupError = if self.subscriptionStore.contains(registration: registration) {
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

        let token = self.subscriptionStore.add(registration: registration, handler: handler)
        axInfoLog(
            logSegments(
                "Successfully subscribed handler (token: \(token.id)) for \(describePid(pid))",
                "notification: \(notification.rawValue)"))
        return .success(token)
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
        for token in self.subscriptionStore.tokens(for: pid) {
            try? self.unsubscribe(token: token)
        }
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
        return AXObserverRegistrationKey(
            subscription: AXNotificationSubscriptionKey(pid: pid, notification: notification),
            element: observedElement,
            scope: self.registrationScope(pid: pid, observedElement: observedElement))
    }

    private func registrationScope(pid: pid_t, observedElement: Element) -> AXObserverRegistrationKey.Scope {
        let applicationElement = Element(AXUIElement.application(pid: pid))
        return observedElement == applicationElement ? .process : .element
    }

    /// Ensures an AXObserver is created for the exact registration target.
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
        self.logObserverSetup(
            targetPid: targetPid,
            element: registration.element,
            notification: subscription.notification)
        guard let observer = getOrCreateObserver(for: targetPid, expectedGeneration: expectedGeneration) else {
            axErrorLog("Failed to get/create AXObserver for effective PID \(targetPid) during setup.")
            return .failure
        }

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let error = AXObserverAddNotification(
            observer,
            registration.element.underlyingElement,
            subscription.notification.rawValue as CFString,
            selfPtr)

        let finalGeneration = self.processIdentityProvider(targetPid)
        guard finalGeneration == expectedGeneration else {
            if error == .success {
                _ = AXObserverRemoveNotification(
                    observer,
                    registration.element.underlyingElement,
                    subscription.notification.rawValue as CFString)
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

    private func logObserverSetup(targetPid: pid_t, element: Element?, notification: AXNotification) {
        let elementDescriptionForLog = element?.briefDescription() ?? "N/A"
        axDebugLog(
            logSegments(
                "Setting up underlying AXObserver for effective \(describePid(targetPid))",
                "Element: \(elementDescriptionForLog)",
                "notification: \(notification.rawValue)"))
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
            axWarningLog(
                logSegments(
                    "No AXObserver found for \(describePid(targetPid)) during cleanup",
                    "notification: \(subscription.notification.rawValue)"))
            return
        }

        let error = AXObserverRemoveNotification(
            observer,
            registration.element.underlyingElement,
            subscription.notification.rawValue as CFString)

        if error == .success {
            axInfoLog(
                logSegments(
                    "Successfully removed notification from AXObserver for \(describePid(targetPid))",
                    "key: \(subscription.notification.rawValue) during cleanup"))
            self.removeObserverIfUnused(targetPid: targetPid)
        } else {
            axErrorLog(
                logSegments(
                    "Failed to remove notification from AXObserver for \(describePid(targetPid))",
                    "key: \(subscription.notification.rawValue)",
                    "error: \(error.rawValue)"))
        }
    }

    private func removeObserverIfUnused(targetPid: pid_t) {
        let hasAnySubscription = self.subscriptionStore.containsSubscriptions(forEffectivePID: targetPid)
        guard !hasAnySubscription, let observer = getObserver(for: targetPid) else { return }
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

    private func resetObserverGeneration(for pid: pid_t) {
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
        return self.createObserver(for: pid, expectedGeneration: expectedGeneration)
    }

    private func createObserver(for pid: pid_t, expectedGeneration: UInt64) -> AXObserver? {
        var observer: AXObserver?
        let callback = self.makeObserverCallback()

        let error = AXObserverCreateWithInfoCallback(pid, callback, &observer)

        if error == .success,
           let newObserver = observer,
           self.processIdentityProvider(pid) == expectedGeneration
        {
            // Add to run loop ONCE when observer is created.
            CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(newObserver), .defaultMode)
            axDebugLog("Added run loop source for new observer PID \(pid)")

            let obj = AXObserverObjAndPID(observer: newObserver, pid: pid)
            self.observers.append(obj)
            self.recordObserverGeneration(for: pid, startIdentity: expectedGeneration)
            axDebugLog("Created observer for PID \(pid)")
            return newObserver
        } else {
            axErrorLog("Failed to create observer for PID \(pid), error: \(error.rawValue)")
            return nil
        }
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
        axDebugLog("Removed AXObserver instance for effective PID \(pid).")
    }

    static func nativeProcessUniqueIdentity(_ processIdentifier: pid_t) -> UInt64? {
        guard processIdentifier > 0 else { return nil }
        var info = ProcessUniqueIdentifierInfo()
        let expectedSize = Int32(MemoryLayout<ProcessUniqueIdentifierInfo>.stride)
        guard proc_pidinfo(
            processIdentifier,
            17, // PROC_PIDUNIQIDENTIFIERINFO from XNU's proc_info_private.h
            0,
            &info,
            expectedSize) == expectedSize,
            info.uniqueIdentifier != 0
        else {
            return nil
        }
        return info.uniqueIdentifier
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
