// NotificationWatcher.swift - Provides an object-oriented way to observe accessibility notifications.

import ApplicationServices
import Foundation

enum AXGlobalObserverRetryPolicy {
    static let delays: [Duration] = [.milliseconds(500), .seconds(2), .seconds(8)]
    static let maximumAttempts = AXGlobalObserverRetryPolicy.delays.count

    static func sleep(beforeAttempt attempt: Int) async throws {
        guard self.delays.indices.contains(attempt - 1) else { return }
        try await Task.sleep(for: self.delays[attempt - 1])
    }
}

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
        self.globalApplicationMonitor = nil
        self.globalRetrySleep = AXGlobalObserverRetryPolicy.sleep
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
        self.globalApplicationMonitor = nil
        self.globalRetrySleep = AXGlobalObserverRetryPolicy.sleep
    }

    /// Initializes a watcher for a specific process ID (PID).
    public init(forPID pid: pid_t, notification: AXNotification, handler: @escaping AXNotificationSubscriptionHandler) {
        self.target = .pid(pid)
        self.notification = notification
        self.handler = handler
        self.registry = AXObserverCenter.shared
        self.globalApplicationMonitor = nil
        self.globalRetrySleep = AXGlobalObserverRetryPolicy.sleep
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
        self.globalApplicationMonitor = nil
        self.globalRetrySleep = AXGlobalObserverRetryPolicy.sleep
    }

    /// Initializes a watcher for a global notification (any application).
    public init(globalNotification notification: AXNotification, handler: @escaping AXNotificationSubscriptionHandler) {
        self.target = .global
        self.notification = notification
        self.handler = handler
        self.registry = AXObserverCenter.shared
        self.globalApplicationMonitor = AXWorkspaceApplicationMonitor()
        self.globalRetrySleep = AXGlobalObserverRetryPolicy.sleep
        let logMessage = "NotificationWatcher initialized for global notification: \(notification.rawValue)"
        axDebugLog(logMessage)
    }

    init(
        globalNotification notification: AXNotification,
        registry: any AXObservationRegistry,
        applicationMonitor: any AXGlobalApplicationMonitoring,
        retrySleep: @escaping @Sendable (Int) async throws -> Void = AXGlobalObserverRetryPolicy.sleep,
        handler: @escaping AXNotificationSubscriptionHandler)
    {
        self.target = .global
        self.notification = notification
        self.handler = handler
        self.registry = registry
        self.globalApplicationMonitor = applicationMonitor
        self.globalRetrySleep = retrySleep
    }

    deinit {
        axDebugLog("NotificationWatcher deinit")
        let token = self.subscriptionToken
        let globalTokens = Array(self.globalSubscriptionTokens.values)
        let globalRegistrationTasks = self.globalRegistrationTasks.values.map(\.task)
        let globalRetryTasks = self.globalRetryTasks.values.map(\.task)
        let registry = self.registry
        let applicationMonitor = self.globalApplicationMonitor
        for task in globalRegistrationTasks {
            task.cancel()
        }
        for task in globalRetryTasks {
            task.cancel()
        }
        Task { @MainActor in
            applicationMonitor?.stop()
            if let token {
                try? registry.unsubscribe(token: token)
            }
            for token in globalTokens {
                try? registry.unsubscribe(token: token)
            }
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

        if case .global = self.target {
            try self.startGlobalObservation()
            return
        }

        var effectivePid: pid_t = 0
        var elementForSubscription: Element? // For element-specific, pass the element to subscribe
        var targetDescription: String

        switch self.target {
        case let .element(element):
            targetDescription = element.briefDescription()
            elementForSubscription = element
            guard let pidForSubscription = element.pid() else {
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
            preconditionFailure("Global observation must use native process fan-out")
        }

        let logStart =
            "NotificationWatcher starting for target: \(targetDescription) " +
            "(PID: \(effectivePid)), notification: \(self.notification.rawValue)"
        axInfoLog(logStart)

        let subscribeResult = self.registry.subscribeProcess(
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
        if case .global = self.target {
            self.stopGlobalObservation()
            return
        }
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

    private struct GlobalRegistrationTask {
        let id: UUID
        let task: Task<Void, Never>
    }

    private struct GlobalRetryTask {
        let id: UUID
        let task: Task<Void, Never>
    }

    private let target: ObservationTarget
    private let notification: AXNotification
    private let handler: AXNotificationSubscriptionHandler
    private let registry: any AXObservationRegistry
    private let globalApplicationMonitor: (any AXGlobalApplicationMonitoring)?
    private let globalRetrySleep: @Sendable (Int) async throws -> Void
    private var subscriptionToken: SubscriptionToken?
    private var globalSubscriptionTokens: [pid_t: SubscriptionToken] = [:]
    private var globalRegistrationTasks: [pid_t: GlobalRegistrationTask] = [:]
    private var globalRegistrationRefreshRequests: Set<pid_t> = []
    private var globalRetryTasks: [pid_t: GlobalRetryTask] = [:]
    private var isObserving: Bool = false
}

@MainActor
extension NotificationWatcher {
    private func startGlobalObservation() throws {
        guard let globalApplicationMonitor else {
            throw AccessibilityError.observerSetupFailed(details: "Global application lifecycle monitor unavailable")
        }

        // Process registration is intentionally asynchronous: a wedged AX endpoint
        // must never keep the lifecycle monitor or its caller on the main actor.
        self.isObserving = true
        globalApplicationMonitor.start(
            onLaunch: { [weak self] pid in
                self?.handleGlobalLaunch(pid)
            },
            onTermination: { [weak self] pid in
                self?.cancelGlobalRegistration(pid)
                self?.cancelGlobalRetry(pid)
                self?.globalRegistrationRefreshRequests.remove(pid)
                self?.unsubscribeGlobalProcess(pid)
            })

        let processIdentifiers = Array(Set(globalApplicationMonitor.runningProcessIdentifiers)).sorted()
        for pid in processIdentifiers where self.globalRegistrationTasks[pid] == nil {
            self.startGlobalRegistration(pid, retryAttempt: 0)
        }

        axInfoLog(
            "Global observer started; scheduling \(processIdentifiers.count) process registrations for " +
                self.notification.rawValue)
    }

    private func stopGlobalObservation() {
        guard self.isObserving ||
            !self.globalSubscriptionTokens.isEmpty ||
            !self.globalRegistrationTasks.isEmpty ||
            !self.globalRetryTasks.isEmpty
        else { return }
        self.isObserving = false
        self.globalApplicationMonitor?.stop()
        self.cancelAllGlobalRegistrations()
        self.cancelAllGlobalRetries()
        self.globalRegistrationRefreshRequests.removeAll()
        for pid in self.globalSubscriptionTokens.keys.sorted() {
            self.unsubscribeGlobalProcess(pid)
        }
        axInfoLog("Global observer stopped for \(self.notification.rawValue)")
    }

    private func handleGlobalLaunch(_ pid: pid_t) {
        guard self.isObserving, pid > 0, self.globalSubscriptionTokens[pid] == nil else { return }
        self.cancelGlobalRetry(pid)
        if self.globalRegistrationTasks[pid] != nil {
            self.globalRegistrationRefreshRequests.insert(pid)
            return
        }
        self.startGlobalRegistration(pid, retryAttempt: 0)
    }

    private func startGlobalRegistration(_ pid: pid_t, retryAttempt: Int) {
        guard self.isObserving,
              pid > 0,
              self.globalSubscriptionTokens[pid] == nil,
              self.globalRegistrationTasks[pid] == nil
        else { return }

        let id = UUID()
        let registry = self.registry
        let notification = self.notification
        let handler = self.handler
        let task = Task { @MainActor [weak self] in
            let result = await registry.subscribeProcessAsync(
                pid: pid,
                element: nil,
                notification: notification,
                handler: handler)
            guard let self else {
                if case let .success(token) = result {
                    try? registry.unsubscribe(token: token)
                }
                return
            }
            self.completeGlobalRegistration(
                pid,
                id: id,
                retryAttempt: retryAttempt,
                result: result)
        }
        self.globalRegistrationTasks[pid] = GlobalRegistrationTask(id: id, task: task)
    }

    private func completeGlobalRegistration(
        _ pid: pid_t,
        id: UUID,
        retryAttempt: Int,
        result: Result<SubscriptionToken, AccessibilityError>)
    {
        guard self.globalRegistrationTasks[pid]?.id == id else {
            if case let .success(token) = result {
                try? self.registry.unsubscribe(token: token)
            }
            return
        }
        self.globalRegistrationTasks.removeValue(forKey: pid)

        guard self.isObserving else {
            if case let .success(token) = result {
                try? self.registry.unsubscribe(token: token)
            }
            return
        }

        switch result {
        case let .success(token):
            self.globalRegistrationRefreshRequests.remove(pid)
            self.globalSubscriptionTokens[pid] = token
            if retryAttempt > 0 {
                axInfoLog("Global observer recovered registration for PID \(pid) on retry \(retryAttempt)")
            }
        case let .failure(error):
            axWarningLog("Global observer skipped PID \(pid): \(error.localizedDescription)")
            if self.globalRegistrationRefreshRequests.remove(pid) != nil {
                self.startGlobalRegistration(pid, retryAttempt: retryAttempt)
                return
            }
            self.scheduleGlobalRetry(pid, attempt: retryAttempt + 1, lastError: error)
        }
    }

    private func scheduleGlobalRetry(_ pid: pid_t, attempt: Int, lastError: AccessibilityError) {
        guard self.isObserving else { return }
        guard attempt <= AXGlobalObserverRetryPolicy.maximumAttempts else {
            axWarningLog(
                "Global observer exhausted retries for PID \(pid): \(lastError.localizedDescription)")
            return
        }
        guard self.globalRetryTasks[pid] == nil else { return }

        let retrySleep = self.globalRetrySleep
        let id = UUID()
        let task = Task { @MainActor [weak self] in
            do {
                try await retrySleep(attempt)
            } catch {
                return
            }
            guard !Task.isCancelled, let self else { return }
            guard self.globalRetryTasks[pid]?.id == id else { return }
            self.globalRetryTasks.removeValue(forKey: pid)
            guard self.isObserving else { return }
            self.startGlobalRegistration(pid, retryAttempt: attempt)
        }
        self.globalRetryTasks[pid] = GlobalRetryTask(id: id, task: task)
    }

    private func cancelGlobalRegistration(_ pid: pid_t) {
        self.globalRegistrationTasks.removeValue(forKey: pid)?.task.cancel()
    }

    private func cancelAllGlobalRegistrations() {
        for registration in self.globalRegistrationTasks.values {
            registration.task.cancel()
        }
        self.globalRegistrationTasks = [:]
        self.globalRegistrationRefreshRequests.removeAll()
    }

    private func cancelGlobalRetry(_ pid: pid_t) {
        self.globalRetryTasks.removeValue(forKey: pid)?.task.cancel()
    }

    private func cancelAllGlobalRetries() {
        for retry in self.globalRetryTasks.values {
            retry.task.cancel()
        }
        self.globalRetryTasks = [:]
    }

    private func unsubscribeGlobalProcess(_ pid: pid_t) {
        guard let token = self.globalSubscriptionTokens.removeValue(forKey: pid) else { return }
        do {
            try self.registry.unsubscribe(token: token)
        } catch {
            axWarningLog("Global observer cleanup failed for PID \(pid): \(error.localizedDescription)")
        }
    }
}
