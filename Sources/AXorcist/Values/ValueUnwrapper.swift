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
            return unsafeDowncast(value, to: AXUIElement.self)
        case ApplicationServices.AXValueGetTypeID():
            return self.unwrapAXValue(value)
        case CFStringGetTypeID():
            let cfString = unsafeDowncast(value, to: CFString.self)
            return cfString as String
        case CFAttributedStringGetTypeID():
            let attributedString = unsafeDowncast(value, to: NSAttributedString.self)
            return attributedString.string
        case CFBooleanGetTypeID():
            let cfBool = unsafeDowncast(value, to: CFBoolean.self)
            return CFBooleanGetValue(cfBool)
        case CFNumberGetTypeID():
            return unsafeDowncast(value, to: NSNumber.self)
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
        let axVal = unsafeDowncast(value, to: AXValue.self)
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
        let cfArray = unsafeDowncast(value, to: CFArray.self)
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
        let cfDict = unsafeDowncast(value, to: CFDictionary.self)
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
