//
//  AXObserverCenter.swift
//  AXorcist
//
//  A centralized manager for AXObserver instances
//

import ApplicationServices
import Foundation

// swiftlint:disable file_length

/// Centralized manager for AXObserver instances that coordinates accessibility notifications.
///
/// AXObserverCenter provides:
/// - Unified management of accessibility observers across the application
/// - Registration and lifecycle management of notification subscriptions
/// - Process-specific observer tracking
/// - Automatic cleanup of observers when processes terminate
/// - Thread-safe observer operations
///
/// This center ensures efficient resource usage by reusing observers for the same
/// process and prevents memory leaks by properly cleaning up observers.
@MainActor
public final class AXObserverCenter {
    // MARK: - Public State

    /// Shared instance
    public static let shared = AXObserverCenter()

    /// All active observers
    public var activeObservers: [AXObserverObjAndPID] {
        self.observers
    }

    /// All registered observer keys
    public var registeredKeys: [AXNotificationSubscriptionKey] { // Updated to use new key type
        // return observerKeys // Old way
        Array(self.subscriptions.keys)
    }

    // MARK: - Stored State

    /// Stores multiple handlers per notification key (and optional PID)
    private var subscriptions: [AXNotificationSubscriptionKey: [UUID: AXNotificationSubscriptionHandler]] = [:]
    private var subscriptionTokens: [UUID: AXNotificationSubscriptionKey] = [:]
    private var observers: [AXObserverObjAndPID] = []
    private let subscriptionsLock = NSLock()

    // MARK: - Lifecycle

    private init() {}
}

// MARK: - Public API

@MainActor
extension AXObserverCenter {
    public func subscribe(
        pid: pid_t? = nil,
        element: Element? = nil,
        notification: AXNotification,
        handler: @escaping AXNotificationSubscriptionHandler) -> Result<SubscriptionToken, AccessibilityError>
    {
        let elementDescriptionForLog = element?.briefDescription() ?? "N/A"
        axDebugLog(
            logSegments(
                "Subscribe request for \(describePid(pid))",
                "Element: \(elementDescriptionForLog)",
                "notification: \(notification.rawValue)"))

        let token = SubscriptionToken(id: UUID())
        let key = AXNotificationSubscriptionKey(pid: pid, notification: notification)

        self.subscriptionsLock.lock()
        defer { subscriptionsLock.unlock() }

        let setupError = setupUnderlyingObserver(forPid: pid, forElement: element, notification: notification)
        guard setupError == .success else {
            let errorMsg = "Failed to setup underlying AXObserver for \(describePid(pid)) " +
                "notification \(notification.rawValue) (AXError \(setupError.rawValue))"
            axErrorLog(
                logSegments(
                    "Failed to setup underlying AXObserver for \(describePid(pid))",
                    "notification \(notification.rawValue)",
                    "error: \(setupError.rawValue)"))
            return .failure(.observerSetupFailed(details: errorMsg))
        }

        self.subscriptions[key, default: [:]][token.id] = handler
        self.subscriptionTokens[token.id] = key

        axInfoLog(
            logSegments(
                "Successfully subscribed handler (token: \(token.id)) for \(describePid(pid))",
                "notification: \(notification.rawValue)"))
        return .success(token)
    }

    public func unsubscribe(token: SubscriptionToken) throws {
        self.subscriptionsLock.lock()
        defer { subscriptionsLock.unlock() }

        guard let key = subscriptionTokens.removeValue(forKey: token.id) else {
            axErrorLog("Unsubscribe failed: Token ID \(token.id) not found.")
            throw AccessibilityError.tokenNotFound(tokenId: token.id)
        }

        guard var handlersForKey = subscriptions[key] else {
            let tokenKeyDescription = "token \(token.id) (key: \(key))"
            axWarningLog(
                logSegments(
                    "Handler for \(tokenKeyDescription) missing in subscriptions dictionary",
                    "token existed"))
            return
        }
        guard handlersForKey.removeValue(forKey: token.id) != nil else { return }

        self.subscriptions[key] = handlersForKey
        axInfoLog(
            logSegments(
                "Successfully unsubscribed handler (token: \(token.id)) for \(describePid(key.pid))",
                "notification: \(key.notification.rawValue)"))
        if handlersForKey.isEmpty {
            self.subscriptions.removeValue(forKey: key)
            axDebugLog(
                logSegments(
                    "No handlers left for \(describePid(key.pid))",
                    "notification: \(key.notification.rawValue). Key removed from subscriptions"))
            if let targetPid = key.pid {
                cleanupUnderlyingObserverNotification(forPid: targetPid, notification: key.notification)
            }
        } else {
            self.subscriptions[key] = handlersForKey
        }
    }

