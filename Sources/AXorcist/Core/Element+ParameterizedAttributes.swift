// Element+ParameterizedAttributes.swift - Extension for parameterized attribute functionality

import ApplicationServices // For AXUIElement and other C APIs
import Foundation
// GlobalAXLogger is expected to be available in this module (AXorcistLib)

// MARK: - Parameterized Attributes Extension
extension Element {
    @MainActor
    public func parameterizedAttribute<T>(
        _ attribute: Attribute<T>,
        forParameter parameter: Any
    ) -> T? {
        guard let cfParameter = convertParameterToCFTypeRef(parameter, attribute: attribute) else {
            return nil
        }

        guard let resultCFValue = copyParameterizedAttributeValue(
            attribute: attribute,
            parameter: cfParameter
        ) else {
            return nil
        }

        guard let finalValue = ValueUnwrapper.unwrap(resultCFValue) else {
            axDebugLog("Unwrapping CFValue for parameterized attribute \(attribute.rawValue) resulted in nil.")
            return nil
        }

        return castValueToType(finalValue, attribute: attribute)
    }

    @MainActor
    private func convertParameterToCFTypeRef<T>(_ parameter: Any, attribute: Attribute<T>) -> CFTypeRef? {
        if var range = parameter as? CFRange {
            return AXValueCreate(.cfRange, &range)
        } else if let string = parameter as? String {
            return string as CFString
        } else if let number = parameter as? NSNumber {
            return number
        } else if CFGetTypeID(parameter as CFTypeRef) != 0 {
            return (parameter as CFTypeRef)
        } else {
            axWarningLog("Unsupported parameter type \(type(of: parameter)) for attribute \(attribute.rawValue)")
            return nil
        }
    }

    @MainActor
    private func copyParameterizedAttributeValue<T>(
        attribute: Attribute<T>,
        parameter: CFTypeRef
    ) -> CFTypeRef? {
        var value: CFTypeRef?
        let error = AXUIElementCopyParameterizedAttributeValue(
            underlyingElement,
            attribute.rawValue as CFString,
            parameter,
            &value
        )

        if error != .success {
            axDebugLog("Error \(error.rawValue) getting parameterized attribute \(attribute.rawValue)")
            return nil
        }

        guard let resultCFValue = value else {
            axDebugLog("Parameterized attribute \(attribute.rawValue) resulted in nil CFValue despite success.")
            return nil
        }

        return resultCFValue
    }

    @MainActor
    private func castValueToType<T>(_ finalValue: Any, attribute: Attribute<T>) -> T? {
        if T.self == String.self {
            if let str = finalValue as? String { return str as? T }
            if let attrStr = finalValue as? NSAttributedString { return attrStr.string as? T }
            axDebugLog(
                "Failed to cast unwrapped value for String attribute \(attribute.rawValue). " +
                "Value: \(finalValue)"
            )
            return nil
        }

        if let castedValue = finalValue as? T {
            return castedValue
        }

        axWarningLog(
            "Fallback cast attempt for parameterized attribute '\(attribute.rawValue)' " +
            "to type \(T.self) FAILED. Unwrapped value was \(type(of: finalValue)): \(finalValue)"
        )
        return nil
    }
}
