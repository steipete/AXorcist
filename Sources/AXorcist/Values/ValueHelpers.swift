import ApplicationServices
import CoreGraphics // For CGPoint, CGSize etc.
import Foundation

// debug() is assumed to be globally available from Logging.swift
// Constants like kAXPositionAttribute are assumed to be globally available from AccessibilityConstants.swift

// ValueUnwrapper has been moved to its own file: ValueUnwrapper.swift

// MARK: - Attribute Value Accessors

@MainActor
public func copyAttributeValue(element: AXUIElement, attribute: String) -> CFTypeRef? {
    var value: CFTypeRef?
    // This function is low-level, avoid extensive logging here unless specifically for this function.
    // Logging for attribute success/failure is better handled by the caller (axValue).
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
        return nil
    }
    return value
}

@MainActor
public func axValue<T>(
    of element: AXUIElement,
    attr: String,
    isDebugLoggingEnabled: Bool,
    currentDebugLogs: inout [String]
) -> T? {
    func dLog(_ message: String) {
        if isDebugLoggingEnabled {
            currentDebugLogs.append(message)
        }
    }

    let rawCFValue = copyAttributeValue(element: element, attribute: attr)
    let unwrappedValue = ValueUnwrapper.unwrap(
        rawCFValue,
        isDebugLoggingEnabled: isDebugLoggingEnabled,
        currentDebugLogs: &currentDebugLogs
    )

    guard let value = unwrappedValue else {
        return nil
    }

    return castValueToType(value, expectedType: T.self, attr: attr, dLog: dLog)
}

// MARK: - Type Casting Helpers

@MainActor
private func castValueToType<T>(_ value: Any, expectedType: T.Type, attr: String, dLog: (String) -> Void) -> T? {
    // Handle basic types
    if let result = castToBasicType(value, expectedType: expectedType, attr: attr, dLog: dLog) {
        return result
    }

    // Handle array types
    if let result = castToArrayType(value, expectedType: expectedType, attr: attr, dLog: dLog) {
        return result
    }

    // Handle geometry types
    if let result = castToGeometryType(value, expectedType: expectedType, attr: attr, dLog: dLog) {
        return result
    }

    // Handle special types
    if let result = castToSpecialType(value, expectedType: expectedType, attr: attr, dLog: dLog) {
        return result
    }
    // Direct cast fallback
    if let directCast = value as? T {
        return directCast
    }

    dLog(
        "axValue: Fallback cast attempt for attribute '\(attr)' to type \(T.self) FAILED. " +
            "Unwrapped value was \(type(of: value)): \(value)"
    )
    return nil
}

@MainActor
private func castToBasicType<T>(_ value: Any, expectedType: T.Type, attr: String, dLog: (String) -> Void) -> T? {
    switch expectedType {
    case is String.Type:
        return castToString(value, attr: attr, dLog: dLog) as? T
    case is Bool.Type:
        return castToBool(value, attr: attr, dLog: dLog) as? T
    case is Int.Type:
        return castToInt(value, attr: attr, dLog: dLog) as? T
    case is Double.Type:
        return castToDouble(value, attr: attr, dLog: dLog) as? T
    default:
        return nil
    }
}

@MainActor
private func castToString(_ value: Any, attr: String, dLog: (String) -> Void) -> String? {
    if let str = value as? String {
        return str
    } else if let attrStr = value as? NSAttributedString {
        return attrStr.string
    }
    dLog("axValue: Expected String for attribute '\(attr)', but got \(type(of: value)): \(value)")
    return nil
}

@MainActor
private func castToBool(_ value: Any, attr: String, dLog: (String) -> Void) -> Bool? {
    if let boolVal = value as? Bool {
        return boolVal
    } else if let numVal = value as? NSNumber {
        return numVal.boolValue
    }
    dLog("axValue: Expected Bool for attribute '\(attr)', but got \(type(of: value)): \(value)")
    return nil
}

@MainActor
private func castToInt(_ value: Any, attr: String, dLog: (String) -> Void) -> Int? {
    if let intVal = value as? Int {
        return intVal
    } else if let numVal = value as? NSNumber {
        return numVal.intValue
    }
    dLog("axValue: Expected Int for attribute '\(attr)', but got \(type(of: value)): \(value)")
    return nil
}

@MainActor
private func castToDouble(_ value: Any, attr: String, dLog: (String) -> Void) -> Double? {
    if let doubleVal = value as? Double {
        return doubleVal
    } else if let numVal = value as? NSNumber {
        return numVal.doubleValue
    }
    dLog("axValue: Expected Double for attribute '\(attr)', but got \(type(of: value)): \(value)")
    return nil
}

@MainActor
private func castToArrayType<T>(_ value: Any, expectedType: T.Type, attr: String, dLog: (String) -> Void) -> T? {
    switch expectedType {
    case is [AXUIElement].Type:
        return castToAXUIElementArray(value, attr: attr, dLog: dLog) as? T
    case is [Element].Type:
        return castToElementArray(value, attr: attr, dLog: dLog) as? T
    case is [String].Type:
        return castToStringArray(value, attr: attr, dLog: dLog) as? T
    default:
        return nil
    }
}

