// AXValueSpecificFormatter.swift - Formats AXValue types into strings

import ApplicationServices
import CoreGraphics // For CGPoint, CGSize etc.
import Foundation

// ValueFormatOption is now from ModelEnums.swift
// Assumes stringFromAXValueType is available from ValueHelpers.swift

@MainActor
public func formatAXValue(_ axValue: AXValue, option: ValueFormatOption = .smart) -> String {
    let type = AXValueGetType(axValue)

    // Handle special boolean type first (raw value 4)
    // In some SDK versions or contexts, AXValueType might not have a direct .boolean case,
    // or a specific attribute might return a boolean-like value encoded with rawValue 4.
    if type.rawValue == 4 { // Check for boolean-like AXValue based on rawValue
        return formatBooleanAXValue(axValue, type: type, option: option)
    }

    // Handle standard AXValue types
    return formatStandardAXValue(axValue, type: type, option: option)
}

@MainActor
private func formatBooleanAXValue(_ axValue: AXValue, type: AXValueType, option: ValueFormatOption) -> String {
    var boolResult: DarwinBoolean = false // Use DarwinBoolean for AXValueGetValue
    if AXValueGetValue(axValue, type, &boolResult) {
        let result = boolResult.boolValue ? "true" : "false"
        return option == .raw ? result : "<Boolean: \(result)>" // Use .raw for plain, .smart (or other) for prefixed
    }
    // Fallback if AXValueGetValue fails
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
    @unknown default:
        // Use stringFromAXValueType for unknown cases
        return "AXValue (\(stringFromAXValueType(type)))"
    }
}

@MainActor
private func formatCGPointAXValue(_ axValue: AXValue, option: ValueFormatOption) -> String {
    var point = CGPoint.zero
    if AXValueGetValue(axValue, .cgPoint, &point) {
        let result = "x=\(point.x) y=\(point.y)"
        return option == .raw ? result : "<CGPoint: \(result)>"
    }
    return "AXValue (\(stringFromAXValueType(.cgPoint)))"
}

@MainActor
private func formatCGSizeAXValue(_ axValue: AXValue, option: ValueFormatOption) -> String {
    var size = CGSize.zero
    if AXValueGetValue(axValue, .cgSize, &size) {
        let result = "w=\(size.width) h=\(size.height)"
        return option == .raw ? result : "<CGSize: \(result)>"
    }
    return "AXValue (\(stringFromAXValueType(.cgSize)))"
}

@MainActor
private func formatCGRectAXValue(_ axValue: AXValue, option: ValueFormatOption) -> String {
    var rect = CGRect.zero
    if AXValueGetValue(axValue, .cgRect, &rect) {
        let result = "x=\(rect.origin.x) y=\(rect.origin.y) w=\(rect.size.width) h=\(rect.size.height)"
        return option == .raw ? result : "<CGRect: \(result)>"
    }
    return "AXValue (\(stringFromAXValueType(.cgRect)))"
}

@MainActor
private func formatCFRangeAXValue(_ axValue: AXValue, option: ValueFormatOption) -> String {
    var range = CFRange() // No .zero for CFRange, default init is fine.
    if AXValueGetValue(axValue, .cfRange, &range) {
        let result = "pos=\(range.location) len=\(range.length)"
        return option == .raw ? result : "<CFRange: \(result)>"
    }
    return "AXValue (\(stringFromAXValueType(.cfRange)))"
}

@MainActor
private func formatAXErrorAXValue(_ axValue: AXValue, option: ValueFormatOption) -> String {
    var error = AXError.success
    if AXValueGetValue(axValue, .axError, &error) {
        let result = error.stringValue
        return option == .raw ? result : "<AXError: \(result)>"
    }
    return "AXValue (\(stringFromAXValueType(.axError)))"
}

// stringFromAXValueType is available from ValueHelpers.swift
