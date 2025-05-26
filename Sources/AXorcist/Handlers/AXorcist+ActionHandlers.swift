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
            let errorMsg = "Attribute '\(attributeName)' is not settable on element \(targetElement.briefDescription(option: .smart))."
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
        } else if let objectArray = valueToSet as? [AnyObject] { // If valueToSet is directly [AnyObject]
            cfValue = objectArray as CFArray // Then bridge to CFArray
        } else if valueToSet is [Any] { // Check if it's [Any] but not caught by [AnyObject] (e.g. array of value types)
            // This case is problematic for CFArray which expects objects.
            let errorMsg = "Cannot convert array containing non-object types to CFArray for attribute '\(attributeName)'."
            axErrorLog(errorMsg)
            return (errorMsg, .illegalArgument)
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
        actionValue: AnyCodable? = nil,
        maxDepth: Int? = nil
    ) async -> HandlerResponse {
        let logMessage2 = "handlePerformAction: App=\(application ?? AXMiscConstants.focusedApplicationKey), Locator=\(locator), Action=\(actionName), Value=\(String(describing: actionValue))"
        axInfoLog(logMessage2)

        let searchMaxDepth = maxDepth ?? AXMiscConstants.defaultMaxDepthSearch

        let findResult = await findTargetElement(
            for: application,
            locator: locator,
            maxDepthForSearch: searchMaxDepth
        )

        if let targetElement = findResult.element {
            axDebugLog("handlePerformAction: Element found: \(targetElement.briefDescription(option: .smart))")
            // Proceed with targetElement
            let axStatus: AXError
            var actionErrorString: String?

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
                axDebugLog("Action '\(actionName)' performed successfully on \(targetElement.briefDescription(option: .smart)).")
                return HandlerResponse(data: AnyCodable(PerformResponse(commandId: "", success: true)))
            } else {
                let finalErrorMessage = actionErrorString ?? "Action '\(actionName)' failed on \(targetElement.briefDescription(option: .smart)) with status: \(axErrorToString(axStatus))"
                axErrorLog(finalErrorMessage)
                return HandlerResponse(error: finalErrorMessage)
            }
        } else if let errorMsg = findResult.error {
            let errorMessage = "handlePerformAction: Error finding element: \(errorMsg)"
            axErrorLog(errorMessage)
            return HandlerResponse(error: errorMessage)
        } else {
            // Should not happen if findTargetElement always returns either element or error
            let errorMessage = "handlePerformAction: Unknown error finding element."
            axErrorLog(errorMessage)
            return HandlerResponse(error: errorMessage)
        }
    }

    @MainActor
    public func handleExtractText(
        for application: String?,
        locator: Locator,
        maxDepth: Int? = nil
    ) -> HandlerResponse {
        let logMessage3 = "handleExtractText: App=\(application ?? AXMiscConstants.focusedApplicationKey), Locator=\(locator)"
        axInfoLog(logMessage3)

        let searchMaxDepth = maxDepth ?? AXMiscConstants.defaultMaxDepthSearch

        let findResult = findTargetElement(
            for: application,
            locator: locator,
            maxDepthForSearch: searchMaxDepth
        )

        let appElementInstance = applicationElement(for: application ?? AXMiscConstants.focusedApplicationKey)

        if let targetElement = findResult.element {
            axDebugLog("handleExtractText: Element found: \(targetElement.briefDescription(option: .smart))")
            // Proceed with targetElement
            guard appElementInstance != nil else {
                let appNameToLog = application ?? AXMiscConstants.focusedApplicationKey
                let errorMsg = "Could not get application element for path generation in handleExtractText for appKey: \(appNameToLog)."
                axErrorLog(errorMsg)
                return HandlerResponse(data: AnyCodable(TextExtractionResponse(textContent: nil)), error: errorMsg)
            }

            var allTextValues: [String] = []
            if let title: String = targetElement.attribute(.title) { allTextValues.append(title) }
            if let desc: String = targetElement.attribute(.description) { allTextValues.append(desc) }
            if let valStr: String = targetElement.attribute(Attribute<String>(AXAttributeNames.kAXValueAttribute)) { allTextValues.append(valStr) }
            if let selectedText: String = targetElement.attribute(.selectedText) { allTextValues.append(selectedText) }
            if let placeholder: String = targetElement.attribute(.placeholderValue) { allTextValues.append(placeholder) }

            let combinedText = allTextValues.joined(separator: " ").lowercased()

            if combinedText.isEmpty {
                axDebugLog("No textual content found for element: \(targetElement.briefDescription(option: .smart))")
                return HandlerResponse(data: AnyCodable(TextExtractionResponse(textContent: nil)), error: "No textual content found")
            } else {
                axDebugLog("Extracted text: '\(combinedText)' from element: \(targetElement.briefDescription(option: .smart))")
                return HandlerResponse(data: AnyCodable(TextExtractionResponse(textContent: combinedText.isEmpty ? nil : combinedText)))
            }
        } else if let errorMsg = findResult.error {
            let errorMessage = "handleExtractText: Error finding element: \(errorMsg)"
            axErrorLog(errorMessage)
            return HandlerResponse(error: errorMessage)
        } else {
            let errorMessage = "handleExtractText: Unknown error finding element."
            axErrorLog(errorMessage)
            return HandlerResponse(error: errorMessage)
        }
    }

    // MARK: - Set Focused Value Handler

    @MainActor
    public func handleSetFocusedValue(
        for applicationName: String?,
        locator: Locator?, // Optional: to verify the focused element if provided
        actionName: String, // Typically kAXValueAttribute or similar
        actionValue: AnyCodable? // The value to set
    ) -> HandlerResponse {
        let appID = applicationName ?? AXMiscConstants.focusedApplicationKey
        axInfoLog("[handleSetFocusedValue] App=\(appID), Locator=\(locator?.description ?? "nil"), Action=\(actionName), Value=\(String(describing: actionValue))")

        guard let focusedElement = getFocusedElement(for: appID) else {
            let errorMsg = "[handleSetFocusedValue] Could not get focused element for app: \(appID)"
            axErrorLog(errorMsg)
            return HandlerResponse(error: errorMsg)
        }
        axDebugLog("[handleSetFocusedValue] Found focused element: \(focusedElement.briefDescription())")

        // Optional: Validate against locator if provided
        if let aLocator = locator {
            // evaluateElementAgainstCriteria is synchronous
            let matchStatus = evaluateElementAgainstCriteria(
                element: focusedElement, 
                locator: aLocator, 
                actionToVerify: nil, // Not verifying an action here, just the element itself
                depth: 0 // Depth is not relevant for a single element check
            )
            if matchStatus != .fullMatch {
                let errorMsg = "[handleSetFocusedValue] Focused element \(focusedElement.briefDescription()) does not match provided locator: \(aLocator.description)"
                axWarningLog(errorMsg)
                // Depending on strictness, one might return an error here or proceed.
                // For now, proceeding but logging a warning.
            }
        }

        guard let valueToSet = actionValue else {
            let errorMsg = "[handleSetFocusedValue] Value to set is nil for attribute/action '\(actionName)'."
            axErrorLog(errorMsg)
            return HandlerResponse(error: errorMsg)
        }
        
        // Use the existing helper for setting attribute values
        let setResult = executeSetAttributeValueAction(attributeName: actionName, value: valueToSet, on: focusedElement)

        if setResult.axStatus == .success {
            axDebugLog("[handleSetFocusedValue] Action/Attribute '\(actionName)' set successfully on focused element \(focusedElement.briefDescription()).")
            return HandlerResponse(data: AnyCodable(PerformResponse(commandId: "", success: true, message: "Value set successfully.")))
        } else {
            let finalErrorMessage = setResult.errorMessage ?? "[handleSetFocusedValue] Failed to set '\(actionName)' on focused element \(focusedElement.briefDescription()) with status: \(axErrorToString(setResult.axStatus))"
            axErrorLog(finalErrorMessage)
            return HandlerResponse(error: finalErrorMessage)
        }
    }
}

// Define PerformResponse and TextExtractionResponse if they are not already globally available
// For now, assuming they are defined elsewhere and are Codable.
// struct PerformResponse: Codable { let commandId: String; let success: Bool }
// struct TextExtractionResponse: Codable { let textContent: String? }

// Removed stub PathHintComponent struct - the canonical one is in SearchCriteriaUtils.swift
// struct PathHintComponent {
//    let originalSegment: String?
// }