@MainActor
private func castToAXUIElementArray(_ value: Any, attr: String, dLog: (String) -> Void) -> [AXUIElement]? {
    if let anyArray = value as? [Any?] {
        let result = anyArray.compactMap { item -> AXUIElement? in
            guard let cfItem = item else { return nil }
            if CFGetTypeID(cfItem as CFTypeRef) == AXUIElementGetTypeID() {
                return (cfItem as! AXUIElement)
            }
            return nil
        }
        return result
    }
    dLog("axValue: Expected [AXUIElement] for attribute '\(attr)', but got \(type(of: value)): \(value)")
    return nil
}

@MainActor
private func castToElementArray(_ value: Any, attr: String, dLog: (String) -> Void) -> [Element]? {
    if let anyArray = value as? [Any?] {
        let result = anyArray.compactMap { item -> Element? in
            guard let cfItem = item else { return nil }
            if CFGetTypeID(cfItem as CFTypeRef) == AXUIElementGetTypeID() {
                return Element(cfItem as! AXUIElement)
            }
            return nil
        }
        return result
    }
    dLog("axValue: Expected [Element] for attribute '\(attr)', but got \(type(of: value)): \(value)")
    return nil
}

@MainActor
private func castToStringArray(_ value: Any, attr: String, dLog: (String) -> Void) -> [String]? {
    if let stringArray = value as? [Any?] {
        let result = stringArray.compactMap { $0 as? String }
        if result.count == stringArray.count {
            return result
        }
    }
    dLog("axValue: Expected [String] for attribute '\(attr)', but got \(type(of: value)): \(value)")
    return nil
}

@MainActor
private func castToGeometryType<T>(_ value: Any, expectedType: T.Type, attr: String, dLog: (String) -> Void) -> T? {
    switch expectedType {
    case is CGPoint.Type:
        return castToCGPoint(value, attr: attr, dLog: dLog) as? T
    case is CGSize.Type:
        return castToCGSize(value, attr: attr, dLog: dLog) as? T
    default:
        return nil
    }
}

@MainActor
private func castToCGPoint(_ value: Any, attr: String, dLog: (String) -> Void) -> CGPoint? {
    if let pointVal = value as? CGPoint {
        return pointVal
    }
    dLog("axValue: Expected CGPoint for attribute '\(attr)', but got \(type(of: value)): \(value)")
    return nil
}

@MainActor
private func castToCGSize(_ value: Any, attr: String, dLog: (String) -> Void) -> CGSize? {
    if let sizeVal = value as? CGSize {
        return sizeVal
    }
    dLog("axValue: Expected CGSize for attribute '\(attr)', but got \(type(of: value)): \(value)")
    return nil
}

@MainActor
private func castToSpecialType<T>(_ value: Any, expectedType: T.Type, attr: String, dLog: (String) -> Void) -> T? {
    if expectedType == AXUIElement.self {
        return castToAXUIElement(value, attr: attr, dLog: dLog) as? T
    }
    return nil
}

@MainActor
private func castToAXUIElement(_ value: Any, attr: String, dLog: (String) -> Void) -> AXUIElement? {
    if let cfValue = value as CFTypeRef?, CFGetTypeID(cfValue) == AXUIElementGetTypeID() {
        return (cfValue as! AXUIElement)
    }
    let typeDescription = String(describing: type(of: value))
    let valueDescription = String(describing: value)
    dLog("axValue: Expected AXUIElement for attribute '\(attr)', but got \(typeDescription): \(valueDescription)")
    return nil
}

// MARK: - AXValueType String Helper

public func stringFromAXValueType(_ type: AXValueType) -> String {
    switch type {
    case .cgPoint: return "CGPoint (kAXValueCGPointType)"
    case .cgSize: return "CGSize (kAXValueCGSizeType)"
    case .cgRect: return "CGRect (kAXValueCGRectType)"
    case .cfRange: return "CFRange (kAXValueCFRangeType)"
    case .axError: return "AXError (kAXValueAXErrorType)"
    case .illegal: return "Illegal (kAXValueIllegalType)"
    default:
        // AXValueType is not exhaustive in Swift's AXValueType enum from ApplicationServices.
        // Common missing ones include Boolean (4), Number (5), Array (6), Dictionary (7), String (8), URL (9), etc.
        // We rely on ValueUnwrapper to handle these based on CFGetTypeID.
        // This function is mostly for AXValue encoded types.
        if type.rawValue == 4 { // kAXValueBooleanType is often 4 but not in the public enum
            return "Boolean (rawValue 4, contextually kAXValueBooleanType)"
        }
        return "Unknown AXValueType (rawValue: \(type.rawValue))"
    }
}
