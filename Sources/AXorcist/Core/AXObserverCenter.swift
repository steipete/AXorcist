//
//  AXObserverCenter.swift
//  AXorcist
//
//  A centralized manager for AXObserver instances
//

import ApplicationServices
import Foundation

/// Callback type for observer notifications
// public typealias AXObserverHandler = @MainActor (pid_t, AXNotification, AXObserver, AXUIElement, CFDictionary?) -> Void // Old handler

/// New callback type for subscriptions. The AXObserver and AXUIElement might be less relevant to the direct subscriber
/// if the Center abstracts them, or they can be added back if deemed necessary.
public typealias AXNotificationSubscriptionHandler = @MainActor (/*element: Element,*/ pid_t, AXNotification, _ rawElement: AXUIElement, _ nsUserInfo: [String: Any]?) -> Void

/// Key for tracking registered notifications. Can allow nil PID for global observers for a specific notification type.
public struct AXNotificationSubscriptionKey: Hashable {
    let pid: pid_t? // Optional to allow for global observers for a specific notification
    let notification: AXNotification
}

/// Key and PID pair for tracking registered notifications
public struct AXObserverKeyAndPID: Hashable {
    let pid: pid_t
    let key: AXNotification
}

/// Observer and PID pair for tracking active observers
public struct AXObserverObjAndPID {
    var observer: AXObserver
    var pid: pid_t
}

/// Centralized manager for AXObserver instances
@MainActor
public class AXObserverCenter {
    /// Shared instance
    public static let shared = AXObserverCenter()

    // Private storage
    private var observers: [AXObserverObjAndPID] = []
    // private var observerKeys: [AXObserverKeyAndPID] = [] // Old tracking for single handler

    /// Stores multiple handlers per notification key (and optional PID)
    private var subscriptions: [AXNotificationSubscriptionKey: [UUID: AXNotificationSubscriptionHandler]] = [:]
    private var subscriptionTokens: [UUID: AXNotificationSubscriptionKey] = [:]
    private let subscriptionsLock = NSLock() // Added subscriptionsLock

    /// Public token for unsubscribing
    public struct SubscriptionToken: Hashable {
        let id: UUID
    }

    /// Handler to be called when notifications are received - To be replaced by subscriptions model
    // public var handler: AXObserverHandler?

    /// All active observers
    public var activeObservers: [AXObserverObjAndPID] {
        return observers
    }

    /// All registered observer keys
    public var registeredKeys: [AXNotificationSubscriptionKey] { // Updated to use new key type
        // return observerKeys // Old way
        return Array(subscriptions.keys)
    }

    private init() {}

    // MARK: - Public Subscription API

    @MainActor
    public func subscribe(
        pid: pid_t? = nil, // If nil, observer is for system-wide notifications
        element: Element? = nil, // The specific element to observe, if any. If nil with a pid, observes the app.
        notification: AXNotification,
        handler: @escaping AXNotificationSubscriptionHandler
    ) -> Result<SubscriptionToken, AccessibilityError> {
        // Pre-construct log message
        let elementDescriptionForLog = element?.briefDescription() ?? "N/A"
        let logMessage = "Subscribe request for PID \(String(describing: pid)), Element: \(elementDescriptionForLog), notification: \(notification.rawValue)"
        axDebugLog(logMessage)

        let token = SubscriptionToken(id: UUID()) // Corrected initializer
        let key = AXNotificationSubscriptionKey(pid: pid, notification: notification)

        // Determine the effective pid and element for the underlying observer
        let targetPid = pid ?? 0 // Use 0 for system-wide
        var elementForUnderlyingObserver: AXUIElement? = element?.underlyingElement

        if pid != nil && elementForUnderlyingObserver == nil {
            // If pid is provided but no specific element, observe the application element
            elementForUnderlyingObserver = AXUIElementCreateApplication(targetPid)
            // If elementForUnderlyingObserver is still nil, it's an error
            guard elementForUnderlyingObserver != nil else {
                let errorMsg = "Failed to get application element for PID: \(targetPid) for notification \(notification.rawValue)"
                axErrorLog(errorMsg)
                return .failure(.observerSetupFailed(details: errorMsg))
            }
        }

        subscriptionsLock.lock()
        defer { subscriptionsLock.unlock() }

        let setupError = setupUnderlyingObserver(forPid: pid, forElement: element, notification: notification)
        if setupError != .success {
            let errorMsg = "Failed to setup underlying AXObserver for PID \(String(describing: pid)), notification \(notification.rawValue). Error: \(setupError.rawValue)"
            axErrorLog(errorMsg)
            return .failure(.observerSetupFailed(details: errorMsg))
        }

        subscriptions[key, default: [:]][token.id] = handler
        subscriptionTokens[token.id] = key

        axInfoLog("Successfully subscribed handler (token: \(token.id)) for PID \(String(describing: pid)), notification: \(notification.rawValue)")
        return .success(token)
    }

