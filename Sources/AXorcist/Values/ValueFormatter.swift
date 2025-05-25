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

// MARK: - CFTypeRef Formatting

@MainActor
public func formatCFTypeRef(
    _ cfValue: CFTypeRef?,
    option: ValueFormatOption = .default
) -> String {
    guard let value = cfValue else { return "<nil>" }
    let typeID = CFGetTypeID(value)

    return formatCFTypeByID(
        value,
        typeID: typeID,
        option: option
    )
}

@MainActor
private func formatCFTypeByID(
    _ value: CFTypeRef,
    typeID: CFTypeID,
    option: ValueFormatOption
) -> String {
    switch typeID {
    case AXUIElementGetTypeID():
        return formatAXUIElement(
            value,
            option: option
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
        return formatCFArray(value, option: option)
    case CFDictionaryGetTypeID():
        return formatCFDictionary(value, option: option)
    default:
        let typeDescription = CFCopyTypeIDDescription(typeID) as String? ?? "Unknown"
        // Use GlobalAXLogger for unhandled types if necessary, though format functions usually just return strings.
        axDebugLog("formatCFTypeByID: Unhandled CFType: \(typeDescription) for value. Returning description string.",
                   file: #file,
                   function: #function,
                   line: #line
        )
        return "<Unhandled CFType: \(typeDescription)>"
    }
}

@MainActor
private func formatAXUIElement(
    _ value: CFTypeRef,
    option: ValueFormatOption
) -> String {
    let element = Element(value as! AXUIElement)

    // Element.role() and .title() will use GlobalAXLogger internally
    let role = element.role() ?? "Unknown"
    let title = element.title()

    if let title = title, !title.isEmpty {
        return option == .verbose ?
            "<\(role): \"\(escapeStringForDisplay(title))\">" :
            "\(role):\"\(escapeStringForDisplay(title))\""
    } else {
        return option == .verbose ? "<\(role)>" : role
    }
}

@MainActor
private func formatCFArray(
    _ value: CFTypeRef,
    option: ValueFormatOption
) -> String {
    let cfArray = value as! CFArray
    let count = CFArrayGetCount(cfArray)

    if option == .verbose || count <= 5 { // Arbitrary limit for verbose array printing
        var swiftArray: [String] = []
        for index in 0..<count {
            guard let elementPtr = CFArrayGetValueAtIndex(cfArray, index) else {
                swiftArray.append("<nil_in_array>")
                continue
            }
            swiftArray.append(formatCFTypeRef(
                Unmanaged<CFTypeRef>.fromOpaque(elementPtr).takeUnretainedValue(),
                option: .default // Recursive calls typically use default/short format for elements
            ))
        }
        return "[\(swiftArray.joined(separator: ", "))]" // Added space for readability
    } else {
        return "<Array of size \(count)>"
    }
}

@MainActor
private func formatCFDictionary(
    _ value: CFTypeRef,
    option: ValueFormatOption
) -> String {
    let cfDict = value as! CFDictionary
    let count = CFDictionaryGetCount(cfDict)

    if option == .verbose || count <= 3 { // Arbitrary limit for verbose dictionary printing
        var swiftDict: [String: String] = [:]
        // More robust CFDictionary iteration if direct bridging fails
        if let nsDict = cfDict as? [String: AnyObject] {
            for (key, val) in nsDict {
                swiftDict[key] = formatCFTypeRef(
                    val,
                    option: .default // Recursive calls typically use default/short format for values
                )
            }
        } else {
            axWarningLog(
                "formatCFDictionary: Failed to bridge CFDictionary to [String: AnyObject]. " +
                    "Iteration might be incomplete.",
                file: #file,
                function: #function,
                line: #line
            )
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
