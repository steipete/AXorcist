import ApplicationServices
import Foundation

@MainActor
extension AXorcist {
    public func handleGetFocusedElement(command: GetFocusedElementCommand) -> AXResponse {
        GlobalAXLogger.shared.log(AXLogEntry(
            level: .info,
            message: "AXorcist/HandleGetFocused: App '\(String(describing: command.appIdentifier))', " +
                "Attributes: \(command.attributesToReturn?.joined(separator: ", ") ?? "default")"
        ))

        guard let appElement = getApplicationElement(for: command.appIdentifier ?? "focused") else {
            let errorMessage = "AXorcist/HandleGetFocused: Could not get application element for '\(String(describing: command.appIdentifier))'."
            GlobalAXLogger.shared.log(AXLogEntry(level: .error, message: errorMessage))
            return .errorResponse(message: errorMessage, code: .elementNotFound)
        }
        GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "AXorcist/HandleGetFocused: Got app element: \(appElement.briefDescription(option: ValueFormatOption.smart))"))

        guard let focusedElement = appElement.focusedUIElement() else {
            let errorMessage = "AXorcist/HandleGetFocused: No focused element found for application " +
                "'\(String(describing: command.appIdentifier))' " +
                "(\(appElement.briefDescription(option: ValueFormatOption.smart))])."
            GlobalAXLogger.shared.log(AXLogEntry(level: .info, message: errorMessage))
            // This is not necessarily an error, could be a valid state.
            // Return success with an empty payload or specific indication.
            return .successResponse(payload: AnyCodable(NoFocusPayload(message: "No focused element found.")))
        }
        GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "AXorcist/HandleGetFocused: Focused element: \(focusedElement.briefDescription(option: ValueFormatOption.smart))"))

        let attributesToFetch = command.attributesToReturn ?? AXMiscConstants.defaultAttributesToFetch
        let elementData = buildQueryResponse(element: focusedElement, attributesToFetch: attributesToFetch, includeChildrenBrief: command.includeChildrenBrief ?? false)

        return .successResponse(payload: AnyCodable(elementData))
    }
}