    @MainActor
    public func unsubscribe(token: SubscriptionToken) throws {
        subscriptionsLock.lock()
        defer { subscriptionsLock.unlock() }

        guard let key = subscriptionTokens.removeValue(forKey: token.id) else {
            axErrorLog("Unsubscribe failed: Token ID \(token.id) not found.")
            throw AccessibilityError.tokenNotFound(tokenId: token.id)
        }

        guard var handlersForKey = subscriptions[key] else {
            axWarningLog("Handler for token \(token.id) (key: \(key)) not found in subscriptions dictionary during unsubscribe, though token existed.")
            return
        }
        if handlersForKey.removeValue(forKey: token.id) != nil {
            subscriptions[key] = handlersForKey // Update with the modified dictionary
            axInfoLog("Successfully unsubscribed handler (token: \(token.id)) for key PID: \(String(describing: key.pid)), notification: \(key.notification.rawValue)")
            if handlersForKey.isEmpty {
                subscriptions.removeValue(forKey: key)
                axDebugLog("No handlers left for key PID: \(String(describing: key.pid)), notification: \(key.notification.rawValue). Key removed from subscriptions.")
                // Now, potentially clean up the underlying AXObserver notification
                if let targetPid = key.pid { // Only act if PID is not nil
                    cleanupUnderlyingObserverNotification(forPid: targetPid, notification: key.notification)
                }
            } else {
                subscriptions[key] = handlersForKey // Update with the modified dictionary
            }
        }
    }

    // MARK: - Internal AXObserver Management (previously addObserver / removeObserver)

    /// Ensures an AXObserver is created for the PID and the notification is added to it.
    /// This is called by `subscribe`.
    private func setupUnderlyingObserver(forPid pid: pid_t?, forElement element: Element?, notification: AXNotification) -> AXError {
        let targetPid = pid ?? 0 // Use 0 for system-wide if pid is nil
        let elementDescriptionForLog = element?.briefDescription() ?? "N/A"
        axDebugLog("Setting up underlying AXObserver for effective PID \(targetPid), Element: \(elementDescriptionForLog), notification: \(notification.rawValue)")

        let observer = getOrCreateObserver(for: targetPid)
        guard let observer = observer else {
            axErrorLog("Failed to get/create AXObserver for effective PID \(targetPid) during setup.")
            return .failure
        }

        // Determine the element to observe on
        let elementToObserveAXUI: AXUIElement
        if let specificElement = element { // If a specific element is provided for the subscription
            elementToObserveAXUI = specificElement.underlyingElement
            axDebugLog("Observer for PID \(targetPid): Using provided specific element \(specificElement.briefDescription()) for notification \(notification.rawValue).")
        } else if pid == nil { // Global observation, no specific element provided
            elementToObserveAXUI = AXUIElementCreateSystemWide()
            axDebugLog("Global observer: Using system-wide element for notification \(notification.rawValue).")
        } else { // Application-specific observation, no specific element provided
            elementToObserveAXUI = AXUIElement.application(pid: targetPid)
            axDebugLog("Application observer (PID: \(targetPid)): Using application element for notification \(notification.rawValue).")
        }

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let error = AXObserverAddNotification(observer, elementToObserveAXUI, notification.rawValue as CFString, selfPtr)

        if error == .success {
            axInfoLog("Successfully ensured AXObserver notification for effective PID \(targetPid), key: \(notification.rawValue)")
        } else {
            axErrorLog("Failed to add notification to AXObserver for effective PID \(targetPid), key: \(notification.rawValue), error: \(error.rawValue)")
        }
        return error
    }

