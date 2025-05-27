// ObserverTypes.swift - Types and structs for AXObserver management

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

/// Public token for unsubscribing
public struct SubscriptionToken: Hashable {
    let id: UUID
}
