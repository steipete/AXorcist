import ApplicationServices
import CoreFoundation
import Foundation

/// Manages accessibility observers for monitoring UI element changes.
///
/// Legacy raw-callback observer API retained for source compatibility. New code should use
/// ``AXObserverCenter`` or ``NotificationWatcher``. This adapter owns only its logical tokens;
/// native observer creation, bounded registration, late-result cleanup, and removal all remain
/// centralized in ``AXObserverCenter``.
@MainActor
@available(*, deprecated, message: "Use AXObserverCenter or NotificationWatcher for token-based observation")
public final class AXObserverManager {
    // MARK: Lifecycle

    private init() {
        self.observationCenter = .shared
    }

    init(observationCenter: AXObserverCenter) {
        self.observationCenter = observationCenter
    }

    // MARK: Public

    /// Typealias for notification callback - matches AXObserverCallbackWithInfo but without refcon.
    public typealias AXNotificationCallback = (AXObserver, AXUIElement, CFString, CFDictionary?) -> Void

    /// Error types retained by the compatibility API.
    public enum ObserverError: Error {
        case couldNotCreateObserver
        case addNotificationFailed(AXError)
        case other(String)
    }

    /// Singleton instance.
    public static let shared = AXObserverManager()

    /// Add an observer for an element and notification.
    public func addObserver(
        for element: Element,
        notification: AXNotification,
        callback: @escaping AXNotificationCallback) throws
    {
        let key = RegistrationKey(element: element, notification: notification)
        if let registration = self.registrations[key] {
            registration.callback.callback = callback
            return
        }

        guard let pid = element.pid() else {
            throw ObserverError.other("Could not get PID for element")
        }
        let callbackBox = CallbackBox(callback: callback)
        let result = self.observationCenter.subscribeObserverAware(
            pid: pid,
            element: element,
            notification: notification)
        { observer, rawElement, notificationString, userInfo in
            callbackBox.callback(observer, rawElement, notificationString, userInfo)
        }
        switch result {
        case let .success(token):
            self.registrations[key] = Registration(token: token, callback: callbackBox)
        case let .failure(error):
            throw self.compatibilityError(from: error)
        }
    }

    /// Remove the observer owned by this compatibility manager for an element and notification.
    public func removeObserver(for element: Element, notification: AXNotification) throws {
        let key = RegistrationKey(element: element, notification: notification)
        guard let registration = self.registrations[key] else { return }
        let error = self.observationCenter.unsubscribeCompatibility(token: registration.token)
        guard NativeNotificationRegistration.removalConfirmsRegistrationAbsent(error) else {
            throw ObserverError.other("Failed to remove notification: \(error)")
        }
        self.registrations.removeValue(forKey: key)
    }

    /// Remove every observer owned by this compatibility manager without affecting other clients.
    public func removeAllObservers() {
        let registrations = Array(self.registrations.values)
        self.registrations.removeAll()
        for registration in registrations {
            try? self.observationCenter.unsubscribe(token: registration.token)
        }
    }

    // MARK: Private

    private struct RegistrationKey: Hashable {
        let elementID: ObjectIdentifier
        let notification: AXNotification

        init(element: Element, notification: AXNotification) {
            self.elementID = ObjectIdentifier(element.underlyingElement as AnyObject)
            self.notification = notification
        }
    }

    private struct Registration {
        let token: SubscriptionToken
        let callback: CallbackBox
    }

    private final class CallbackBox {
        var callback: AXNotificationCallback

        init(callback: @escaping AXNotificationCallback) {
            self.callback = callback
        }
    }

    private let observationCenter: AXObserverCenter
    private var registrations: [RegistrationKey: Registration] = [:]

    private func compatibilityError(from error: AXObserverSubscriptionError) -> ObserverError {
        switch error {
        case .observerCreationFailed:
            .couldNotCreateObserver
        case let .nativeRegistrationFailed(_, _, nativeError):
            .addNotificationFailed(nativeError)
        case let .validation(details):
            .other(details)
        }
    }
}