    /// Called when a subscription is removed and its key might no longer be needed by any handler.
    /// This function will decide if AXObserverRemoveNotification should be called.
    private func cleanupUnderlyingObserverNotification(forPid pid: pid_t?, notification: AXNotification) { // pid is now optional
        let targetPid = pid ?? 0 // Use 0 for global observers if pid is nil
        axDebugLog("Cleanup check for underlying AXObserver notification for effective PID \(targetPid), notification: \(notification.rawValue)")

        let specificKey = AXNotificationSubscriptionKey(pid: pid, notification: notification) // This key uses the original optional pid

        // If there are no more subscriptions for this specific key (pid can be nil here)
        if subscriptions[specificKey]?.isEmpty ?? true {
            axInfoLog("No specific subscriptions remain for key (PID: \(String(describing: pid)), notification: \(notification.rawValue)). Removing from AXObserver.")
            guard let observer = getObserver(for: targetPid) else { // Use effective PID to get observer
                axWarningLog("No AXObserver found for effective PID \(targetPid) during cleanup. Notification: \(notification.rawValue)")
                return
            }

            let elementToObserve: AXUIElement
            if pid == nil { // Global observation being removed
                elementToObserve = AXUIElementCreateSystemWide()
            } else { // Application-specific observation being removed
                elementToObserve = AXUIElement.application(pid: targetPid)
            }

            let error = AXObserverRemoveNotification(observer, elementToObserve, notification.rawValue as CFString)

            if error == .success {
                axInfoLog("Successfully removed notification from AXObserver for effective PID \(targetPid), key: \(notification.rawValue) during cleanup.")
                // Now check if the AXObserver itself for this effective PID (0 for global) can be removed.
                var hasAnySubscriptionForEffectivePid = false
                for (key, handlers) in subscriptions {
                    let keyEffectivePid = key.pid ?? 0
                    if keyEffectivePid == targetPid && !(handlers.isEmpty) {
                        hasAnySubscriptionForEffectivePid = true
                        break
                    }
                }
                if !hasAnySubscriptionForEffectivePid {
                    axDebugLog("No subscriptions of any kind remain for effective PID \(targetPid). Removing AXObserver instance.")
                    CFRunLoopRemoveSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), .defaultMode)
                    removePidObserverInstance(pid: targetPid) // Use effective PID to remove observer instance
                }
            } else {
                axErrorLog("Failed to remove notification from AXObserver for effective PID \(targetPid), key: \(notification.rawValue) during cleanup, error: \(error.rawValue)")
            }
        } else {
            axDebugLog("Specific subscriptions still exist for key (PID: \(String(describing: pid)), notification: \(notification.rawValue)). AXObserver notification retained.")
        }
    }

    /// Remove all observers and all subscriptions.
    @MainActor
    public func removeAllObservers() {
        axInfoLog("Removing all observers and subscriptions globally.")
        subscriptionsLock.lock()
        defer { subscriptionsLock.unlock() }

        // Unsubscribe all known tokens
        for tokenID in subscriptionTokens.keys {
            if let key = subscriptionTokens[tokenID] { // Safely unwrap
                if var handlersForKey = subscriptions[key] {
                    handlersForKey.removeValue(forKey: tokenID)
                    if handlersForKey.isEmpty {
                        subscriptions.removeValue(forKey: key)
                        // Potential cleanup of underlying observer if no subscriptions remain for this specific key
                        cleanupUnderlyingObserverNotification(forPid: key.pid, notification: key.notification)
                    } else {
                        subscriptions[key] = handlersForKey
                    }
                }
            }
        }
        subscriptionTokens.removeAll()

        // After all unsubscriptions, observers and subscriptions should be empty.
        if !self.observers.isEmpty || !self.subscriptions.isEmpty || !self.subscriptionTokens.isEmpty { // Added self.
            axWarningLog("removeAllObservers: observers, subscriptions, or tokens list not empty after mass unsubscribe. observers: \(self.observers.count), subscriptions: \(self.subscriptions.count), tokens: \(self.subscriptionTokens.count)") // Added self.
            // Force clear for safety, though unsubscribe should handle it.
            self.observers.removeAll() // Added self.
            self.subscriptions.removeAll() // Added self.
            self.subscriptionTokens.removeAll() // Added self.
        }
        axInfoLog("All observers and subscriptions have been cleared.")
    }

    /// Remove all observers for a specific process
    public func removeAllObservers(for pid: pid_t) {
        axInfoLog("Removing all observers and subscriptions for PID \(pid)")
        let tokensForPid = subscriptionTokens.filter { $0.value.pid == pid }.map { $0.key }
        for tokenId in tokensForPid {
            try? unsubscribe(token: SubscriptionToken(id: tokenId))
        }
        // Also handle global observers that might have been tied to this app if pid was 0 initially
        // but that logic is complex and might be better handled by specific unsubscription.
        // The current loop handles subscriptions explicitly tied to this PID.
    }

    /// Check if a notification key is registered for a process
    public func isKeyRegistered(pid: pid_t?, notification: AXNotification) -> Bool { // pid is now optional
        // return observerKeys.contains { $0.pid == pid && $0.key == notification } // Old way
        let key = AXNotificationSubscriptionKey(pid: pid, notification: notification)
        return subscriptions[key]?.isEmpty == false
    }

    // MARK: - Private Methods

    private func getObserver(for pid: pid_t) -> AXObserver? {
        return observers.first { $0.pid == pid }?.observer
    }

    private func getOrCreateObserver(for pid: pid_t) -> AXObserver? {
        if let existing = getObserver(for: pid) {
            return existing
        }
        return createObserver(for: pid)
    }

    private func createObserver(for pid: pid_t) -> AXObserver? {
        var observer: AXObserver?

        let callback: AXObserverCallbackWithInfo = { _, element, notificationCFString, userInfo, refcon in
            guard let refcon = refcon else { return }
            let center = Unmanaged<AXObserverCenter>.fromOpaque(refcon).takeUnretainedValue()

            var elementPID: pid_t = 0
            AXUIElementGetPid(element, &elementPID)

            // Convert CFString to AXNotification
            guard let axNotification = AXNotification(rawValue: notificationCFString as String) else {
                axWarningLog("Received unknown notification string: \(notificationCFString as String) for PID \(elementPID). Cannot call handler.")
                return
            }

            // Convert CFDictionary to [String: Any]?
            var nsUserInfo: [String: Any]?
            if let cfUserInfo = userInfo as CFDictionary? {
                if let cfDict = cfUserInfo as? [CFString: CFTypeRef] {
                    var tempDict = [String: Any]()
                    for (key, value) in cfDict {
                        tempDict[key as String] = center.convertCFValueToSwift(value)
                    }
                    nsUserInfo = tempDict
                } else {
                    axWarningLog("Could not cast userInfo CFDictionary to Dictionary<CFString, CFTypeRef> for initial conversion.")
                }
            }

            Task { @MainActor in
                // Construct keys for dispatch
                let specificKey = AXNotificationSubscriptionKey(pid: elementPID, notification: axNotification)
                let globalKey = AXNotificationSubscriptionKey(pid: nil, notification: axNotification)

                var handlersToCall: [AXNotificationSubscriptionHandler] = []

                if let specificHandlers = center.subscriptions[specificKey] {
                    handlersToCall.append(contentsOf: specificHandlers.values)
                }
                if let globalHandlers = center.subscriptions[globalKey] {
                    // Avoid duplicate calls if a handler subscribed to both specific PID and global for the same notification
                    // (though UUID keys should prevent direct duplication in the list)
                    handlersToCall.append(contentsOf: globalHandlers.values)
                }

                for handler in handlersToCall {
                    // Pass the original element, pid, notification, and userInfo.
                    // Consider if `Element(element)` should be passed, but that might involve overhead.
                    handler(/*Element(element),*/ elementPID, axNotification, element, nsUserInfo)
                }
            }
        }

        let error = AXObserverCreateWithInfoCallback(pid, callback, &observer)

        if error == .success, let newObserver = observer {
            // Add to run loop ONCE when observer is created.
            CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(newObserver), .defaultMode)
            axDebugLog("Added run loop source for new observer PID \(pid)")

            let obj = AXObserverObjAndPID(observer: newObserver, pid: pid)
            observers.append(obj)
            axDebugLog("Created observer for PID \(pid)")
            return newObserver
        } else {
            axErrorLog("Failed to create observer for PID \(pid), error: \(error.rawValue)")
            return nil
        }
    }

    // private func removeKey(pid: pid_t, key: AXNotification) { // Old method
    //    observerKeys.removeAll { $0.pid == pid && $0.key == key }
    // }

    private func removePidObserverInstance(pid: pid_t) {
        observers.removeAll { $0.pid == pid }
        axDebugLog("Removed AXObserver instance for effective PID \(pid).")
    }

    // MARK: - Helper for userInfo conversion
    private func convertCFValueToSwift(_ cfValue: CFTypeRef?) -> Any? {
        guard let cfValue = cfValue else { return nil }
        let typeID = CFGetTypeID(cfValue)

        switch typeID {
        case CFStringGetTypeID():
            return cfValue as? String
        case CFNumberGetTypeID():
            return cfValue as? NSNumber // Could be Int, Double, Bool (via NSNumber bridging)
        case CFBooleanGetTypeID():
            // Ensure correct conversion for CFBoolean
            if CFEqual(cfValue, kCFBooleanTrue) {
                return true
            } else if CFEqual(cfValue, kCFBooleanFalse) {
                return false
            }
            // Fallback for other CFBoolean representations if any, or if direct Bool bridging works
            if let boolVal = cfValue as? Bool {
                return boolVal
            }
            axWarningLog("Could not convert CFBoolean to Bool: \(String(describing: cfValue))")
            return nil // Or handle as error
        case CFArrayGetTypeID():
            // Swift arrays bridge to CFArray, and CFArray can be cast to NSArray / [AnyObject]
            if let cfArray = cfValue as? [CFTypeRef] { // or cfValue as? NSArray
                return cfArray.compactMap { convertCFValueToSwift($0) }
            }
            axWarningLog("Failed to convert CFArray from userInfo.")
            return cfValue // Return raw CFArray if conversion fails for some reason
        case CFDictionaryGetTypeID():
            if let cfDict = cfValue as? [CFString: CFTypeRef] { // or cfValue as? NSDictionary
                var swiftDict = [String: Any]()
                for (key, value) in cfDict {
                    swiftDict[key as String] = convertCFValueToSwift(value)
                }
                return swiftDict
            }
            axWarningLog("Failed to convert nested CFDictionary from userInfo.")
            return cfValue // Return raw CFDictionary if conversion fails
        case AXUIElementGetTypeID():
            return cfValue as! AXUIElement // Should be safe to force unwrap if type matches
        // Add other common CF types if necessary, e.g., CFURL, CFDate
        default:
            axDebugLog("Unhandled CFTypeRef in convertCFValueToSwift: typeID \(typeID). Value: \(cfValue)")
            return cfValue // Return raw CFTypeRef if unhandled, caller might know what to do
        }
    }

    // Actual callback function that receives notifications
    private func axObserverCallbackWithInfo(
        _ observer: AXObserver!,
        _ axElement: AXUIElement!, // Renamed to axElement
        _ notification: CFString!,
        _ userInfo: CFDictionary?, // This is CFDictionary?, which is correct
        _ refcon: UnsafeMutableRawPointer!
    ) {
        let center = Unmanaged<AXObserverCenter>.fromOpaque(refcon).takeUnretainedValue()
        guard let axNotification = AXNotification(rawValue: notification as String) else {
            axWarningLog("Received unknown notification: \(notification as String)")
            return
        }

        var pid: pid_t = 0
        let pidError = AXUIElementGetPid(axElement, &pid)
        if pidError != .success {
            if let observerInstance = center.observers.first(where: { $0.observer == observer }), observerInstance.pid != 0 {
                pid = observerInstance.pid
                axDebugLog("AXUIElementGetPid failed for observed element. Using PID from observer instance: \(pid). Notification: \(axNotification.rawValue)")
            } else {
                axWarningLog("AXUIElementGetPid failed for observed element and could not determine PID. Notification: \(axNotification.rawValue). Error: \(pidError.rawValue)")
            }
        }

        // Convert CFDictionary to [String: Any]?
        var nsUserInfo: [String: Any]?
        if let cfUserInfo = userInfo {
            nsUserInfo = center.convertCFValueToSwift(cfUserInfo) as? [String: Any]
        }

        // Dispatch to relevant handlers
        // Check for PID-specific subscriptions
        let specificKey = AXNotificationSubscriptionKey(pid: pid, notification: axNotification)
        if let handlers = center.subscriptions[specificKey] {
            axDebugLog("Dispatching to \(handlers.count) PID-specific handlers for PID \(pid), notification \(axNotification.rawValue)")
            for handler in handlers.values {
                handler(pid, axNotification, axElement, nsUserInfo) // Pass raw axElement, handler expects AXUIElement
            }
        }

        // Check for global subscriptions (pid == nil in key)
        let globalKey = AXNotificationSubscriptionKey(pid: nil, notification: axNotification)
        if let globalHandlers = center.subscriptions[globalKey] {
            axDebugLog("Dispatching to \(globalHandlers.count) global handlers for notification \(axNotification.rawValue)")
            for handler in globalHandlers.values {
                handler(pid, axNotification, axElement, nsUserInfo) // Pass raw axElement, handler expects AXUIElement
            }
        }

        if center.subscriptions[specificKey] == nil && center.subscriptions[globalKey] == nil {
            axWarningLog("No handlers found for notification \(axNotification.rawValue).")
        }
    }

    // Global notification callback function
    private func axObserverCallback(
        _ observer: AXObserver,
        _ element: AXUIElement,
        _ notificationName: CFString,
        _ context: UnsafeMutableRawPointer?
    ) {
        // This is the older, simpler callback without userInfo.
        // We will primarily use axObserverCallbackWithInfo if possible.
        // However, some observers might still use this one if not configured for info.

        guard let context = context else {
            axWarningLog("AXObserver callback invoked with nil context.")
            return
        }
        let observerCenter = Unmanaged<AXObserverCenter>.fromOpaque(context).takeUnretainedValue()
        let notification = AXNotification(rawValue: notificationName as String) ?? .created // Fallback if unknown
        // Get PID from stored observer data instead of AXObserverGetPID (which doesn't exist in Swift)
        var appPid: pid_t = 0
        if let observerData = observerCenter.observers.first(where: { $0.observer == observer }) {
            appPid = observerData.pid
        } else {
            // Try to get PID from the element if we couldn't find the observer
            AXUIElementGetPid(element, &appPid)
        }

        Task {
            observerCenter.processNotification(pid: appPid, notification: notification, rawElement: element, nsUserInfo: nil)
        }
    }

    // Global notification callback function WITH USERINFO
    // This is the one we expect to be called by AXObserverAddNotification when userInfo is passed.
    private func axObserverCallbackWithInfo(
        _ observer: AXObserver, // The AXObserver instance that triggered the callback.
        _ element: AXUIElement, // The AXUIElement that the notification is about.
        _ notificationName: CFString, // The name of the notification (e.g., kAXFocusedUIElementChangedNotification).
        _ userInfo: CFDictionary?, // An optional dictionary containing additional information about the notification.
        _ context: UnsafeMutableRawPointer? // User-defined data passed when the observer was registered (self for AXObserverCenter).
    ) {
        guard let context = context else {
            axWarningLog("AXObserver callback (with info) invoked with nil context.")
            return
        }
        let observerCenter = Unmanaged<AXObserverCenter>.fromOpaque(context).takeUnretainedValue()
        let notification = AXNotification(rawValue: notificationName as String)

        guard let axNotification = notification else {
            axWarningLog("Received unknown notification: \(notificationName as String)")
            return
        }

        // Get the PID associated with the observer from our stored data
        // (AXObserverGetPID doesn't exist in Swift)
        var eventPid: pid_t = 0
        if let observerData = observerCenter.observers.first(where: { $0.observer == observer }) {
            eventPid = observerData.pid
        }

        // Try to get the PID of the element that the notification is about, which is more relevant.
        var elementPid: pid_t = 0
        if AXUIElementGetPid(element, &elementPid) == .success {
            eventPid = elementPid // Prefer the element's PID if available
        }

        let swiftUserInfo = observerCenter.convertCFValueToSwift(userInfo) as? [String: Any]

        // Debug logging of the raw callback information
        // axDebugLog("AXObserverCallbackWithInfo: PID=\(eventPid), Notification=\(axNotification.rawValue), Element=\(Element(element).briefDescription()), UserInfo=\(String(describing: swiftUserInfo))")

        Task {
            observerCenter.processNotification(pid: eventPid, notification: axNotification, rawElement: element, nsUserInfo: swiftUserInfo)
        }
    }

    // MARK: - Main Notification Processing (Called by global callbacks)
    @MainActor // Ensure this runs on the main actor as handlers are @MainActor
    fileprivate func processNotification(pid: pid_t, notification: AXNotification, rawElement: AXUIElement, nsUserInfo: [String: Any]?) {
        subscriptionsLock.lock()
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
        // This ensures global handlers are called even if a specific PID handler also exists for the same notification type.
        if let globalHandlers = subscriptions[globalKey] {
            handlersToCall.append(contentsOf: globalHandlers.values)
        }

        // Deduplicate handlers if any subscribed to both specific and global for the same notification (though unlikely with UUID keys)
        // let uniqueHandlers = Array(Set(handlersToCall)) // Set requires AXNotificationSubscriptionHandler to be Hashable, which it might not be (closure).
        // For now, direct invocation. If a handler is in both lists, it will be called twice.
        // This design assumes handlers are distinct or idempotent if registered for both global and specific.

        if handlersToCall.isEmpty {
            // axDebugLog("No handlers registered for PID \(pid), Notification \(notification.rawValue).")
            return
        }

        // axDebugLog("Processing notification for PID \(pid), Notification \(notification.rawValue). Invoking \(handlersToCall.count) handlers.")

        for handler in handlersToCall {
            // The element passed to the handler should ideally be the one from the notification (`rawElement`)
            // wrapped in an `Element` struct.
            // let elementForHandler = Element(rawElement)
            handler(pid, notification, rawElement, nsUserInfo)
        }
    }
}
