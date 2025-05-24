// AXorcist+ActionHandlers.swift - Action and data operation handlers

import AppKit
import ApplicationServices
import Darwin
import Foundation
// import Defaults // REMOVED
// import removed - logging utilities now in same module

// MARK: - Action & Data Handlers Extension
extension AXorcist {

    // MARK: - Private Helper Methods

    @MainActor
    private func executeStandardAccessibilityAction(
        _ axActionName: CFString,
        on targetElement: Element,
        actionNameForLog: String
    ) -> AXError {
        let axStatus = AXUIElementPerformAction(targetElement.underlyingElement, axActionName)
        if axStatus != .success {
            let errorMessage = "[AXorcist.handlePerformAction] Failed to perform " +
                "\(actionNameForLog) action: \(axErrorToString(axStatus))"
            axErrorLog(errorMessage) // Use global logger
        }
        return axStatus
    }

    @MainActor
    private func executeSetAttributeValueAction(
        attributeName: String,
        value: AnyCodable?,
        on targetElement: Element
    ) -> (errorMessage: String?, axStatus: AXError) {
        guard let valueToSet = value?.value else {
            let errorMsg = "Value for set attribute '\(attributeName)' is nil."
            axErrorLog(errorMsg)
            return (errorMsg, .cannotComplete)
        }

        guard targetElement.isAttributeSettable(named: attributeName) else {
            let errorMsg = "Attribute '\(attributeName)' is not settable on element \(targetElement.briefDescription())."
            axErrorLog(errorMsg)
            return (errorMsg, .attributeUnsupported)
        }

        // Convert the value to CFTypeRef if possible, handle different types
        var cfValue: CFTypeRef?

        if let stringValue = valueToSet as? String {
            cfValue = stringValue as CFString
        } else if let boolValue = valueToSet as? Bool {
            cfValue = (boolValue ? kCFBooleanTrue : kCFBooleanFalse) as CFBoolean
        } else if let numberValue = valueToSet as? NSNumber { // Handles Int, Double, etc.
            cfValue = numberValue
        } else if let arrayValue = valueToSet as? [Any] {
            // Attempt to convert to CFArray of CFTypeRefs
            // Filter for AnyObject before casting to CFTypeRef to satisfy warning, then cast to CFArray.
            let objectArray = arrayValue.filter { $0 is AnyObject } // Get only class instances
            if objectArray.count == arrayValue.count { // Ensure all items were objects
                cfValue = objectArray as CFArray // Direct cast of [AnyObject] to CFArray
            } else {
                let errorMsg = "Could not convert all elements of array to CFTypeRef (some were not objects) for attribute '\(attributeName)'."
                axErrorLog(errorMsg)
                return (errorMsg, .illegalArgument)
            }
        } else {
            // For other types, attempt direct casting if it's already a CFTypeRef-compatible type
            // This part might need more robust type checking and conversion
            // CFGetTypeID(valueToSet as CFTypeRef) != 0 might be a check, but Swift types might not bridge directly
            // For simplicity, we'll assume if it's not a common type, it might be problematic.
            let errorMsg = "Unsupported value type '\(type(of: valueToSet))' for attribute '\(attributeName)'."
            axErrorLog(errorMsg)
            return (errorMsg, .illegalArgument)
        }

        guard let finalCFValue = cfValue else {
            let errorMsg = "Failed to convert value for attribute '\(attributeName)' to a compatible CFType."
            axErrorLog(errorMsg)
            return (errorMsg, .cannotComplete)
        }

        let axStatus = AXUIElementSetAttributeValue(targetElement.underlyingElement, attributeName as CFString, finalCFValue)
        if axStatus != .success {
            let errorMsg = "Failed to set attribute '\(attributeName)': \(axErrorToString(axStatus))"
            axErrorLog(errorMsg)
            return (errorMsg, axStatus)
        }
        return (nil, .success)
    }

    // Temporary placeholder until actual definition is found or created
    public typealias ActionValueCodable = AnyCodable

    // Temporary simple struct for ActionResponse
    struct ActionResponse: Codable {
        var success: Bool
        var message: String?
    }

