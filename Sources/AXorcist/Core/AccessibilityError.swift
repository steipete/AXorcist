// AccessibilityError.swift - Defines custom error types for the accessibility tool.

import ApplicationServices // Import to make AXError visible
import Foundation

// Main error enum for the accessibility tool, incorporating parsing and operational errors.
public enum AccessibilityError: Error, CustomStringConvertible {
    // Authorization & Setup Errors
    case apiDisabled // Accessibility API is disabled.
    case notAuthorized(String?) // Process is not authorized. Optional AXError for more detail.

    // Command & Input Errors
    case invalidCommand(String?) // Command is invalid or not recognized. Optional message.
    case missingArgument(String) // A required argument is missing.
    case invalidArgument(String) // An argument has an invalid value or format.

    // Element & Search Errors
    case appNotFound(String) // Application with specified bundle ID or name not found or not running.
    case elementNotFound(String?) // Element matching criteria or path not found. Optional message.
    case invalidElement // The AXUIElementRef is invalid or stale.

    // Observer Errors (New cases)
    case observerSetupFailed(details: String) // Failed to setup AXObserver
    case tokenNotFound(tokenId: UUID) // Subscription token not found

    // Attribute Errors
    case attributeUnsupported(attribute: String, elementDescription: String?) // Attribute is not supported by the element.
    case attributeNotReadable(attribute: String, elementDescription: String?) // Attribute value cannot be read.
    case attributeNotSettable(attribute: String, elementDescription: String?) // Attribute is not settable.
    case typeMismatch(expected: String, actual: String, attribute: String?) // Value type does not match attribute's expected type.
    case valueParsingFailed(details: String, attribute: String?) // Failed to parse string into the required type for an attribute.
    case valueNotAXValue(attribute: String, elementDescription: String?) // Value is not an AXValue type when one is expected.

    // Action Errors
    case actionUnsupported(action: String, elementDescription: String?) // Action is not supported by the element.
    case actionFailed(action: String, elementDescription: String?, underlyingError: AXError?) // Action failed. Optional message and AXError.

    // Generic & System Errors
    case unknownAXError(AXError) // An unknown or unexpected AXError occurred.
    case jsonEncodingFailed(Error?) // Failed to encode response to JSON.
    case jsonDecodingFailed(Error?) // Failed to decode request from JSON.
    case genericError(String) // A generic error with a custom message.

    public var description: String {
        switch self {
        // Authorization & Setup
        case .apiDisabled: return "Accessibility API is disabled. Please enable it in System Settings."
        case .notAuthorized(let axErr):
            let base = "Accessibility permissions are not granted for this process."
            if let error = axErr { return "\(base) AXError: \(error)" }
            return base

        // Command & Input
        case .invalidCommand(let msg):
            let base = "Invalid command specified."
            if let message = msg { return "\(base) \(message)" }
            return base
        case .missingArgument(let name): return "Missing required argument: \(name)."
        case .invalidArgument(let details): return "Invalid argument: \(details)."

        // Element & Search
        case .appNotFound(let app): return "Application '\(app)' not found or not running."
        case .elementNotFound(let msg):
            let base = "No element matches the locator criteria or path."
            if let message = msg { return "\(base) \(message)" }
            return base
        case .invalidElement: return "The specified UI element is invalid (possibly stale)."

        // Observer Errors
        case .observerSetupFailed(let details): return "AXObserver setup failed: \(details)."
        case .tokenNotFound(let tokenId): return "Subscription token ID \(tokenId) not found."

        // Attribute Errors
        case .attributeUnsupported(let attr, let elDesc):
            let base = "Attribute '\(attr)' is not supported"
            if let desc = elDesc { return "\(base) on element '\(desc)'." }
            return "\(base)."
        case .attributeNotReadable(let attr, let elDesc):
            let base = "Attribute '\(attr)' is not readable"
            if let desc = elDesc { return "\(base) on element '\(desc)'." }
            return "\(base)."
        case .attributeNotSettable(let attr, let elDesc):
            let base = "Attribute '\(attr)' is not settable"
            if let desc = elDesc { return "\(base) on element '\(desc)'." }
            return "\(base)."
        case let .typeMismatch(expected, actual, attribute):
            var msg = "Type mismatch: Expected '\(expected)', got '\(actual)'"
            if let attr = attribute { msg += " for attribute '\(attr)'" }
            return msg + "."
        case .valueParsingFailed(let details, let attribute):
            var msg = "Value parsing failed: \(details)"
            if let attr = attribute { msg += " for attribute '\(attr)'" }
            return msg + "."
        case .valueNotAXValue(let attr, let elDesc):
            let base = "Value for attribute '\(attr)' is not an AXValue type as expected"
            if let desc = elDesc { return "\(base) on element '\(desc)'." }
            return "\(base)."

        // Action Errors
        case .actionUnsupported(let action, let elDesc):
            let base = "Action '\(action)' is not supported"
            if let desc = elDesc { return "\(base) on element '\(desc)'." }
            return "\(base)."
        case let .actionFailed(action, elDesc, axErr):
            var parts: [String] = ["Action '\(action)' failed."]
            if let desc = elDesc { parts.append("On element: '\(desc)'.") }
            if let error = axErr { parts.append("AXError: \(axErrorToString(error)).") }
            return parts.joined(separator: " ")

        // Generic & System
        case .unknownAXError(let error): return "An unexpected Accessibility Framework error occurred: \(error)."
        case .jsonEncodingFailed(let err):
            let base = "Failed to encode the response to JSON."
            if let error = err { return "\(base) Error: \(error.localizedDescription)" }
            return base
        case .jsonDecodingFailed(let err):
            let base = "Failed to decode the JSON command input."
            if let error = err { return "\(base) Error: \(error.localizedDescription)" }
            return base
        case .genericError(let msg): return msg
        }
    }

    // Helper to get a more specific exit code if needed, or a general one.
    // This is just an example; actual exit codes might vary.
    public var exitCode: Int32 {
        switch self {
        case .apiDisabled, .notAuthorized: return 10
        case .invalidCommand, .missingArgument, .invalidArgument: return 20
        case .appNotFound, .elementNotFound, .invalidElement: return 30
        case .attributeUnsupported, .attributeNotReadable, .attributeNotSettable, .typeMismatch, .valueParsingFailed,
             .valueNotAXValue: return 40
        case .actionUnsupported, .actionFailed: return 50
        case .jsonEncodingFailed, .jsonDecodingFailed: return 60
        case .unknownAXError, .genericError: return 1
        case .observerSetupFailed, .tokenNotFound: return 70
        }
    }
}