    public func removeAllObservers() {
        axInfoLog("Removing all observers and subscriptions globally.")
        self.subscriptionsLock.lock()
        defer { subscriptionsLock.unlock() }

        removeAllTokens()

        if !self.observers.isEmpty || !self.subscriptions.isEmpty || !self.subscriptionTokens.isEmpty {
            axWarningLog(
                "removeAllObservers: observers, subscriptions, or tokens list not empty after mass unsubscribe. " +
                    "observers: \(self.observers.count), subscriptions: \(self.subscriptions.count), " +
                    "tokens: \(self.subscriptionTokens.count)")
            self.observers.removeAll()
            self.subscriptions.removeAll()
            self.subscriptionTokens.removeAll()
        }
        axInfoLog("All observers and subscriptions have been cleared.")
    }

    public func removeAllObservers(for pid: pid_t) {
        axInfoLog("Removing all observers and subscriptions for PID \(pid)")
        let tokensForPid = self.subscriptionTokens.filter { $0.value.pid == pid }.map(\.key)
        for tokenId in tokensForPid {
            try? self.unsubscribe(token: SubscriptionToken(id: tokenId))
        }
    }

    public func isKeyRegistered(pid: pid_t?, notification: AXNotification) -> Bool {
        let key = AXNotificationSubscriptionKey(pid: pid, notification: notification)
        return self.subscriptions[key]?.isEmpty == false
    }
}

// MARK: - Private Helpers

@MainActor
extension AXObserverCenter {
    private func removeAllTokens() {
        for (tokenId, key) in self.subscriptionTokens {
            guard var handlers = subscriptions[key] else { continue }
            handlers.removeValue(forKey: tokenId)
            if handlers.isEmpty {
                self.subscriptions.removeValue(forKey: key)
                self.cleanupUnderlyingObserverNotification(forPid: key.pid, notification: key.notification)
            } else {
                self.subscriptions[key] = handlers
            }
        }
        self.subscriptionTokens.removeAll()
    }

    // MARK: - Internal AXObserver Management (previously addObserver / removeObserver)

