// Element+TypeConversion.swift - Type conversion functionality for Element

import ApplicationServices
import Foundation

extension Element {
    @MainActor
    func convertCFTypeToSwiftType<T>(_ cfValue: CFTypeRef, attribute: Attribute<T>) -> T? {
        // Try specific type conversions first
        if let converted = convertToSpecificType(cfValue, targetType: T.self) as? T {
            return converted
        }

        // Handle Any/AnyObject types
        if T.self == Any.self || T.self == AnyObject.self {
            GlobalAXLogger.shared.log(AXLogEntry(
                level: .debug,
                message: "Attribute \(attribute.rawValue): T is Any/AnyObject. Using ValueUnwrapper."))
            return ValueUnwrapper.unwrap(cfValue) as? T
        }

        // Try direct cast
        if let directCast = cfValue as? T {
            GlobalAXLogger.shared.log(AXLogEntry(
                level: .debug,
                message: "Basic conversion succeeded with direct cast for T = \(String(describing: T.self)), " +
                    "Attribute: \(attribute.rawValue)."))
            return directCast
        }

        // Fall back to ValueUnwrapper
        GlobalAXLogger.shared.log(AXLogEntry(
            level: .debug,
            message: "Attempting ValueUnwrapper for T = \(String(describing: T.self)), " +
                "Attribute: \(attribute.rawValue)."))
        return ValueUnwrapper.unwrap(cfValue) as? T
    }

    private func convertToSpecificType(_ cfValue: CFTypeRef, targetType: Any.Type) -> Any? {
        let cfTypeID = CFGetTypeID(cfValue)

        switch targetType {
        case is String.Type:
            return self.convertToString(cfValue, cfTypeID: cfTypeID)
        case is Bool.Type:
            return self.convertToBool(cfValue, cfTypeID: cfTypeID)
        case is Int.Type:
            return self.convertToInt(cfValue, cfTypeID: cfTypeID)
        case is AXUIElement.Type:
            return self.convertToAXUIElement(cfValue, cfTypeID: cfTypeID)
        default:
            return nil
        }
    }

    private func convertToString(_ cfValue: CFTypeRef, cfTypeID: CFTypeID) -> String? {
        if cfTypeID == CFStringGetTypeID() {
            guard let cfString = cfValue as? CFString else {
                GlobalAXLogger.shared.log(
                    AXLogEntry(level: .warning, message: "Failed to cast CFTypeRef to CFString"))
                return nil
            }
            return cfString as String
        } else if cfTypeID == CFAttributedStringGetTypeID() {
            guard let attrString = cfValue as? NSAttributedString else {
                GlobalAXLogger.shared.log(
                    AXLogEntry(level: .warning, message: "Failed to cast CFTypeRef to NSAttributedString"))
                return nil
            }
            return attrString.string
        }
        return nil
    }

    private func convertToBool(_ cfValue: CFTypeRef, cfTypeID: CFTypeID) -> Bool? {
        if cfTypeID == CFBooleanGetTypeID() {
            guard let cfBool = cfValue as? CFBoolean else {
                GlobalAXLogger.shared.log(
                    AXLogEntry(level: .warning, message: "Failed to cast CFTypeRef to CFBoolean"))
                return nil
            }
            return CFBooleanGetValue(cfBool)
        }
        return nil
    }

    private func convertToInt(_ cfValue: CFTypeRef, cfTypeID: CFTypeID) -> Int? {
        if cfTypeID == CFNumberGetTypeID() {
            guard let cfNumber = cfValue as? CFNumber else {
                GlobalAXLogger.shared.log(
                    AXLogEntry(level: .warning, message: "Failed to cast CFTypeRef to CFNumber"))
                return nil
            }
            var intValue = 0
            if CFNumberGetValue(cfNumber, .sInt64Type, &intValue) {
                return intValue
            }
        }
        return nil
    }

    private func convertToAXUIElement(_ cfValue: CFTypeRef, cfTypeID: CFTypeID) -> AXUIElement? {
        if cfTypeID == AXUIElementGetTypeID() {
            guard let element = cfValue as? AXUIElement else {
                GlobalAXLogger.shared.log(
                    AXLogEntry(level: .warning, message: "Failed to cast CFTypeRef to AXUIElement"))
                return nil
            }
            return element
        }
        return nil
    }
}
