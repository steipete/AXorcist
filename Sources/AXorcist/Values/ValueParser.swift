// AXValueParser.swift - Utilities for parsing string inputs into AX-compatible values

import ApplicationServices
import CoreGraphics // For CGPoint, CGSize, CGRect, CFRange
import Foundation

// GlobalAXLogger is assumed to be available

// Inspired by UIElementInspector's UIElementUtilities.m

@MainActor
public func getCFTypeIDForAttribute(element: Element, attributeName: String) -> CFTypeID? {
    // Logging will be handled by rawAttributeValue if needed, or can be added here directly.
    guard let rawValue = element.rawAttributeValue(named: attributeName) else {
        axDebugLog("getCFTypeIDForAttribute: Failed to get raw attribute value for '\(attributeName)'",
                   file: #file,
                   function: #function,
                   line: #line
        )
        return nil
    }
    return CFGetTypeID(rawValue)
}

@MainActor
public func getAXValueTypeForAttribute(element: Element, attributeName: String) -> AXValueType? {
    guard let rawValue = element.rawAttributeValue(named: attributeName) else {
        axDebugLog("getAXValueTypeForAttribute: Failed to get raw attribute value for '\(attributeName)'",
                   file: #file,
                   function: #function,
                   line: #line
        )
        return nil
    }

    guard CFGetTypeID(rawValue) == AXValueGetTypeID() else {
        axDebugLog(
            "getAXValueTypeForAttribute: Attribute '\(attributeName)' is not an AXValue. " +
                "TypeID: \(CFGetTypeID(rawValue))",
            file: #file,
            function: #function,
            line: #line
        )
        return nil
    }

    let axValue = rawValue as! AXValue
    return AXValueGetType(axValue)
}

@MainActor
public func createCFTypeRefFromString(
    stringValue: String,
    forElement element: Element,
    attributeName: String
) throws -> CFTypeRef? {
    // rawAttributeValue uses GlobalAXLogger internally if needed
    guard let currentRawValue = element.rawAttributeValue(named: attributeName) else {
        axErrorLog(
            "createCFTypeRefFromString: Could not read current value for attribute '\(attributeName)' " +
                "to determine type.",
            file: #file,
            function: #function,
            line: #line
        )
        throw AccessibilityError.attributeNotReadable(
            attribute: attributeName,
            elementDescription: element.briefDescription()
        )
    }

    let typeID = CFGetTypeID(currentRawValue)

    if typeID == AXValueGetTypeID() {
        let axValue = currentRawValue as! AXValue
        let axValueType = AXValueGetType(axValue)
        axDebugLog("Attribute '\(attributeName)' is AXValue of type: \(stringFromAXValueType(axValueType))",
                   file: #file,
                   function: #function,
                   line: #line
        )
        return try parseStringToAXValue(stringValue: stringValue, targetAXValueType: axValueType)
    } else if typeID == CFStringGetTypeID() {
        axDebugLog("Attribute '\(attributeName)' is CFString. Returning stringValue as CFString.",
                   file: #file,
                   function: #function,
                   line: #line
        )
        return stringValue as CFString
    } else if typeID == CFNumberGetTypeID() {
        axDebugLog("Attribute '\(attributeName)' is CFNumber. Attempting to parse stringValue.",
                   file: #file,
                   function: #function,
                   line: #line
        )
        if let doubleValue = Double(stringValue) {
            return NSNumber(value: doubleValue)
        } else if let intValue = Int(stringValue) {
            return NSNumber(value: intValue)
        } else {
            axWarningLog(
                "Could not parse '\(stringValue)' as Double or Int for CFNumber attribute '\(attributeName)'",
                file: #file,
                function: #function,
                line: #line
            )
            throw AccessibilityError.valueParsingFailed(
                details: "Could not parse '\(stringValue)' as Double or Int for CFNumber attribute '\(attributeName)'",
                attribute: attributeName
            )
        }
    } else if typeID == CFBooleanGetTypeID() {
        axDebugLog("Attribute '\(attributeName)' is CFBoolean. Attempting to parse stringValue as Bool.",
                   file: #file,
                   function: #function,
                   line: #line
        )
        if stringValue.lowercased() == "true" {
            return kCFBooleanTrue
        } else if stringValue.lowercased() == "false" {
            return kCFBooleanFalse
        } else {
            axWarningLog(
                "Could not parse '\(stringValue)' as Bool (true/false) for CFBoolean attribute '\(attributeName)'",
                file: #file,
                function: #function,
                line: #line
            )
            throw AccessibilityError.valueParsingFailed(
                details: "Could not parse '\(stringValue)' as Bool (true/false) for CFBoolean attribute '\(attributeName)'",
                attribute: attributeName
            )
        }
    }

    let typeDescription = CFCopyTypeIDDescription(typeID) as String? ?? "Unknown CFType"
    axErrorLog(
        "Setting attribute '\(attributeName)' of CFTypeID \(typeID) (\(typeDescription)) " +
            "from string is not supported yet.",
        file: #file,
        function: #function,
        line: #line
    )
    throw AccessibilityError.attributeUnsupported(
        attribute: "Setting attribute '\(attributeName)' of CFTypeID \(typeID) (\(typeDescription)) " +
            "from string is not supported yet.",
        elementDescription: element.briefDescription()
    )
}

