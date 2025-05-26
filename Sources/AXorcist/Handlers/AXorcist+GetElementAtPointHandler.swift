// AXorcist+GetElementAtPointHandler.swift - Handler for GetElementAtPoint command

import Foundation
import ApplicationServices // For CGPoint

extension AXorcist {
    @MainActor
    public func handleGetElementAtPoint(
        for application: String?, // Optional: application context
        point: CGPoint,          // The screen coordinates
        commandId: String?,
        attributesToFetch: [String]? = nil, // Optional: attributes to fetch for the found element
        outputFormat: OutputFormat? = .smart,
        valueFormatOption: ValueFormatOption? = .smart, // Assuming ValueFormatOption exists
        debugCLI: Bool = false
    ) async -> HandlerResponse {
        let effectiveCommandId = commandId ?? "getElementAtPoint_\(UUID().uuidString.prefix(8))"
        axInfoLog("[AXorcist.handleGetElementAtPoint][CmdID: \(effectiveCommandId)] App=\(application ?? "systemWide"), Point=(\(point.x), \(point.y))")

        // 1. Determine the root element for hit-testing
        //    If an application is specified, use that application's main window or element.
        //    Otherwise, use the system-wide element.
        var searchRootElement: Element?
        if let appIdentifier = application {
            searchRootElement = applicationElement(for: appIdentifier)
            if searchRootElement == nil {
                let errorMsg = "Application not found: \(appIdentifier)"
                axErrorLog("[AXorcist.handleGetElementAtPoint][CmdID: \(effectiveCommandId)] \(errorMsg)")
                return HandlerResponse(data: nil, error: errorMsg)
            }
        } else {
            searchRootElement = Element.systemWide()
        }

        guard let rootElement = searchRootElement else {
            // This case should ideally not be reached if the above logic is sound
            let errorMsg = "Could not determine root element for hit-testing."
            axErrorLog("[AXorcist.handleGetElementAtPoint][CmdID: \(effectiveCommandId)] \(errorMsg)")
            return HandlerResponse(data: nil, error: errorMsg)
        }

        // 2. Perform the hit-test
        var hitElementRef: AXUIElement?
        let error = AXUIElementCopyElementAtPosition(rootElement.underlyingElement, Float(point.x), Float(point.y), &hitElementRef)

        if error != .success {
            let errorMsg = "AXUIElementCopyElementAtPosition failed: \(axErrorToString(error))"
            axErrorLog("[AXorcist.handleGetElementAtPoint][CmdID: \(effectiveCommandId)] \(errorMsg)")
            return HandlerResponse(data: nil, error: errorMsg)
        }

        guard let foundAxElement = hitElementRef else {
            let errorMsg = "No element found at point (\(point.x), \(point.y))"
            axInfoLog("[AXorcist.handleGetElementAtPoint][CmdID: \(effectiveCommandId)] \(errorMsg)")
            // Not necessarily an error, could be empty space. Return success with no data.
            return HandlerResponse(data: nil, error: nil)
        }

        let foundElement = Element(foundAxElement)
        axInfoLog("[AXorcist.handleGetElementAtPoint][CmdID: \(effectiveCommandId)] Found element: \(foundElement.briefDescription(option: .smart))")

        // 3. Fetch attributes if requested (similar to handleQuery)
        let (attributes, attrErrors) = await getElementAttributes(
            element: foundElement,
            attributes: attributesToFetch ?? AXorcist.defaultAttributesToFetch,
            outputFormat: outputFormat ?? .smart,
            valueFormatOption: valueFormatOption ?? .smart
        )

        if !attrErrors.isEmpty {
            axWarningLog("[AXorcist.handleGetElementAtPoint][CmdID: \(effectiveCommandId)] Errors fetching attributes: \(attrErrors.map { $0.message }.joined(separator: "; "))")
        }
        
        let appElementForPath = applicationElement(for: application ?? AXMiscConstants.focusedApplicationKey)

        let elementData = AXElementData(
            path: foundElement.generatePathArray(upTo: appElementForPath),
            attributes: attributes,
            role: attributes[AXAttributeNames.kAXRoleAttribute]?.value as? String,
            computedName: foundElement.computedName()
        )

        return HandlerResponse(data: AnyCodable(elementData), error: nil)
    }
}

// Need to ensure ValueFormatOption is defined, if not already.
// For now, assuming it exists, e.g., in ModelEnums.swift or similar.
// public enum ValueFormatOption: String, Codable {
//    case smart
//    case raw
//    case stringified
// } 