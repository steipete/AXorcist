import ApplicationServices
import CoreGraphics // For CGPoint, CGSize etc.
import Foundation

// GlobalAXLogger is expected to be available in this module (AXorcistLib)

// MARK: - ValueUnwrapper Utility

enum ValueUnwrapper {
    // MARK: Internal

    @MainActor
    static func unwrap(_ cfValue: CFTypeRef?) -> Any? {
        guard let value = cfValue else { return nil }
        let typeID = CFGetTypeID(value)

        return self.unwrapByTypeID(
            value,
            typeID: typeID)
    }

    // MARK: Private

    @MainActor
    private static func unwrapByTypeID(
        _ value: CFTypeRef,
        typeID: CFTypeID) -> Any?
    {
        switch typeID {
        case ApplicationServices.AXUIElementGetTypeID():
            guard let element = value as? AXUIElement else {
                axWarningLog("Failed to cast CFTypeRef to AXUIElement.")
                return nil
            }
            return element
        case ApplicationServices.AXValueGetTypeID():
            return self.unwrapAXValue(value)
        case CFStringGetTypeID():
            guard let cfString = value as? CFString else {
                axWarningLog("Failed to cast CFTypeRef to CFString.")
                return nil
            }
            return cfString as String
        case CFAttributedStringGetTypeID():
            guard let attributedString = value as? NSAttributedString else {
                axWarningLog("Failed to cast CFTypeRef to NSAttributedString.")
                return nil
            }
            return attributedString.string
        case CFBooleanGetTypeID():
            guard let cfBool = value as? CFBoolean else {
                axWarningLog("Failed to cast CFTypeRef to CFBoolean.")
                return nil
            }
            return CFBooleanGetValue(cfBool)
        case CFNumberGetTypeID():
            guard let number = value as? NSNumber else {
                axWarningLog("Failed to cast CFTypeRef to NSNumber.")
                return nil
            }
            return number
        case CFArrayGetTypeID():
            return self.unwrapCFArray(value)
        case CFDictionaryGetTypeID():
            return self.unwrapCFDictionary(value)
        default:
            let typeDescription = CFCopyTypeIDDescription(typeID) as String? ?? "Unknown"
            let message = "Unhandled CFTypeID: \(typeID) - \(typeDescription). Returning raw value."
            axDebugLog(message)
            return value
        }
    }

    @MainActor
    private static func unwrapAXValue(
        _ value: CFTypeRef) -> Any?
    {
        guard let axVal = value as? AXValue else {
            axWarningLog("Failed to cast CFTypeRef to AXValue.")
            return nil
        }
        let axValueType = axVal.valueType

        // Log the AXValueType
        let message = """
        ValueUnwrapper.unwrapAXValue: Encountered AXValue with type: \(axValueType)
        (rawValue: \(axValueType.rawValue))
        """.trimmingCharacters(in: .whitespacesAndNewlines)
        axDebugLog(message)

        // Handle special boolean type
        if axValueType.rawValue == 4 { // kAXValueBooleanType (private)
            var boolResult: DarwinBoolean = false
            if AXValueGetValue(axVal, axValueType, &boolResult) {
                return boolResult.boolValue
            }
        }

        // Use new AXValue extensions for cleaner unwrapping
        let unwrappedExtensionValue = axVal.value()
        let valueDescription = String(describing: unwrappedExtensionValue)
        let returnMessage = "ValueUnwrapper.unwrapAXValue: axVal.value() returned: \(valueDescription) " +
            "for type: \(axValueType)"
        axDebugLog(returnMessage)
        return unwrappedExtensionValue
    }

    @MainActor
    private static func unwrapCFArray(
        _ value: CFTypeRef) -> [Any?]
    {
        guard let cfArray = value as? CFArray else {
            axWarningLog("Failed to cast CFTypeRef to CFArray.")
            return []
        }
        var swiftArray: [Any?] = []

        for index in 0..<CFArrayGetCount(cfArray) {
            guard let elementPtr = CFArrayGetValueAtIndex(cfArray, index) else {
                swiftArray.append(nil)
                continue
            }
            swiftArray.append(self.unwrap( // Recursive call uses new unwrap signature
                Unmanaged<CFTypeRef>.fromOpaque(elementPtr).takeUnretainedValue()))
        }
        return swiftArray
    }

    @MainActor
    private static func unwrapCFDictionary(
        _ value: CFTypeRef) -> [String: Any?]
    {
        guard let cfDict = value as? CFDictionary else {
            axWarningLog("Failed to cast CFTypeRef to CFDictionary.")
            return [:]
        }
        var swiftDict: [String: Any?] = [:]

        if let nsDict = cfDict as? [String: AnyObject] {
            for (key, val) in nsDict {
                swiftDict[key] = self.unwrap(val) // Recursive call uses new unwrap signature
            }
        } else {
            axWarningLog(
                "Failed to bridge CFDictionary to [String: AnyObject]. Full iteration not implemented yet.")
        }
        return swiftDict
    }
}