@MainActor
private func parseStringToAXValue(
    stringValue: String,
    targetAXValueType: AXValueType
) throws -> AXValue? {
    let valueRef: AXValue?
    switch targetAXValueType {
    case .cgPoint:
        valueRef = try parseCGPoint(from: stringValue)
    case .cgSize:
        valueRef = try parseCGSize(from: stringValue)
    case .cgRect:
        valueRef = try parseCGRect(from: stringValue)
    case .cfRange:
        valueRef = try parseCFRange(from: stringValue)
    case .illegal:
        axErrorLog(
            "parseStringToAXValue: Attempted to parse for .illegal AXValueType.",
            file: #file,
            function: #function,
            line: #line
        )
        throw AccessibilityError.attributeUnsupported(
            attribute: "AXValueType.illegal",
            elementDescription: nil
        )
    case .axError:
        axErrorLog(
            "parseStringToAXValue: Attempted to parse for .axError AXValueType.",
            file: #file,
            function: #function,
            line: #line
        )
        throw AccessibilityError.attributeUnsupported(
            attribute: "AXValueType.axError",
            elementDescription: nil
        )
    default:
        valueRef = try parseDefaultAXValueType(from: stringValue, targetType: targetAXValueType)
    }

    if valueRef == nil {
        axErrorLog(
            "parseStringToAXValue: AXValueCreate failed for type \(stringFromAXValueType(targetAXValueType)) " +
                "with input '\(stringValue)'",
            file: #file,
            function: #function,
            line: #line
        )
        throw AccessibilityError.valueParsingFailed(
            details: "AXValueCreate failed for type \(stringFromAXValueType(targetAXValueType)) " +
                "with input '\(stringValue)'",
            attribute: stringFromAXValueType(targetAXValueType)
        )
    }
    return valueRef
}

// MARK: - Helper Functions for AXValue Parsing

@MainActor
private func parseCGPoint(from stringValue: String) throws -> AXValue? {
    var xCoord: Double = 0, yCoord: Double = 0
    let components = stringValue.replacingOccurrences(of: " ", with: "").split(separator: ",")

    if components.count == 2,
       let xValStr = components[0].split(separator: "=").last, let xVal = Double(xValStr),
       let yValStr = components[1].split(separator: "=").last, let yVal = Double(yValStr) {
        xCoord = xVal; yCoord = yVal
    } else if components.count == 2, let xVal = Double(components[0]), let yVal = Double(components[1]) {
        xCoord = xVal; yCoord = yVal
    } else {
        let scanner = Scanner(string: stringValue)
        _ = scanner.scanCharacters(in: CustomCharacterSet(charactersInString: "xy:, \t\n"))
        let xScanned = scanner.scanDouble()
        _ = scanner.scanCharacters(in: CustomCharacterSet(charactersInString: "xy:, \t\n"))
        let yScanned = scanner.scanDouble()
        if let xVal = xScanned, let yVal = yScanned {
            xCoord = xVal; yCoord = yVal
        } else {
            axWarningLog(
                "parseCGPoint: Parsing failed for '\(stringValue)' via scanner.",
                file: #file,
                function: #function,
                line: #line
            )
            throw AccessibilityError.valueParsingFailed(
                details: "Could not parse '\(stringValue)' into CGPoint. " +
                    "Expected format like 'x=10,y=20' or '10,20'.",
                attribute: "CGPoint"
            )
        }
    }
    var point = CGPoint(x: xCoord, y: yCoord)
    return AXValueCreate(.cgPoint, &point)
}

