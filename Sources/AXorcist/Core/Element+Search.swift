//
//  Element+Search.swift
//  AXorcist
//
//  Provides search functionality for accessibility elements
//

import ApplicationServices
import Foundation

// MARK: - Search Options

/// Options for customizing element search behavior
public struct ElementSearchOptions {
    /// Maximum depth to search (0 = unlimited)
    public var maxDepth: Int = 0

    /// Whether to search case-insensitively (default: true)
    public var caseInsensitive: Bool = true

    /// Whether to search only visible elements
    public var visibleOnly: Bool = false

    /// Whether to search only enabled elements
    public var enabledOnly: Bool = false

    /// Roles to include in search (empty = all roles)
    public var includeRoles: Set<String> = []

    /// Roles to exclude from search
    public var excludeRoles: Set<String> = []

    public init() {}
}

// MARK: - Element Search Extensions

extension Element {
    /// Search for elements matching a query string
    /// - Parameters:
    ///   - query: The search query to match against element properties
    ///   - options: Search options to customize behavior
    /// - Returns: Array of matching elements
    @MainActor
    public func searchElements(
        matching query: String,
        options: ElementSearchOptions = ElementSearchOptions()) -> [Element]
    {
        var results: [Element] = []
        traverseAXTree(
            from: self,
            maxDepth: options.maxDepth > 0 ? options.maxDepth : nil)
        { element, _ in
            if element.matches(query: query, options: options) {
                results.append(element)
            }
            return .continue
        }
        return results
    }

    /// Find the first element matching a query string
    /// - Parameters:
    ///   - query: The search query to match against element properties
    ///   - options: Search options to customize behavior
    /// - Returns: First matching element, or nil if none found
    @MainActor
    public func findElement(
        matching query: String,
        options: ElementSearchOptions = ElementSearchOptions()) -> Element?
    {
        var result: Element?
        traverseAXTree(
            from: self,
            maxDepth: options.maxDepth > 0 ? options.maxDepth : nil)
        { element, _ in
            guard element.matches(query: query, options: options) else {
                return .continue
            }
            result = element
            return .stop
        }
        return result
    }

    /// Search for elements by role
    /// - Parameters:
    ///   - role: The role to search for (e.g., "AXButton", "AXTextField")
    ///   - options: Search options to customize behavior
    /// - Returns: Array of elements with the specified role
    @MainActor
    public func searchElements(
        byRole role: String,
        options: ElementSearchOptions = ElementSearchOptions()) -> [Element]
    {
        var results: [Element] = []
        traverseAXTree(
            from: self,
            maxDepth: options.maxDepth > 0 ? options.maxDepth : nil)
        { element, _ in
            if options.visibleOnly, element.isHidden() == true {
                return .skipChildren
            }
            if options.enabledOnly, element.isEnabled() == false {
                return .skipChildren
            }
            if element.role() == role {
                results.append(element)
            }
            return .continue
        }
        return results
    }

    /// Check if element matches a search query
    /// - Parameters:
    ///   - query: The search query to match against
    ///   - options: Search options to customize matching
    /// - Returns: True if element matches the query
    @MainActor
    public func matches(query: String, options: ElementSearchOptions = ElementSearchOptions()) -> Bool {
        // Check visibility and enabled state if required
        if options.visibleOnly, isHidden() == true {
            return false
        }
        if options.enabledOnly, isEnabled() == false {
            return false
        }

        // Check role filters
        if let role = role() {
            if !options.includeRoles.isEmpty, !options.includeRoles.contains(role) {
                return false
            }
            if options.excludeRoles.contains(role) {
                return false
            }
        }

        // Prepare query for comparison
        let searchQuery = options.caseInsensitive ? query.lowercased() : query

        // Check various text properties
        let properties = [
            title(),
            label(),
            stringValue(),
            placeholderValue(),
            descriptionText(),
            roleDescription(),
            help(),
            identifier(),
        ]

        for property in properties {
            if let text = property {
                let compareText = options.caseInsensitive ? text.lowercased() : text
                if compareText.contains(searchQuery) {
                    return true
                }
            }
        }

        return false
    }
}

// MARK: - Convenience Methods

extension Element {
    /// Find all buttons in the element hierarchy
    @MainActor
    public func findAllButtons() -> [Element] {
        self.searchElements(byRole: "AXButton")
    }

    /// Find all text fields in the element hierarchy
    @MainActor
    public func findAllTextFields() -> [Element] {
        self.searchElements(byRole: "AXTextField")
    }

    /// Find all links in the element hierarchy
    @MainActor
    public func findAllLinks() -> [Element] {
        self.searchElements(byRole: "AXLink")
    }

    /// Find element by identifier
    @MainActor
    public func findElement(byIdentifier identifier: String) -> Element? {
        var result: Element?
        traverseAXTree(from: self) { element, _ in
            if element.identifier() == identifier {
                result = element
                return .stop
            }
            return .continue
        }
        return result
    }
}
