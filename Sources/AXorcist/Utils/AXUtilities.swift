// AXUtilities.swift - Utility functions for performing AX actions and setting values.

import ApplicationServices
import Foundation

// GlobalAXLogger is assumed available

@MainActor
public enum AXUtilities {
    public static func performAXAction(_ actionName: String, on element: Element) -> AXError {
        do {
            try element.performAction(actionName)
            return .success
        } catch {
            if let systemError = error as? AccessibilitySystemError {
                axErrorLog(
                    "AXUtilities: Action '\(actionName)' failed: \(systemError.localizedDescription) " +
                        "(AXError \(systemError.axError.rawValue))")
            } else {
                axErrorLog("AXUtilities: Action '\(actionName)' failed with an unexpected error: \(error)")
            }
            return Self.axError(forActionError: error)
        }
    }

    static func axError(forActionError error: any Error) -> AXError {
        (error as? AccessibilitySystemError)?.axError ?? .failure
    }

    public static func performSetValueAction(
        forElement element: Element,
        valueToSet: Any?) -> (error: AXError, errorMessage: String?)
    {
        let description = element.briefDescription()
        axDebugLog(
            "AXUtilities: Attempting to set value for element: \(description) " +
                "with value: \(String(describing: valueToSet))")

        let attributeName = AXAttributeNames.kAXValueAttribute

        var cfValue: CFTypeRef?
        if let nsValue = valueToSet as? NSObject {
            cfValue = nsValue
        } else if let strValue = valueToSet as? String {
            cfValue = strValue as CFString
        } else if valueToSet == nil {
            axDebugLog("AXUtilities: valueToSet is nil. Attempting to set attribute to nil/empty.")
        } else {
            let errorMsg =
                "AXUtilities: Value type for attribute '\(attributeName)' is not directly " +
                "convertible to CFTypeRef: \(String(describing: valueToSet)). " +
                "Type: \(type(of: valueToSet))"
            axErrorLog(errorMsg)
            return (.apiDisabled, errorMsg)
        }

        let error = AXUIElementSetAttributeValue(
            element.underlyingElement,
            attributeName as CFString,
            cfValue ?? CFConstants.cfBooleanFalse!)

        if error == .success {
            axDebugLog(
                "AXUtilities: Successfully set attribute '\(attributeName)' on \(description)")
            return (.success, nil)
        } else {
            let errorMsg =
                "AXUtilities: Failed to set attribute '\(attributeName)' on \(description). " +
                "Error: \(error)"
            axErrorLog(errorMsg)
            return (error, errorMsg)
        }
    }
}
