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

/// The single registration boundary used by AXorcist's observer APIs.
@MainActor
protocol AXObservationRegistry: AnyObject, Sendable {
    func subscribe(
        pid: pid_t?,
        element: Element?,
        notification: AXNotification,
        handler: @escaping AXNotificationSubscriptionHandler) -> Result<SubscriptionToken, AccessibilityError>

    func unsubscribe(token: SubscriptionToken) throws
}

/// Key for tracking accessibility notification subscriptions.
///
/// Allows for both process-specific and global notification observers.
/// When `pid` is nil, the subscription applies globally for that notification type.
public struct AXNotificationSubscriptionKey: Hashable {
    /// Process ID to monitor, or nil for global monitoring.
    let pid: pid_t?

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

    private var subscriptions: [AXObserverRegistrationKey: [UUID: AXNotificationSubscriptionHandler]] = [:]
    private var subscriptionTokens: [UUID: AXObserverRegistrationKey] = [:]

    var registeredKeys: [AXNotificationSubscriptionKey] {
        Array(Set(self.subscriptions.keys.map(\.subscription)))
    }

    func add(
        registration: AXObserverRegistrationKey,
        handler: @escaping AXNotificationSubscriptionHandler) -> SubscriptionToken
    {
        let token = SubscriptionToken(id: UUID())
        self.subscriptions[registration, default: [:]][token.id] = handler
        self.subscriptionTokens[token.id] = registration
        return token
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

    func tokens(for pid: pid_t) -> [SubscriptionToken] {
        self.subscriptionTokens.compactMap { tokenID, registration in
            registration.subscription.pid == pid ? SubscriptionToken(id: tokenID) : nil
        }
    }

    func contains(pid: pid_t?, notification: AXNotification) -> Bool {
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
            (registration.subscription.pid ?? 0) == pid && !handlers.isEmpty
        }
    }

    func dispatch(
        pid: pid_t,
        notification: AXNotification,
        rawElement: AXUIElement,
        userInfo: [String: Any]?)
    {
        let specificKey = AXNotificationSubscriptionKey(
            pid: pid,
            notification: notification)
        let globalKey = AXNotificationSubscriptionKey(pid: nil, notification: notification)
        var handlersToCall: [AXNotificationSubscriptionHandler] = []
        let eventElement = Element(rawElement)
        for (registration, handlers) in self.subscriptions {
            let subscription = registration.subscription
            let matchesGlobal = subscription == globalKey
            let matchesProcess = subscription == specificKey && registration.scope == .process
            // AXObserver registrations are object-specific. Only application registrations use process scope;
            // element registrations must not fan the callback out to sibling accessibility objects.
            let matchesElement = subscription == specificKey &&
                registration.scope == .element &&
                registration.element == eventElement
            if matchesGlobal || matchesProcess || matchesElement {
                handlersToCall.append(contentsOf: handlers.values)
            }
        }

        for handler in handlersToCall {
            handler(pid, notification, rawElement, userInfo)
        }
    }
}