@MainActor
private func parseCGSize(from stringValue: String) throws -> AXValue? {
    var widthValue: Double = 0, heightValue: Double = 0
    let components = stringValue.replacingOccurrences(of: " ", with: "").split(separator: ",")

    if components.count == 2,
       let wValStr = components[0].split(separator: "=").last, let wVal = Double(wValStr),
       let hValStr = components[1].split(separator: "=").last, let hVal = Double(hValStr) {
        widthValue = wVal; heightValue = hVal
    } else if components.count == 2, let wVal = Double(components[0]), let hVal = Double(components[1]) {
        widthValue = wVal; heightValue = hVal
    } else {
        let scanner = Scanner(string: stringValue)
        _ = scanner.scanCharacters(in: CustomCharacterSet(charactersInString: "wh:, \t\n"))
        let wScanned = scanner.scanDouble()
        _ = scanner.scanCharacters(in: CustomCharacterSet(charactersInString: "wh:, \t\n"))
        let hScanned = scanner.scanDouble()
        if let wVal = wScanned, let hVal = hScanned {
            widthValue = wVal; heightValue = hVal
        } else {
            axWarningLog(
                "parseCGSize: Parsing failed for '\(stringValue)' via scanner.",
                file: #file,
                function: #function,
                line: #line
            )
            throw AccessibilityError.valueParsingFailed(
                details: "Could not parse '\(stringValue)' into CGSize. " +
                    "Expected format like 'w=100,h=50' or '100,50'.",
                attribute: "CGSize"
            )
        }
    }
    var size = CGSize(width: widthValue, height: heightValue)
    return AXValueCreate(.cgSize, &size)
}

@MainActor
private func parseCGRect(from stringValue: String) throws -> AXValue? {
    var xCoord: Double = 0, yCoord: Double = 0, width: Double = 0, height: Double = 0
    let components = stringValue.replacingOccurrences(of: " ", with: "").split(separator: ",")

    if components.count == 4,
       let xStr = components[0].split(separator: "=").last, let xVal = Double(xStr),
       let yStr = components[1].split(separator: "=").last, let yVal = Double(yStr),
       let wStr = components[2].split(separator: "=").last, let wVal = Double(wStr),
       let hStr = components[3].split(separator: "=").last, let hVal = Double(hStr) {
        xCoord = xVal; yCoord = yVal; width = wVal; height = hVal
    } else if components.count == 4,
              let xVal = Double(components[0]), let yVal = Double(components[1]),
              let wVal = Double(components[2]), let hVal = Double(components[3]) {
        xCoord = xVal; yCoord = yVal; width = wVal; height = hVal
    } else {
        let scanner = Scanner(string: stringValue)
        _ = scanner.scanCharacters(in: CustomCharacterSet(charactersInString: "xywh:, \t\n"))
        let xScanned = scanner.scanDouble()
        _ = scanner.scanCharacters(in: CustomCharacterSet(charactersInString: "xywh:, \t\n"))
        let yScanned = scanner.scanDouble()
        _ = scanner.scanCharacters(in: CustomCharacterSet(charactersInString: "xywh:, \t\n"))
        let wScanned = scanner.scanDouble()
        _ = scanner.scanCharacters(in: CustomCharacterSet(charactersInString: "xywh:, \t\n"))
        let hScanned = scanner.scanDouble()
        if let xString = xScanned, let yString = yScanned, let wString = wScanned, let hString = hScanned {
            xCoord = xString; yCoord = yString; width = wString; height = hString
        } else {
            axWarningLog(
                "parseCGRect: Parsing failed for '\(stringValue)' via scanner.",
                file: #file,
                function: #function,
                line: #line
            )
            throw AccessibilityError.valueParsingFailed(
                details: "Could not parse '\(stringValue)' into CGRect. " +
                    "Expected format like 'x=0,y=0,w=100,h=50' or '0,0,100,50'.",
                attribute: "CGRect"
            )
        }
    }
    var rect = CGRect(x: xCoord, y: yCoord, width: width, height: height)
    return AXValueCreate(.cgRect, &rect)
}

