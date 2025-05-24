import ApplicationServices
import Foundation
// GlobalAXLogger is assumed to be available via imports in the main AXorcist module or AXorcistLib

extension AXorcist {

    // MARK: - Attribute Access Handlers

    /// Checks if a specific attribute of an accessibility element is settable.
    ///
    /// - Parameters:
    ///   - attributeName: The name of the attribute to check (e.g., kAXValueAttribute).
    ///   - element: The `AXUIElement` to check.
    /// - Returns: `true` if the attribute is settable, `false` otherwise. Returns `false` if the element is nil or on error.
    @MainActor
    public func isAttributeSettable(
        _ attributeName: String,
        forElement element: AXUIElement?
    ) -> Bool {
        guard let element = element else {
            // Log will only occur if GlobalAXLogger.isCurrentlyCollecting is true
            axDebugLog("isAttributeSettable: Element is nil for attribute '\(attributeName)'.")
            return false
        }

        var isSettable: DarwinBoolean = false
        let error = AXUIElementIsAttributeSettable(element, attributeName as CFString, &isSettable)

        if error != .success {
            axDebugLog("isAttributeSettable: Error checking if attribute '\(attributeName)' is settable. Error code: \(error.rawValue)")
            return false
        }

        axDebugLog("isAttributeSettable: Attribute '\(attributeName)' is \(isSettable.boolValue ? "settable" : "not settable").")
        return isSettable.boolValue
    }

    /// Sets the value of a specific attribute for an accessibility element.
    ///
    /// - Parameters:
    ///   - attributeName: The name of the attribute to set (e.g., kAXValueAttribute).
    ///   - value: The new value for the attribute. Currently supports String values primarily.
    ///            Other types might require specific `CFTypeRef` conversion.
    ///   - element: The `AXUIElement` for which to set the attribute.
    /// - Returns: `true` if the attribute was set successfully, `false` otherwise.
    @MainActor
    public func setAttributeValue(
        _ attributeName: String,
        to value: Any,
        forElement element: AXUIElement?
    ) -> Bool {
        guard let element = element else {
            axDebugLog("setAttributeValue: Element is nil for attribute '\(attributeName)'.")
            return false
        }

        let cfValue: CFTypeRef?
        if let stringValue = value as? String {
            cfValue = stringValue as CFString
        } else if let numberValue = value as? NSNumber {
            cfValue = numberValue
        } else if CFGetTypeID(value as CFTypeRef) != 0 {
            cfValue = value as CFTypeRef
        } else {
            axWarningLog("setAttributeValue: Unsupported value type '\(type(of: value))' for attribute '\(attributeName)'.")
            return false
        }

        guard let finalCFValue = cfValue else {
            axWarningLog("setAttributeValue: Failed to convert value '\(value)' to CFTypeRef for attribute '\(attributeName)'.")
            return false
        }

        let error = AXUIElementSetAttributeValue(element, attributeName as CFString, finalCFValue)

        if error == .success {
            axInfoLog("setAttributeValue: Successfully set attribute '\(attributeName)' to '\(String(describing: value).truncated(to: 100))'.") // Truncate potentially long value
            return true
        } else {
            axErrorLog("setAttributeValue: Error setting attribute '\(attributeName)' to '\(String(describing: value).truncated(to: 100))'. Error code: \(error.rawValue)")
            return false
        }
    }
}
