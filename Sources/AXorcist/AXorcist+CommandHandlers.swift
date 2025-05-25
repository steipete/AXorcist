// AXorcist+CommandHandlers.swift - Command handler methods for AXorcist

import AppKit
import ApplicationServices
import Foundation

// MARK: - Command Handlers Extension
extension AXorcist {

    // Placeholder for getting the focused element.
    // It should accept debug logging parameters and update logs.
    @MainActor
    public func handleGetFocusedElement(
        for appIdentifierOrNil: String? = nil,
        requestedAttributes: [String]? = nil
    ) -> HandlerResponse {
        let appIdentifier = appIdentifierOrNil ?? AXMiscConstants.focusedApplicationKey // Corrected: Use AXMiscConstants.focusedApplicationKey
        axDebugLog("[AXorcist.handleGetFocusedElement] Handling for app: \(appIdentifier)",
                   file: #file,
                   function: #function,
                   line: #line
        )

        guard let appElement = applicationElement(for: appIdentifier) else {
            let errorMsgText = "Application not found: \(appIdentifier)"
            axDebugLog("[AXorcist.handleGetFocusedElement] \(errorMsgText)",
                       file: #file,
                       function: #function,
                       line: #line
            )
            return HandlerResponse(data: nil, error: errorMsgText)
        }
        axDebugLog("[AXorcist.handleGetFocusedElement] Successfully obtained application element for \(appIdentifier)",
                   file: #file,
                   function: #function,
                   line: #line
        )

        var cfValue: CFTypeRef?
        let copyAttributeStatus = AXUIElementCopyAttributeValue(
            appElement.underlyingElement,
            AXAttributeNames.kAXFocusedUIElementAttribute as CFString,
            &cfValue
        )

        guard copyAttributeStatus == .success, let rawAXElement = cfValue else {
            axDebugLog(
                "[AXorcist.handleGetFocusedElement] Failed to copy focused element attribute or it was nil. " +
                    "Status: \(axErrorToString(copyAttributeStatus)). Application: \(appIdentifier)",
                file: #file,
                function: #function,
                line: #line
            )
            return HandlerResponse(
                data: nil,
                error: "Could not get the focused UI element for \(appIdentifier). Ensure a window of the application is focused. AXError: \(axErrorToString(copyAttributeStatus))"
            )
        }

        guard CFGetTypeID(rawAXElement) == AXUIElementGetTypeID() else {
            axDebugLog(
                "[AXorcist.handleGetFocusedElement] Focused element attribute was not an AXUIElement. Application: \(appIdentifier)",
                file: #file,
                function: #function,
                line: #line
            )
            return HandlerResponse(
                data: nil,
                error: "Focused element was not a valid UI element for \(appIdentifier)."
            )
        }

        let focusedElement = Element(rawAXElement as! AXUIElement)
        axDebugLog(
            "[AXorcist.handleGetFocusedElement] Successfully obtained focused element: " +
                "\(focusedElement.briefDescription()) for application \(appIdentifier)",
            file: #file,
            function: #function,
            line: #line
        )

        let (fetchedAttributes, _) = getElementAttributes(
            element: focusedElement,
            attributes: requestedAttributes ?? [],
            outputFormat: .smart
        )

        let elementPathArray = focusedElement.generatePathArray(upTo: appElement)

        let axElement = AXElement(attributes: fetchedAttributes, path: elementPathArray)

        return HandlerResponse(data: AnyCodable(axElement), error: nil)
    }

    // TODO: Add remaining command handler methods here...
    // This is a placeholder file to demonstrate the refactoring approach
    // The complete implementation would include all handle* methods
}
