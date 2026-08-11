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
        guard let valueToSet else {
            let message = "AXUtilities: AXValue requires a non-nil value."
            axErrorLog(message)
            return (.illegalArgument, message)
        }

        do {
            try element.setAttributeValue(valueToSet, forAttribute: AXAttributeNames.kAXValueAttribute)
            return (.success, nil)
        } catch let error as AccessibilitySystemError {
            let message = "AXUtilities: Failed to set AXValue: \(error.localizedDescription) " +
                "(AXError \(error.axError.rawValue))."
            axErrorLog(message)
            return (error.axError, message)
        } catch {
            let message = "AXUtilities: Failed to set AXValue: \(error.localizedDescription)"
            axErrorLog(message)
            return (.failure, message)
        }
    }
}