@MainActor
private func parseCFRange(from stringValue: String) throws -> AXValue? {
    var loc: Int = 0, len: Int = 0
    let components = stringValue.replacingOccurrences(of: " ", with: "").split(separator: ",")

    if components.count == 2,
       let locStr = components[0].split(separator: "=").last, let locVal = Int(locStr),
       let lenStr = components[1].split(separator: "=").last, let lenVal = Int(lenStr) {
        loc = locVal; len = lenVal
    } else if components.count == 2, let locVal = Int(components[0]), let lenVal = Int(components[1]) {
        loc = locVal; len = lenVal
    } else {
        let scanner = Scanner(string: stringValue)
        _ = scanner.scanCharacters(in: CustomCharacterSet(charactersInString: "loclen:, \t\n"))
        let locScanned: Int? = scanner.scanInteger()
        _ = scanner.scanCharacters(in: CustomCharacterSet(charactersInString: "loclen:, \t\n"))
        let lenScanned: Int? = scanner.scanInteger()
        if let locV = locScanned, let lenV = lenScanned {
            loc = locV
            len = lenV
        } else {
            axWarningLog(
                "parseCFRange: Parsing failed for '\(stringValue)' via scanner.",
                file: #file,
                function: #function,
                line: #line
            )
            throw AccessibilityError.valueParsingFailed(
                details: "Could not parse '\(stringValue)' into CFRange. " +
                    "Expected format like 'loc=0,len=10' or '0,10'.",
                attribute: "CFRange"
            )
        }
    }
    var range = CFRangeMake(loc, len)
    return AXValueCreate(.cfRange, &range)
}

@MainActor
private func parseDefaultAXValueType(
    from stringValue: String,
    targetType: AXValueType
) throws -> AXValue? {
    // Example for a hypothetical boolean AXValue type (targetType.rawValue == 4 was in original UIElementUtilities.m)
    // This would need mapping if AXValue could directly hold booleans.
    // Assuming 4 is a placeholder for a boolean-like AXValue type code
    if targetType.rawValue == 4 {
        if stringValue.lowercased() == "true" {
            // boolVal = true // Was unused
        } else if stringValue.lowercased() == "false" {
            // boolVal = false // Was unused
        } else {
            axWarningLog(
                "parseDefaultAXValueType: Could not parse '\(stringValue)' as boolean " +
                    "for targetType \(targetType.rawValue)",
                file: #file,
                function: #function,
                line: #line
            )
            throw AccessibilityError.valueParsingFailed(
                details: "Could not parse '\(stringValue)' as boolean for AXValueType \(targetType.rawValue)",
                attribute: stringFromAXValueType(targetType)
            )
        }
        // return AXValueCreate(targetType, &boolVal)
        // This depends on AXValueCreate supporting this targetType with DarwinBoolean
        axWarningLog(
            "parseDefaultAXValueType: AXValueCreate with DarwinBoolean for targetType \(targetType.rawValue) " +
                "is not standard/supported.",
            file: #file,
            function: #function,
            line: #line
        )
        // Or throw an error that this specific AXValueType isn't handled for creation from bool
        return nil
    }

    let typeString = stringFromAXValueType(targetType)
    let rawValue = targetType.rawValue
    axWarningLog(
        "parseDefaultAXValueType: Unhandled AXValueType '\(typeString)' (rawValue \(rawValue)) for string parsing.",
        file: #file,
        function: #function,
        line: #line
    )
    throw AccessibilityError.attributeUnsupported(
        attribute: "Parsing string to AXValue of type \(stringFromAXValueType(targetType))",
        elementDescription: nil
    )
}

// stringFromAXValueType is now defined in ValueHelpers.swift
