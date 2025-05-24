// TextExtraction.swift - Utilities for extracting textual content from Elements.

import ApplicationServices // For Element and kAX...Attribute constants
import Foundation

// Assumes Element is defined and has an `attribute(String) -> String?` method.
// Constants like kAXValueAttribute are expected to be available (e.g., from AccessibilityConstants.swift)
// axValue<T>() is assumed to be globally available from ValueHelpers.swift

@MainActor
public func extractTextContent(
    element: Element
) -> String {
    let elementDescription = element.briefDescription(option: .default) // Uses GlobalAXLogger internally
    axDebugLog("Extracting text content for element: \(elementDescription)",
               file: #file,
               function: #function,
               line: #line
    )
    var texts: [String] = []
    let textualAttributes = [
        AXAttributeNames.kAXValueAttribute, AXAttributeNames.kAXTitleAttribute, AXAttributeNames.kAXDescriptionAttribute, AXAttributeNames.kAXHelpAttribute,
        AXAttributeNames.kAXPlaceholderValueAttribute, AXAttributeNames.kAXLabelValueAttribute, AXAttributeNames.kAXRoleDescriptionAttribute
        // Consider adding stringForRangeParameterizedAttribute if dealing with large text views for performance
        // selectedTextAttribute could also be relevant depending on use case
    ]
    for attrName in textualAttributes {
        // axValue uses GlobalAXLogger internally
        if let strValue: String = axValue(
            of: element.underlyingElement,
            attr: attrName
        ), !strValue.isEmpty, strValue.lowercased() != AXMiscConstants.kAXNotAvailableString.lowercased() {
            texts.append(strValue)
        }
    }

    // Deduplicate while preserving order
    var uniqueTexts: [String] = []
    var seenTexts = Set<String>()
    for text in texts where !seenTexts.contains(text) {
        uniqueTexts.append(text)
        seenTexts.insert(text)
    }
    return uniqueTexts.joined(separator: "\n")
}