    @MainActor
    public func handlePerformAction(
        for application: String?,
        locator: Locator,
        actionName: String,
        actionValue: ActionValueCodable? = nil,
        pathHint: [PathHintComponent]? = nil,
        maxDepth: Int? = nil
    ) async -> HandlerResponse {
        let logMessage2 = "handlePerformAction: App=\(application ?? "focused"), Locator=\(locator), Action=\(actionName), Value=\(String(describing: actionValue))"
        axInfoLog(logMessage2)

        // Determine search depth
        let searchMaxDepth = maxDepth ?? AXMiscConstants.defaultMaxDepthSearch

        // Call the global findTargetElement which returns Result<Element, HandlerErrorInfo>
        let findResult = await findTargetElement(
            for: application,
            locator: locator,
            pathHint: pathHint?.compactMap { $0.originalSegment }, // Use .originalSegment
            maxDepthForSearch: searchMaxDepth
        )

        let targetElement: Element
        // appElement is not directly returned by the new findTargetElement, handle if necessary
        // For now, we primarily need the targetElement or error.

        switch findResult {
        case .success(let foundEl):
            targetElement = foundEl
        case .failure(let errorInfo):
            let errorMessage = "handlePerformAction: Error finding element: \(errorInfo.message)"
            axErrorLog(errorMessage)
            return HandlerResponse(error: "Error finding element: \(errorInfo.message)")
        }

        let axStatus: AXError
        var actionErrorString: String? // To capture specific error from set attribute

        let standardActions = [
            AXActionNames.kAXIncrementAction,
            AXActionNames.kAXDecrementAction,
            AXActionNames.kAXConfirmAction,
            AXActionNames.kAXCancelAction,
            AXActionNames.kAXShowMenuAction,
            AXActionNames.kAXPickAction,
            AXActionNames.kAXPressAction,
            AXActionNames.kAXRaiseAction
        ]

        if standardActions.contains(actionName) {
            axStatus = executeStandardAccessibilityAction(actionName as CFString, on: targetElement, actionNameForLog: actionName)
        } else {
            let setResult = executeSetAttributeValueAction(attributeName: actionName, value: actionValue, on: targetElement)
            axStatus = setResult.axStatus
            actionErrorString = setResult.errorMessage
        }

        if axStatus == .success {
            axDebugLog("Action '\(actionName)' performed successfully on \(targetElement.briefDescription()).")
            // Assuming PerformResponse is a valid Codable struct for the data part
            return HandlerResponse(data: AnyCodable(PerformResponse(commandId: "", success: true)))
        } else {
            let finalErrorMessage = actionErrorString ?? "Action '\(actionName)' failed on \(targetElement.briefDescription()) with status: \(axErrorToString(axStatus))"
            axErrorLog(finalErrorMessage)
            return HandlerResponse(error: finalErrorMessage)
        }
    }

    @MainActor
    public func handleExtractText(
        for application: String?,
        locator: Locator,
        pathHint: [PathHintComponent]? = nil,
        maxDepth: Int? = nil
    ) async -> HandlerResponse {
        let logMessage3 = "handleExtractText: App=\(application ?? "focused"), Locator=\(locator)"
        axInfoLog(logMessage3)

        // Determine search depth
        let searchMaxDepth = maxDepth ?? AXMiscConstants.defaultMaxDepthSearch

        // Call the global findTargetElement
        let findResult = await findTargetElement(
            for: application,
            locator: locator,
            pathHint: pathHint?.compactMap { $0.originalSegment }, // Use .originalSegment
            maxDepthForSearch: searchMaxDepth
        )

        let targetElement: Element
        // We might need appElement for path generation later, let's try to get it
        let appElementInstance = applicationElement(for: application ?? focusedAppKeyValue)


        switch findResult {
        case .success(let foundEl):
            targetElement = foundEl
        case .failure(let errorInfo):
            let errorMessage = "handleExtractText: Error finding element: \(errorInfo.message)"
            axErrorLog(errorMessage)
            return HandlerResponse(error: "Error finding element: \(errorInfo.message)")
        }

        guard appElementInstance != nil else {
            let appNameToLog = application ?? "focused"
            let errorMsg = "Could not get application element for path generation in handleExtractText for appKey: \(appNameToLog)."
            axErrorLog(errorMsg)
            // Return nil for textContent as part of TextExtractionResponse, not in HandlerResponse.error
            return HandlerResponse(data: AnyCodable(TextExtractionResponse(textContent: nil)), error: errorMsg)
        }

        // Text extraction logic
        var allTextValues: [String] = []

        if let title: String = targetElement.attribute(.title) { allTextValues.append(title) }
        if let desc: String = targetElement.attribute(.description) { allTextValues.append(desc) }
        if let valAny = targetElement.attribute(.value),
           let valStr = valAny as? String {
             allTextValues.append(valStr)
        }
        if let selectedText: String = targetElement.attribute(.selectedText) { allTextValues.append(selectedText) }
        if let placeholder: String = targetElement.attribute(Attribute<String>(AXAttributeNames.kAXPlaceholderValueAttribute)) { allTextValues.append(placeholder) }


        // Simple deduplication and joining, can be made more sophisticated
        let uniqueTextValues = Array(Set(allTextValues.filter { !$0.isEmpty }))
        let combinedText = uniqueTextValues.joined(separator: "\n")

        if combinedText.isEmpty {
            axDebugLog("No textual content found for element: \(targetElement.briefDescription())")
            // Return nil for textContent as part of TextExtractionResponse
            return HandlerResponse(data: AnyCodable(TextExtractionResponse(textContent: nil)), error: "No textual content found")
        } else {
            axDebugLog("Extracted text: '\(combinedText)' from element: \(targetElement.briefDescription())")
            // Return extracted text
            return HandlerResponse(data: AnyCodable(TextExtractionResponse(textContent: combinedText)))
        }
    }
}

// Define PerformResponse and TextExtractionResponse if they are not already globally available
// For now, assuming they are defined elsewhere and are Codable.
// struct PerformResponse: Codable { let commandId: String; let success: Bool }
// struct TextExtractionResponse: Codable { let textContent: String? }

// PathHintComponent would need to be defined or imported if it's used here.
// Assuming it has an 'originalSegment: String?' property for conversion.
// If PathHintComponent is not defined, the pathHint parameter type and conversion should be adjusted.
// For now, assuming PathHintComponent exists and has `originalSegment`.
