// ObserverTypes.swift - Types and structs for AXObserver management

import ApplicationServices
import Foundation

/// Handler function type for accessibility notification callbacks.
///
/// This handler is called when an observed accessibility notification occurs.
/// Parameters include the process ID, notification type, raw element reference,
/// and optional user info dictionary. The handler runs on the main actor
/// to ensure UI safety.
public typealias AXNotificationSubscriptionHandler = @MainActor ( /* element: Element, */
    pid_t,
    AXNotification,
    _ rawElement: AXUIElement,
    _ nsUserInfo: [String: Any]?) -> Void

typealias AXObserverAwareNotificationHandler = @MainActor (
    _ observer: AXObserver,
    _ rawElement: AXUIElement,
    _ notification: CFString,
    _ userInfo: CFDictionary?) -> Void

enum AXStoredNotificationHandler {
    case standard(AXNotificationSubscriptionHandler)
    case observerAware(AXObserverAwareNotificationHandler)
}

enum AXObserverSubscriptionError: Error {
    case observerCreationFailed(pid_t)
    case nativeRegistrationFailed(pid_t, AXNotification, AXError)
    case validation(String)

    @MainActor var accessibilityError: AccessibilityError {
        switch self {
        case let .observerCreationFailed(pid):
            .observerSetupFailed(details: "Could not create AXObserver for \(describePid(pid))")
        case let .nativeRegistrationFailed(pid, notification, error):
            .observerSetupFailed(
                details: "Failed to setup underlying AXObserver for \(describePid(pid)) " +
                    "notification \(notification.rawValue) (AXError \(error.rawValue))")
        case let .validation(details):
            .observerSetupFailed(details: details)
        }
    }
}

nonisolated struct AXObserverRawNotificationEvent: @unchecked Sendable {
    let observer: AXObserver
    let element: AXUIElement
    let notification: CFString
    let userInfo: CFDictionary?
}

nonisolated struct AXObserverNotificationEvent: @unchecked Sendable {
    let observer: AXObserver?
    let pid: pid_t
    let notification: AXNotification
    let notificationString: CFString
    let rawElement: AXUIElement
    let rawUserInfo: CFDictionary?
    let userInfo: [String: Any]?
}

/// The single registration boundary used by AXorcist's observer APIs.
@MainActor
protocol AXObservationRegistry: AnyObject, Sendable {
    func subscribeProcess(
        pid: pid_t,
        element: Element?,
        notification: AXNotification,
        handler: @escaping AXNotificationSubscriptionHandler) -> Result<SubscriptionToken, AccessibilityError>

    func subscribeProcessAsync(
        pid: pid_t,
        element: Element?,
        notification: AXNotification,
        handler: @escaping AXNotificationSubscriptionHandler) async -> Result<SubscriptionToken, AccessibilityError>

    func unsubscribe(token: SubscriptionToken) throws
}

extension AXObservationRegistry {
    func subscribeProcessAsync(
        pid: pid_t,
        element: Element?,
        notification: AXNotification,
        handler: @escaping AXNotificationSubscriptionHandler) async -> Result<SubscriptionToken, AccessibilityError>
    {
        self.subscribeProcess(pid: pid, element: element, notification: notification, handler: handler)
    }
}

/// Key for tracking accessibility notification subscriptions.
///
/// Accessibility notification subscription for one exact process.
public struct AXNotificationSubscriptionKey: Hashable {
    /// Process ID to monitor.
    let pid: pid_t

    /// The accessibility notification type to observe.
    let notification: AXNotification
}

/// Exact system registration identity retained until the final matching handler unsubscribes.
struct AXObserverRegistrationKey: Hashable {
    enum Scope: Hashable {
        case process
        case element
    }

    let subscription: AXNotificationSubscriptionKey
    let element: Element
    let scope: Scope

    static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.subscription == rhs.subscription, lhs.scope == rhs.scope else { return false }
        return lhs.scope == .process || lhs.element == rhs.element
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(self.subscription)
        hasher.combine(self.scope)
        if self.scope == .element {
            hasher.combine(self.element)
        }
    }
}

/// Key combining process ID and notification type for observer tracking.
///
/// Used internally to manage active accessibility observers for specific
/// combinations of processes and notification types.
public struct AXObserverKeyAndPID: Hashable {
    /// Process ID being observed.
    let pid: pid_t

    /// Notification type being monitored.
    let key: AXNotification
}

/// Container for an active accessibility observer and its target process.
///
/// Pairs an AXObserver instance with the process ID it's monitoring,
/// used for managing the lifecycle of accessibility observers.
public struct AXObserverObjAndPID {
    /// The active accessibility observer.
    var observer: AXObserver

    /// Process ID that this observer is monitoring.
    var pid: pid_t
}

/// Token returned when subscribing to accessibility notifications.
///
/// Use this token to unsubscribe from notifications when they're no longer needed.
/// The token ensures that only the original subscriber can cancel the subscription.
///
/// ## Usage
///
/// ```swift
/// let token = observerCenter.subscribe(to: .valueChanged, for: pid) { ... }
/// // Later...
/// observerCenter.unsubscribe(token)
/// ```
public nonisolated struct SubscriptionToken: Hashable, Sendable {
    /// Unique identifier for this subscription.
    let id: UUID
}

