import ApplicationServices
import Foundation

/// Extension providing accessibility notification observation handlers for AXorcist.
///
/// This extension handles:
/// - Setting up AXObserver instances for notifications
/// - Managing notification subscriptions and callbacks
/// - Real-time event monitoring and processing
/// - Element detail extraction for observed events
/// - Cleanup and lifecycle management of observers
@MainActor
extension AXorcist {
    public func handleObserve(command: ObserveCommand) -> AXResponse {
        self.logObservationStart(command)

        let locator = command.locator ?? Locator(criteria: [
            Criterion(attribute: "AXRole", value: AXRoleNames.kAXApplicationRole, matchType: .exact),
        ])

        let elementToObserve: Element
        switch self.resolveObservationTarget(
            appIdentifier: command.appIdentifier,
            pid: command.pid,
            locator: locator,
            maxDepth: command.maxDepthForSearch)
        {
        case let .success(resolvedElement):
            elementToObserve = resolvedElement
        case let .failure(error):
            GlobalAXLogger.shared.log(AXLogEntry(level: .error, message: error.message))
            return error.response
        }

        self.logObservationTarget(elementToObserve)

        let callback = self.makeObservationCallback()
        return self.startObservation(
            element: elementToObserve,
            command: command,
            callback: callback)
    }

    private func logObservationStart(_ command: ObserveCommand) {
        let details = command.includeElementDetails?.joined(separator: ", ") ?? "none"
        let message = [
            "HandleObserve: App \(command.appIdentifier ?? "focused")",
            "Notifications: \(command.notificationName.rawValue)",
            "Details: \(details)",
        ].joined(separator: ", ")
        GlobalAXLogger.shared.log(AXLogEntry(level: .info, message: message))
    }

    private func logObservationTarget(_ element: Element) {
        let message = [
            "HandleObserve: Element to observe:",
            element.briefDescription(option: ValueFormatOption.smart),
        ].joined(separator: " ")
        GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: message))
    }

    private func startObservation(
        element: Element,
        command: ObserveCommand,
        callback: @escaping AXNotificationSubscriptionHandler) -> AXResponse
    {
        switch self.subscribeToObservation(
            pid: element.pid(),
            element: element,
            notification: command.notificationName,
            handler: callback)
        {
        case .success:
            let successMessage = [
                "HandleObserve: Successfully started observing '\(command.notificationName)' on",
                element.briefDescription(option: ValueFormatOption.smart),
            ].joined(separator: " ")
            GlobalAXLogger.shared.log(AXLogEntry(level: .info, message: successMessage))
            return .successResponse(payload: AnyCodable(["message": successMessage]))
        case let .failure(error):
            let details = [
                "HandleObserve: Failed to add observer.",
                "Error: \(error.localizedDescription) (Code: \(error))",
                "Pid: \(element.pid()?.description ?? "N/A")",
                "Notification: \(command.notificationName)",
            ].joined(separator: " ")
            GlobalAXLogger.shared.log(AXLogEntry(level: .error, message: details))
            return .errorResponse(message: details, code: .observationFailed)
        }
    }

    private func makeObservationCallback() -> AXNotificationSubscriptionHandler {
        { _, notification, axUIElement, userInfo in
            let element = Element(axUIElement)
            let userInfoDesc = userInfo.map(String.init(describing:)) ?? "nil"
            let message = [
                "AXObserver CALLBACK:",
                "Element: \(element.briefDescription(option: ValueFormatOption.smart))",
                "Notification: \(notification.rawValue)",
                "UserInfo: \(userInfoDesc)",
            ].joined(separator: " ")
            GlobalAXLogger.shared.log(AXLogEntry(level: .info, message: message))
        }
    }
}