    /// Ensures an AXObserver is created for the PID and the notification is added to it.
    /// This is called by `subscribe`.
    private func setupUnderlyingObserver(
        forPid pid: pid_t?,
        forElement element: Element?,
        notification: AXNotification) -> AXError
    {
        let targetPid = pid ?? 0
        self.logObserverSetup(targetPid: targetPid, element: element, notification: notification)
        guard let observer = getOrCreateObserver(for: targetPid) else {
            axErrorLog("Failed to get/create AXObserver for effective PID \(targetPid) during setup.")
            return .failure
        }

        let elementToObserveAXUI = self.elementForObservation(
            pid: pid,
            targetPid: targetPid,
            element: element,
            notification: notification)

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let error = AXObserverAddNotification(
            observer,
            elementToObserveAXUI,
            notification.rawValue as CFString,
            selfPtr)

        self.logObserverAddResult(targetPid: targetPid, notification: notification, error: error)
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
        pid: pid_t?,
        targetPid: pid_t,
        element: Element?,
        notification: AXNotification) -> AXUIElement
    {
        if let specificElement = element {
            axDebugLog(
                logSegments(
                    "Observer for \(describePid(targetPid))",
                    "using provided specific element \(specificElement.briefDescription())",
                    "notification \(notification.rawValue)"))
            return specificElement.underlyingElement
        }

        if pid == nil {
            axDebugLog(
                logSegments(
                    "Global observer: Using system-wide element",
                    "notification \(notification.rawValue)"))
            return AXUIElementCreateSystemWide()
        }

        axDebugLog(
            logSegments(
                "Application observer \(describePid(targetPid))",
                "Using application element",
                "notification \(notification.rawValue)"))
        return AXUIElement.application(pid: targetPid)
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

    /// Called when a subscription is removed and its key might no longer be needed by any handler.
    /// This function will decide if AXObserverRemoveNotification should be called.
    private func cleanupUnderlyingObserverNotification(forPid pid: pid_t?, notification: AXNotification) {
        let targetPid = pid ?? 0
        axDebugLog(
            logSegments(
                "Cleanup check for underlying AXObserver notification for \(describePid(targetPid))",
                "notification: \(notification.rawValue)"))

        let specificKey = AXNotificationSubscriptionKey(pid: pid, notification: notification)
        guard self.subscriptions[specificKey]?.isEmpty ?? true else {
            axDebugLog(
                logSegments(
                    "Specific subscriptions still exist for \(describePid(pid))",
                    "notification: \(notification.rawValue). AXObserver notification retained"))
            return
        }

        guard let observer = getObserver(for: targetPid) else {
            axWarningLog(
                logSegments(
                    "No AXObserver found for \(describePid(targetPid)) during cleanup",
                    "notification: \(notification.rawValue)"))
            return
        }

        let elementToObserve = pid == nil ? AXUIElementCreateSystemWide() : AXUIElement.application(pid: targetPid)
        let error = AXObserverRemoveNotification(observer, elementToObserve, notification.rawValue as CFString)

        if error == .success {
            axInfoLog(
                logSegments(
                    "Successfully removed notification from AXObserver for \(describePid(targetPid))",
                    "key: \(notification.rawValue) during cleanup"))
            self.removeObserverIfUnused(targetPid: targetPid)
        } else {
            axErrorLog(
                logSegments(
                    "Failed to remove notification from AXObserver for \(describePid(targetPid))",
                    "key: \(notification.rawValue)",
                    "error: \(error.rawValue)"))
        }
    }

    private func removeObserverIfUnused(targetPid: pid_t) {
        let hasAnySubscription = self.subscriptions.contains { key, handlers in
            let keyPid = key.pid ?? 0
            return keyPid == targetPid && !handlers.isEmpty
        }
        guard !hasAnySubscription, let observer = getObserver(for: targetPid) else { return }
        CFRunLoopRemoveSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), .defaultMode)
        self.removePidObserverInstance(pid: targetPid)
    }

    // MARK: - Private Methods

    private func getObserver(for pid: pid_t) -> AXObserver? {
        self.observers.first { $0.pid == pid }?.observer
    }

    private func getOrCreateObserver(for pid: pid_t) -> AXObserver? {
        if let existing = getObserver(for: pid) {
            return existing
        }
        return self.createObserver(for: pid)
    }

    private func createObserver(for pid: pid_t) -> AXObserver? {
        var observer: AXObserver?
        let callback = self.makeObserverCallback()

        let error = AXObserverCreateWithInfoCallback(pid, callback, &observer)

        if error == .success, let newObserver = observer {
            // Add to run loop ONCE when observer is created.
            CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(newObserver), .defaultMode)
            axDebugLog("Added run loop source for new observer PID \(pid)")

            let obj = AXObserverObjAndPID(observer: newObserver, pid: pid)
            self.observers.append(obj)
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
        axDebugLog("Removed AXObserver instance for effective PID \(pid).")
    }

    // MARK: - Main Notification Processing (Called by global callbacks)

    @MainActor // Ensure this runs on the main actor as handlers are @MainActor
    private func processNotification(
        pid: pid_t,
        notification: AXNotification,
        rawElement: AXUIElement,
        nsUserInfo: [String: Any]?)
    {
        self.subscriptionsLock.lock()
        defer { subscriptionsLock.unlock() }

        // Construct keys for both specific PID and global (nil PID)
        let specificKey = AXNotificationSubscriptionKey(pid: pid, notification: notification)
        let globalKey = AXNotificationSubscriptionKey(pid: nil, notification: notification)

        var handlersToCall: [AXNotificationSubscriptionHandler] = []

        // Check for handlers specific to this PID and notification
        if let specificHandlers = subscriptions[specificKey] {
            handlersToCall.append(contentsOf: specificHandlers.values)
        }

        // Check for global handlers for this notification (if not already covered by specific PID match)
        // This ensures global handlers are called even if a specific PID handler also exists for the same notification
        // type.
        if let globalHandlers = subscriptions[globalKey] {
            handlersToCall.append(contentsOf: globalHandlers.values)
        }

        // Deduplicate handlers if any subscribed to both specific and global for the same notification (though unlikely
        // with UUID keys)
        // let uniqueHandlers = Array(Set(handlersToCall)) // Set requires AXNotificationSubscriptionHandler to be
        // Hashable, which it might not be (closure).
        // For now, direct invocation. If a handler is in both lists, it will be called twice.
        // This design assumes handlers are distinct or idempotent if registered for both global and specific.

        if handlersToCall.isEmpty {
            // axDebugLog("No handlers registered for PID \(pid), Notification \(notification.rawValue).")
            return
        }

        // axDebugLog("Processing notification for PID \(pid), Notification \(notification.rawValue). Invoking
        // \(handlersToCall.count) handlers.")

        for handler in handlersToCall {
            handler(pid, notification, rawElement, nsUserInfo)
        }
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

// swiftlint:enable file_length
