// NotificationWatcher.swift - Provides an object-oriented way to observe accessibility notifications.

import ApplicationServices
import Foundation

/// Provides a high-level interface for observing accessibility notifications on UI elements or processes.
///
/// NotificationWatcher simplifies the process of:
/// - Subscribing to accessibility notifications for specific elements or processes
/// - Managing notification lifecycle with automatic cleanup
/// - Handling notification callbacks in a type-safe manner
/// - Supporting both element-specific and process-wide notifications
///
/// Example usage:
/// ```swift
/// let watcher = NotificationWatcher(forElement: element, notification: .valueChanged) { element, info in
///     print("Value changed on element")
/// }
/// watcher.start()
/// ```
@MainActor
public class NotificationWatcher {
    // MARK: Lifecycle

    // MARK: - Initializers

    /// Initializes a watcher for a specific UI element.
    public init(
        forElement element: Element,
        notification: AXNotification,
        handler: @escaping AXNotificationSubscriptionHandler)
    {
        self.target = .element(element)
        self.notification = notification
        self.handler = handler
        self.registry = AXObserverCenter.shared
        let logMessage = "NotificationWatcher initialized for element, notification: \(notification.rawValue)"
        axDebugLog(logMessage)
    }

    init(
        forElement element: Element,
        notification: AXNotification,
        registry: any AXObservationRegistry,
        handler: @escaping AXNotificationSubscriptionHandler)
    {
        self.target = .element(element)
        self.notification = notification
        self.handler = handler
        self.registry = registry
    }

    /// Initializes a watcher for a specific process ID (PID).
    public init(forPID pid: pid_t, notification: AXNotification, handler: @escaping AXNotificationSubscriptionHandler) {
        self.target = .pid(pid)
        self.notification = notification
        self.handler = handler
        self.registry = AXObserverCenter.shared
        let logMessage = "NotificationWatcher initialized for PID \(pid), notification: \(notification.rawValue)"
        axDebugLog(logMessage)
    }

    init(
        forPID pid: pid_t,
        notification: AXNotification,
        registry: any AXObservationRegistry,
        handler: @escaping AXNotificationSubscriptionHandler)
    {
        self.target = .pid(pid)
        self.notification = notification
        self.handler = handler
        self.registry = registry
    }

    /// Initializes a watcher for a global notification (any application).
    public init(globalNotification notification: AXNotification, handler: @escaping AXNotificationSubscriptionHandler) {
        self.target = .global
        self.notification = notification
        self.handler = handler
        self.registry = AXObserverCenter.shared
        let logMessage = "NotificationWatcher initialized for global notification: \(notification.rawValue)"
        axDebugLog(logMessage)
    }

    deinit {
        axDebugLog("NotificationWatcher deinit")
        guard let token = self.subscriptionToken else { return }
        let registry = self.registry
        Task { @MainActor in
            try? registry.unsubscribe(token: token)
        }
    }

    // MARK: Public

    /// Indicates whether the watcher is currently observing notifications.
    public var isActive: Bool {
        self.isObserving
    }

    // MARK: - Observation Control

    /// Starts observing the notification.
    ///
    /// - Throws: An `AccessibilityError` if starting the observation fails (e.g., subscription to `AXObserverCenter`
    /// fails).
    public func start() throws {
        guard !self.isObserving else {
            let logMessage =
                "NotificationWatcher for \(self.notification.rawValue) on \(self.target) is already observing."
            axDebugLog(logMessage)
            return
        }

        var effectivePid: pid_t? // For global, pid is nil for subscribe
        var elementForSubscription: Element? // For element-specific, pass the element to subscribe
        var targetDescription: String

        switch self.target {
        case let .element(element):
            targetDescription = element.briefDescription()
            elementForSubscription = element
            let pidForSubscription = element.pid()
            if pidForSubscription == nil {
                let elBrief = element.briefDescription()
                let logMessage = "Cannot start watcher: Element has no PID. Element: \(elBrief)"
                axErrorLog(logMessage)
                throw AccessibilityError.invalidElement
            }
            effectivePid = pidForSubscription
        case let .pid(pid):
            targetDescription = "PID: \(pid)"
            effectivePid = pid
        case .global:
            targetDescription = "Global"
            effectivePid = nil // AXObserverCenter handles pid: nil for global
        }

        let pidToLog = effectivePid ?? 0
        let logStart =
            "NotificationWatcher starting for target: \(targetDescription) " +
            "(PID: \(pidToLog)), notification: \(self.notification.rawValue)"
        axInfoLog(logStart)

        let subscribeResult = self.registry.subscribe(
            pid: effectivePid,
            element: elementForSubscription, // Pass element if target is .element
            notification: self.notification,
            handler: self.handler)

        switch subscribeResult {
        case let .success(token):
            self.subscriptionToken = token
            self.isObserving = true
            axInfoLog("\(logStart) - SUBSCRIBED successfully. Token: \(token.id)")
        case let .failure(error):
            self.isObserving = false // Ensure this is reset
            axErrorLog("\(logStart) - FAILED to subscribe: \(error.localizedDescription)")
            // Rethrow the error, or a new specific one if preferred
            throw error // Or AccessibilityError.genericError("Failed to subscribe: \\(errDesc)")
        }
    }

    /// Stops observing the notification.
    @MainActor
    public func stop() {
        guard self.isObserving, let token = subscriptionToken else {
            // let logMessage = "NotificationWatcher for \(self.notification.rawValue) on \(self.target) is not
            // observing or no token."
            // axDebugLog(logMessage) // Can be noisy
            return
        }

        let logStop = "NotificationWatcher stopping for notification: \(self.notification.rawValue)"
        axInfoLog(logStop)

        do {
            try self.registry.unsubscribe(token: token)
            axInfoLog("\(logStop) - UNSUBSCRIBED successfully. Token: \(token.id)")
        } catch {
            axErrorLog("\(logStop) - FAILED to unsubscribe token \(token.id): \(error.localizedDescription)")
        }
        self.subscriptionToken = nil
        self.isObserving = false
    }

    // MARK: Private

    private enum ObservationTarget {
        case element(Element)
        case pid(pid_t)
        case global
    }

    private let target: ObservationTarget
    private let notification: AXNotification
    private let handler: AXNotificationSubscriptionHandler
    private let registry: any AXObservationRegistry
    private var subscriptionToken: SubscriptionToken?
    private var isObserving: Bool = false
}