/// Main-actor-isolated subscription storage. Dispatch snapshots handlers before invoking them,
/// so callbacks can safely unsubscribe themselves or other callbacks.
@MainActor
final class AXObserverSubscriptionStore {
    struct Removal {
        let registration: AXObserverRegistrationKey
        let removedLastHandler: Bool
    }

    private var subscriptions: [AXObserverRegistrationKey: [UUID: AXStoredNotificationHandler]] = [:]
    private var subscriptionTokens: [UUID: AXObserverRegistrationKey] = [:]

    var registeredKeys: [AXNotificationSubscriptionKey] {
        Array(Set(self.subscriptions.keys.map(\.subscription)))
    }

    func add(
        registration: AXObserverRegistrationKey,
        handler: AXStoredNotificationHandler) -> SubscriptionToken
    {
        let token = SubscriptionToken(id: UUID())
        self.subscriptions[registration, default: [:]][token.id] = handler
        self.subscriptionTokens[token.id] = registration
        return token
    }

    func add(
        registration: AXObserverRegistrationKey,
        handler: @escaping AXNotificationSubscriptionHandler) -> SubscriptionToken
    {
        self.add(registration: registration, handler: .standard(handler))
    }

    func remove(token: SubscriptionToken) throws -> Removal {
        guard let registration = self.subscriptionTokens.removeValue(forKey: token.id) else {
            throw AccessibilityError.tokenNotFound(tokenId: token.id)
        }

        guard var handlers = self.subscriptions[registration], handlers.removeValue(forKey: token.id) != nil else {
            return Removal(
                registration: registration,
                removedLastHandler: self.subscriptions[registration]?.isEmpty != false)
        }

        if handlers.isEmpty {
            self.subscriptions.removeValue(forKey: registration)
        } else {
            self.subscriptions[registration] = handlers
        }
        return Removal(registration: registration, removedLastHandler: handlers.isEmpty)
    }

    func removeAll() {
        self.subscriptions.removeAll()
        self.subscriptionTokens.removeAll()
    }

    @discardableResult
    func removeAll(for pid: pid_t) -> Int {
        let tokens = self.tokens(for: pid)
        for token in tokens {
            _ = try? self.remove(token: token)
        }
        return tokens.count
    }

    func tokens(for pid: pid_t) -> [SubscriptionToken] {
        self.subscriptionTokens.compactMap { tokenID, registration in
            registration.subscription.pid == pid ? SubscriptionToken(id: tokenID) : nil
        }
    }

    func registration(for token: SubscriptionToken) -> AXObserverRegistrationKey? {
        self.subscriptionTokens[token.id]
    }

    func handlerCount(for registration: AXObserverRegistrationKey) -> Int {
        self.subscriptions[registration]?.count ?? 0
    }

    func contains(pid: pid_t, notification: AXNotification) -> Bool {
        self.subscriptions.contains { registration, handlers in
            registration.subscription.pid == pid &&
                registration.subscription.notification == notification &&
                !handlers.isEmpty
        }
    }

    func contains(registration: AXObserverRegistrationKey) -> Bool {
        self.subscriptions[registration]?.isEmpty == false
    }

    func containsSubscriptions(forEffectivePID pid: pid_t) -> Bool {
        self.subscriptions.contains { registration, handlers in
            registration.subscription.pid == pid && !handlers.isEmpty
        }
    }

    func dispatch(_ event: AXObserverNotificationEvent) {
        let specificKey = AXNotificationSubscriptionKey(
            pid: event.pid,
            notification: event.notification)
        var handlersToCall: [AXStoredNotificationHandler] = []
        let eventElement = Element(event.rawElement)
        for (registration, handlers) in self.subscriptions {
            let subscription = registration.subscription
            let matchesProcess = subscription == specificKey && registration.scope == .process
            // AXObserver registrations are object-specific. Only application registrations use process scope;
            // element registrations must not fan the callback out to sibling accessibility objects.
            let matchesElement = subscription == specificKey &&
                registration.scope == .element &&
                registration.element == eventElement
            if matchesProcess || matchesElement {
                handlersToCall.append(contentsOf: handlers.values)
            }
        }

        for handler in handlersToCall {
            switch handler {
            case let .standard(standard):
                standard(event.pid, event.notification, event.rawElement, event.userInfo)
            case let .observerAware(observerAware):
                guard let observer = event.observer else { continue }
                observerAware(observer, event.rawElement, event.notificationString, event.rawUserInfo)
            }
        }
    }

    func dispatch(
        pid: pid_t,
        notification: AXNotification,
        rawElement: AXUIElement,
        userInfo: [String: Any]?)
    {
        self.dispatch(AXObserverNotificationEvent(
            observer: nil,
            pid: pid,
            notification: notification,
            notificationString: notification.rawValue as CFString,
            rawElement: rawElement,
            rawUserInfo: nil,
            userInfo: userInfo))
    }
}
