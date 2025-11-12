import ApplicationServices
import CoreGraphics // For CGPoint, CGSize etc.
import Foundation

// MARK: - Value Format Options

// Remove local SimpleValueFormatOption, use ModelEnums.ValueFormatOption
// public enum SimpleValueFormatOption {
//    case `default`
//    case verbose
//    case short
// }

// MARK: - CFTypeRef Formatting

@MainActor
public func formatCFTypeRef(
    _ cfValue: CFTypeRef?,
    option: ValueFormatOption = .smart, // Changed from SimpleValueFormatOption & .default to ValueFormatOption & .smart
) -> String {
    guard let value = cfValue else { return "<nil>" }
    let typeID = CFGetTypeID(value)

    return formatCFTypeByID(
        value,
        typeID: typeID,
        option: option)
}

@MainActor
private func formatCFTypeByID(
    _ value: CFTypeRef,
    typeID: CFTypeID,
    option: ValueFormatOption, // Changed from SimpleValueFormatOption
) -> String {
    switch typeID {
    case AXUIElementGetTypeID():
        return formatAXUIElement(
            value,
            option: option)
    case AXValueGetTypeID():
        guard let axValue = value as? AXValue else {
            axWarningLog("formatCFTypeByID: Expected AXValue but received \(value).")
            return "<Invalid AXValue>"
        }
        return formatAXValue(axValue, option: option)
    case CFStringGetTypeID():
        guard let stringValue = value as? String else {
            return "<Invalid String>"
        }
        return "\"\(escapeStringForDisplay(stringValue))\""
    case CFAttributedStringGetTypeID():
        guard let attributedString = value as? NSAttributedString else {
            return "<Invalid AttributedString>"
        }
        return "\"\(escapeStringForDisplay(attributedString.string))\""
    case CFBooleanGetTypeID():
        guard let boolValue = value as? CFBoolean else {
            return "<Invalid Boolean>"
        }
        return CFBooleanGetValue(boolValue) ? "true" : "false"
    case CFNumberGetTypeID():
        guard let number = value as? NSNumber else {
            return "<Invalid Number>"
        }
        return number.stringValue
    case CFArrayGetTypeID():
        return formatCFArray(value, option: option)
    case CFDictionaryGetTypeID():
        return formatCFDictionary(value, option: option)
    default:
        let typeDescription = CFCopyTypeIDDescription(typeID) as String? ?? "Unknown"
        // Use GlobalAXLogger for unhandled types if necessary, though format functions usually just return strings.
        axDebugLog(
            "formatCFTypeByID: Unhandled CFType: \(typeDescription) for value. Returning description string.",
            file: #file,
            function: #function,
            line: #line)
        return "<Unhandled CFType: \(typeDescription)>"
    }
}

@MainActor
private func formatAXUIElement(
    _ value: CFTypeRef,
    option: ValueFormatOption, // Changed from SimpleValueFormatOption
) -> String {
    guard let axElement = value as? AXUIElement else {
        axWarningLog("formatAXUIElement: Failed to cast CFTypeRef to AXUIElement.")
        return "<Invalid AXUIElement>"
    }
    let element = Element(axElement)

    // Element.role() and .title() will use GlobalAXLogger internally
    let role = element.role() ?? "Unknown"
    let title = element.title()

    // Adjust logic based on ValueFormatOption cases (.smart, .raw, .stringified)
    if let title, !title.isEmpty {
        return option == .raw ? // Example: .raw means minimal
            "\\(role):\\\"\\(escapeStringForDisplay(title))\\\"" :
            "<\\(role): \\\"\\(escapeStringForDisplay(title))\\\">" // .smart or .stringified are more verbose
    } else {
        return option == .raw ? role : "<\\(role)>"
    }
}

@MainActor
private func formatCFArray(
    _ value: CFTypeRef,
    option: ValueFormatOption, // Changed from SimpleValueFormatOption
) -> String {
    guard let cfArray = value as? CFArray else {
        return "<Invalid Array>"
    }
    let count = CFArrayGetCount(cfArray)

    // Adjust logic based on ValueFormatOption cases
    if option != .raw || count <= 5 { // Example: .raw might mean short, others verbose
        var swiftArray: [String] = []
        for index in 0..<count {
            guard let elementPtr = CFArrayGetValueAtIndex(cfArray, index) else {
                swiftArray.append("<nil_in_array>")
                continue
            }
            swiftArray.append(formatCFTypeRef(
                Unmanaged<CFTypeRef>.fromOpaque(elementPtr).takeUnretainedValue(),
                option: .smart, // Recursive calls, .smart is a good default
            ))
        }
        return "[\\(swiftArray.joined(separator: \", \"))]"
    } else {
        return "<Array of size \(count)>"
    }
}

@MainActor
private func formatCFDictionary(
    _ value: CFTypeRef,
    option: ValueFormatOption, // Changed from SimpleValueFormatOption
) -> String {
    guard let cfDict = value as? CFDictionary else {
        return "<Invalid Dictionary>"
    }
    let count = CFDictionaryGetCount(cfDict)

    // Adjust logic based on ValueFormatOption cases
    if option != .raw || count <= 3 { // Example: .raw might mean short, others verbose
        var swiftDict: [String: String] = [:]
        // More robust CFDictionary iteration if direct bridging fails
        if let nsDict = cfDict as? [String: AnyObject] {
            for (key, val) in nsDict {
                swiftDict[key] = formatCFTypeRef(
                    val,
                    option: .smart, // Recursive calls, .smart is a good default
                )
            }
        } else {
            axWarningLog(
                "formatCFDictionary: Failed to bridge CFDictionary to [String: AnyObject]. " +
                    "Iteration might be incomplete.",
                file: #file,
                function: #function,
                line: #line)
            // Implement manual iteration if necessary for full support, though this is a formatter.
        }
        let pairs = swiftDict.map { "\"\(escapeStringForDisplay($0))\": \($1)" }
            .sorted()
            .joined(separator: ", ")
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
