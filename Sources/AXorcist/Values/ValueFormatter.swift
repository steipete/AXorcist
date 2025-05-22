import ApplicationServices
import CoreGraphics // For CGPoint, CGSize etc.
import Foundation

// MARK: - Value Format Options

public enum ValueFormatOption {
    case `default`
    case verbose
    case short
    // Add more variants as needed, like .minimal, .debug, etc.
}

// MARK: - AXValue Formatting

@MainActor
public func formatAXValue(_ axValue: AXValue, option: ValueFormatOption = .default) -> String {
    let type = AXValueGetType(axValue)
    
    // Handle special boolean type first
    if type.rawValue == 4 {
        return formatBooleanAXValue(axValue, type: type, option: option)
    }
    
    // Handle standard AXValue types
    return formatStandardAXValue(axValue, type: type, option: option)
}

@MainActor
private func formatBooleanAXValue(_ axValue: AXValue, type: AXValueType, option: ValueFormatOption) -> String {
    var boolResult: DarwinBoolean = false
    if AXValueGetValue(axValue, type, &boolResult) {
        let result = boolResult.boolValue ? "true" : "false"
        return option == .verbose ? "<Boolean: \(result)>" : result
    }
    return "AXValue (\(stringFromAXValueType(type)))"
}

@MainActor
private func formatStandardAXValue(_ axValue: AXValue, type: AXValueType, option: ValueFormatOption) -> String {
    switch type {
    case .cgPoint:
        return formatCGPointAXValue(axValue, option: option)
    case .cgSize:
        return formatCGSizeAXValue(axValue, option: option)
    case .cgRect:
        return formatCGRectAXValue(axValue, option: option)
    case .cfRange:
        return formatCFRangeAXValue(axValue, option: option)
    case .axError:
        return formatAXErrorAXValue(axValue, option: option)
    case .illegal:
        return "Illegal AXValue"
    default:
        return "AXValue (\(stringFromAXValueType(type)))"
    }
}

@MainActor
private func formatCGPointAXValue(_ axValue: AXValue, option: ValueFormatOption) -> String {
    var point = CGPoint.zero
    if AXValueGetValue(axValue, .cgPoint, &point) {
        let result = "x=\(point.x) y=\(point.y)"
        return option == .verbose ? "<CGPoint: \(result)>" : result
    }
    return "AXValue (\(stringFromAXValueType(.cgPoint)))"
}

@MainActor
private func formatCGSizeAXValue(_ axValue: AXValue, option: ValueFormatOption) -> String {
    var size = CGSize.zero
    if AXValueGetValue(axValue, .cgSize, &size) {
        let result = "w=\(size.width) h=\(size.height)"
        return option == .verbose ? "<CGSize: \(result)>" : result
    }
    return "AXValue (\(stringFromAXValueType(.cgSize)))"
}

@MainActor
private func formatCGRectAXValue(_ axValue: AXValue, option: ValueFormatOption) -> String {
    var rect = CGRect.zero
    if AXValueGetValue(axValue, .cgRect, &rect) {
        let result = "x=\(rect.origin.x) y=\(rect.origin.y) w=\(rect.size.width) h=\(rect.size.height)"
        return option == .verbose ? "<CGRect: \(result)>" : result
    }
    return "AXValue (\(stringFromAXValueType(.cgRect)))"
}

@MainActor
private func formatCFRangeAXValue(_ axValue: AXValue, option: ValueFormatOption) -> String {
    var range = CFRange()
    if AXValueGetValue(axValue, .cfRange, &range) {
        let result = "pos=\(range.location) len=\(range.length)"
        return option == .verbose ? "<CFRange: \(result)>" : result
    }
    return "AXValue (\(stringFromAXValueType(.cfRange)))"
}

@MainActor
private func formatAXErrorAXValue(_ axValue: AXValue, option: ValueFormatOption) -> String {
    var error = AXError.success
    if AXValueGetValue(axValue, .axError, &error) {
        let result = axErrorToString(error)
        return option == .verbose ? "<AXError: \(result)>" : result
    }
    return "AXValue (\(stringFromAXValueType(.axError)))"
}

// MARK: - CFTypeRef Formatting

@MainActor
public func formatCFTypeRef(
    _ cfValue: CFTypeRef?,
    option: ValueFormatOption = .default,
    isDebugLoggingEnabled: Bool,
    currentDebugLogs: inout [String]
) -> String {
    guard let value = cfValue else { return "<nil>" }
    let typeID = CFGetTypeID(value)

    return formatCFTypeByID(
        value,
        typeID: typeID,
        option: option,
        isDebugLoggingEnabled: isDebugLoggingEnabled,
        currentDebugLogs: &currentDebugLogs
    )
}

