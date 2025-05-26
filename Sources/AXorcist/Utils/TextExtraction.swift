// TextExtraction.swift - Utilities for extracting text from accessibility elements

import ApplicationServices
import Foundation

@MainActor
func extractTextFromElement(_ element: Element, maxDepth: Int = 2, currentDepth: Int = 0) async -> String? {
    // Basic attributes first
    var components: [String] = []

    if let title: String = element.attribute(Attribute<String>.title) { components.append(title) }
    if let value: String = element.attribute(Attribute<String>(AXAttributeNames.kAXValueAttribute)) { components.append(value) }
    if let description: String = element.attribute(Attribute<String>.description) { components.append(description) }
    if let placeholder: String = element.attribute(Attribute<String>.placeholderValue) { components.append(placeholder) }
    if let help: String = element.attribute(Attribute<String>.help) { components.append(help) }

    // If we have some text, or we've reached max depth, return
    if !components.isEmpty || currentDepth >= maxDepth {
        let joinedText = components.filter { !$0.isEmpty }.joined(separator: " ")
        if !joinedText.isEmpty {
            GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "TextExtraction: Found text '\(joinedText)' at depth \(currentDepth) for element \(element.briefDescription(option: .smart))"))
        }
        return joinedText.isEmpty ? nil : joinedText
    }

    // Recursively check children if no text found yet and depth allows
    if let children = element.children() {
        for child in children {
            if let childText = await extractTextFromElement(child, maxDepth: maxDepth, currentDepth: currentDepth + 1) {
                components.append(childText)
            }
        }
    }

    let finalText = components.filter { !$0.isEmpty }.joined(separator: " ")
    if !finalText.isEmpty {
        GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "TextExtraction: Aggregated text '\(finalText)' at depth \(currentDepth) for element \(element.briefDescription(option: .smart))"))
    }
    return finalText.isEmpty ? nil : finalText
}

// More focused text extraction, typically used by handlers.
@MainActor
func getElementTextualContent(element: Element, includeChildren: Bool = false, maxDepth: Int = 1, currentDepth: Int = 0) async -> String? {
    var textPieces: [String] = []

    // Prioritize attributes common for text content
    if let title: String = element.attribute(Attribute<String>.title) { textPieces.append(title) }
    if let value: String = element.attribute(Attribute<String>(AXAttributeNames.kAXValueAttribute)) { textPieces.append(value) }
    if let description: String = element.attribute(Attribute<String>.description) { textPieces.append(description) }
    if let placeholder: String = element.attribute(Attribute<String>.placeholderValue) { textPieces.append(placeholder) }
    // Less common but potentially useful
    // if let help: String = element.attribute(Attribute.help) { textPieces.append(help) }
    // if let selectedText: String = element.attribute(Attribute.selectedText) { textPieces.append(selectedText) }

    let joinedDirectText = textPieces.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)

    if includeChildren && currentDepth < maxDepth { 
        if let children = element.children() {
            var childTexts: [String] = []
            for child in children {
                if let childTextContent = await getElementTextualContent(element: child, includeChildren: true, maxDepth: maxDepth, currentDepth: currentDepth + 1) {
                    childTexts.append(childTextContent)
                }
            }
            let joinedChildText = childTexts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            if !joinedChildText.isEmpty {
                // Smartly join parent and child text, avoiding duplicates if child text is part of parent text.
                if joinedDirectText.isEmpty {
                    return joinedChildText
                } else if joinedChildText.isEmpty {
                    return joinedDirectText
                } else {
                    // A more sophisticated joining might be needed if there's overlap.
                    // For now, simple space join.
                    return "\(joinedDirectText) \(joinedChildText)"
                }
            }
        }
    }
    
    if !joinedDirectText.isEmpty {
         GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "TextExtraction/Content: Extracted '\(joinedDirectText)' for element \(element.briefDescription(option: .smart)) (children included: \(includeChildren), depth: \(currentDepth))"))
        return joinedDirectText
    }
    
    GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "TextExtraction/Content: No direct text found for \(element.briefDescription(option: .smart)) (children included: \(includeChildren), depth: \(currentDepth))"))
    return nil
}
