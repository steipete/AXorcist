import ApplicationServices
import Foundation

extension Element {
    /// Sets the native `AXValue` attribute and preserves the exact Accessibility framework error.
    @MainActor
    @discardableResult
    public func setValue(_ value: String) throws -> Element {
        try self.setAttributeValue(value, forAttribute: AXAttributeNames.kAXValueAttribute)
    }

    /// Sets an accessibility attribute and preserves the exact Accessibility framework error.
    @MainActor
    @discardableResult
    public func setAttributeValue(_ value: Any, forAttribute attributeName: String) throws -> Element {
        try self.setAttributeValue(value, forAttribute: attributeName, using: AXUIElementSetAttributeValue)
    }

    /// Compatibility wrapper for callers that still use the historical Boolean setter.
    @MainActor
    public func setValue(_ value: Any, forAttribute attributeName: String) -> Bool {
        do {
            try self.setAttributeValue(value, forAttribute: attributeName)
            return true
        } catch {
            axErrorLog("Failed to set attribute '\(attributeName)': \(error.localizedDescription)")
            return false
        }
    }

    @MainActor
    @discardableResult
    func setAttributeValue(
        _ value: Any,
        forAttribute attributeName: String,
        using setter: (AXUIElement, CFString, CFTypeRef) -> AXError) throws -> Element
    {
        guard let cfValue = Self.bridgeAttributeValue(value) else {
            throw AccessibilitySystemError(.illegalArgument)
        }

        let description = GlobalAXLogger.shared.isLoggingEnabled
            ? self.briefDescription(option: .smart)
            : nil
        if let description {
            axDebugLog("Setting attribute '\(attributeName)' on element: \(description)")
        }

        try setter(self.underlyingElement, attributeName as CFString, cfValue).throwIfError()

        if let description {
            axInfoLog("Successfully set attribute '\(attributeName)' on element: \(description)")
        }
        return self
    }

    private static func bridgeAttributeValue(_ value: Any) -> CFTypeRef? {
        if let string = value as? String {
            return string as CFString
        }
        if let bool = value as? Bool {
            return CFConstants.cfBoolean(from: bool)
        }
        if let number = value as? NSNumber {
            return number
        }
        if let element = value as? Element {
            return element.underlyingElement
        }
        if let object = value as? NSObject {
            return object
        }
        return nil
    }
}