@MainActor
private func formatCFTypeByID(
    _ value: CFTypeRef,
    typeID: CFTypeID,
    option: ValueFormatOption,
    isDebugLoggingEnabled: Bool,
    currentDebugLogs: inout [String]
) -> String {
    switch typeID {
    case AXUIElementGetTypeID():
        return formatAXUIElement(
            value,
            option: option,
            isDebugLoggingEnabled: isDebugLoggingEnabled,
            currentDebugLogs: &currentDebugLogs
        )
    case AXValueGetTypeID():
        return formatAXValue(value as! AXValue, option: option)
    case CFStringGetTypeID():
        return "\"\(escapeStringForDisplay(value as! String))\""
    case CFAttributedStringGetTypeID():
        return "\"\(escapeStringForDisplay((value as! NSAttributedString).string))\""
    case CFBooleanGetTypeID():
        return CFBooleanGetValue((value as! CFBoolean)) ? "true" : "false"
    case CFNumberGetTypeID():
        return (value as! NSNumber).stringValue
    case CFArrayGetTypeID():
        return formatCFArray(value, option: option, isDebugLoggingEnabled: isDebugLoggingEnabled, currentDebugLogs: &currentDebugLogs)
    case CFDictionaryGetTypeID():
        return formatCFDictionary(value, option: option, isDebugLoggingEnabled: isDebugLoggingEnabled, currentDebugLogs: &currentDebugLogs)
    default:
        let typeDescription = CFCopyTypeIDDescription(typeID) as String? ?? "Unknown"
        return "<Unhandled CFType: \(typeDescription)>"
    }
}

@MainActor
private func formatAXUIElement(
    _ value: CFTypeRef,
    option: ValueFormatOption,
    isDebugLoggingEnabled: Bool,
    currentDebugLogs: inout [String]
) -> String {
    let element = Element(value as! AXUIElement)
    
    // Create a simple description using available element properties
    let role = element.role(isDebugLoggingEnabled: isDebugLoggingEnabled, currentDebugLogs: &currentDebugLogs) ?? "Unknown"
    let title = element.title(isDebugLoggingEnabled: isDebugLoggingEnabled, currentDebugLogs: &currentDebugLogs)
    
    if let title = title, !title.isEmpty {
        return option == .verbose ? "<\(role): \"\(title)\">" : "\(role):\"\(title)\""
    } else {
        return option == .verbose ? "<\(role)>" : role
    }
}

@MainActor
private func formatCFArray(
    _ value: CFTypeRef,
    option: ValueFormatOption,
    isDebugLoggingEnabled: Bool,
    currentDebugLogs: inout [String]
) -> String {
    let cfArray = value as! CFArray
    let count = CFArrayGetCount(cfArray)
    
    if option == .verbose || count <= 5 {
        var swiftArray: [String] = []
        for index in 0..<count {
            guard let elementPtr = CFArrayGetValueAtIndex(cfArray, index) else {
                swiftArray.append("<nil_in_array>")
                continue
            }
            swiftArray.append(formatCFTypeRef(
                Unmanaged<CFTypeRef>.fromOpaque(elementPtr).takeUnretainedValue(),
                option: .default,
                isDebugLoggingEnabled: isDebugLoggingEnabled,
                currentDebugLogs: &currentDebugLogs
            ))
        }
        return "[\(swiftArray.joined(separator: ","))]"
    } else {
        return "<Array of size \(count)>"
    }
}

@MainActor
private func formatCFDictionary(
    _ value: CFTypeRef,
    option: ValueFormatOption,
    isDebugLoggingEnabled: Bool,
    currentDebugLogs: inout [String]
) -> String {
    let cfDict = value as! CFDictionary
    let count = CFDictionaryGetCount(cfDict)
    
    if option == .verbose || count <= 3 {
        var swiftDict: [String: String] = [:]
        if let nsDict = cfDict as? [String: AnyObject] {
            for (key, val) in nsDict {
                swiftDict[key] = formatCFTypeRef(
                    val,
                    option: .default,
                    isDebugLoggingEnabled: isDebugLoggingEnabled,
                    currentDebugLogs: &currentDebugLogs
                )
            }
        }
        let pairs = swiftDict.map { "\($0):\($1)" }.joined(separator: ",")
        return "{\(pairs)}"
    } else {
        return "<Dictionary with \(count) entries>"
    }
}

// MARK: - String Escaping Helper

private func escapeStringForDisplay(_ input: String) -> String {
    var escaped = input
    // More comprehensive escaping might be needed depending on the exact output context
    // For now, handle common cases for human-readable display.
    escaped = escaped.replacingOccurrences(of: "\\", with: "\\\\") // Escape backslashes first
    escaped = escaped.replacingOccurrences(of: "\"", with: "\\\"") // Escape double quotes
    escaped = escaped.replacingOccurrences(of: "\n", with: "\\n") // Escape newlines
    escaped = escaped.replacingOccurrences(of: "\t", with: "\\t") // Escape tabs
    escaped = escaped.replacingOccurrences(of: "\r", with: "\\r") // Escape carriage returns
    return escaped
}
