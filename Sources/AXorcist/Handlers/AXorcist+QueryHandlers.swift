// AXorcist+QueryHandlers.swift - Query and search operation handlers

import AppKit
import ApplicationServices
import Foundation
// GlobalAXLogger is assumed to be available

// Define arrow separator constant for joining path hints
// private let arrowSeparator = " -> " // No longer needed here

// MARK: - Query & Search Handlers Extension
extension AXorcist {

    // MARK: - handleQuery

    @MainActor
    public func handleQuery(
        for appIdentifierOrNil: String?,
        locator: Locator, // Only locator is needed
        // pathHint: [String]?, // REMOVED
        maxDepth: Int?,
        requestedAttributes: [String]?,
        outputFormat: OutputFormat?
    ) async -> HandlerResponse {
        let appIdentifier = appIdentifierOrNil ?? AXMiscConstants.focusedApplicationKey
        axDebugLog("Handling query for app: \(appIdentifier), locator: \(locator)",
                   file: #file, function: #function, line: #line)

        // findTargetElement will handle app element creation and use locator.rootElementPathHint
        let findResult = await findTargetElement(
            for: appIdentifier,
            locator: locator,
            // pathHint parameter removed from findTargetElement call
            maxDepthForSearch: maxDepth ?? AXMiscConstants.defaultMaxDepthSearch
        )

        guard let foundElement = findResult.element else {
            return HandlerResponse(
                data: nil,
                error: findResult.error ?? "Element not found by handleQuery."
            )
        }
        
        // Need appElement for path generation in buildQueryResponse
        guard let appElement = applicationElement(for: appIdentifier) else {
             axErrorLog("Application not found for path context: \(appIdentifier)")
             // Proceed with foundElement but path might be relative or incomplete
             return buildQueryResponse(
                 element: foundElement,
                 appElement: nil, // Pass nil for appElement
                 requestedAttributes: requestedAttributes,
                 outputFormat: outputFormat
             )
        }


        // Get attributes and build response
        return buildQueryResponse(
            element: foundElement,
            appElement: appElement,
            requestedAttributes: requestedAttributes,
            outputFormat: outputFormat
        )
    }

    // Helper: Navigate with path hint if provided - REMOVED as findTargetElement handles this via locator
    /*
    @MainActor
    private func navigateWithPathHintIfNeeded(
        appElement: Element,
        pathHint: [String]?
    ) -> (element: Element?, error: String?) {
        // ... implementation removed ...
    }
    */

    // Helper: Find element with locator - REMOVED as findTargetElement handles this
    /*
    @MainActor
    private func findElementWithLocator(
        locator: Locator,
        effectiveElement: Element,
        appElement: Element,
        maxDepth: Int?
    ) -> (element: Element?, error: String?) {
        // ... implementation removed ...
    }
    */
    
    // Helper: Find search start element - REMOVED as findTargetElement handles this
    /*
    @MainActor
    private func findSearchStartElement(
        locator: Locator,
        effectiveElement: Element,
        appElement: Element
    ) -> (element: Element?, error: String?) {
        // ... implementation removed ...
    }
    */

    // Helper: Build query response - made internal to be accessible by other handlers
    @MainActor
    internal func buildQueryResponse(
        element: Element,
        appElement: Element?, // Changed to optional
        requestedAttributes: [String]?,
        outputFormat: OutputFormat?
    ) -> HandlerResponse {
        let (attributes, _) = getElementAttributes(
            element: element,
            attributes: requestedAttributes ?? [],
            outputFormat: outputFormat ?? .smart
        )

        let axElement = AXElement(
            attributes: attributes,
            path: element.generatePathArray(upTo: appElement) // Pass appElement (optional)
        )

        return HandlerResponse(
            data: AnyCodable(axElement),
            error: nil
        )
    }

    // MARK: - handleGetAttributes

    @MainActor
    public func handleGetAttributes(
        for appIdentifierOrNil: String?,
        locator: Locator,
        // pathHint: [String]?, // REMOVED
        requestedAttributes: [String]?,
        maxDepth: Int?,
        outputFormat: OutputFormat?
    ) async -> HandlerResponse {
        let appIdentifier = appIdentifierOrNil ?? AXMiscConstants.focusedApplicationKey
        axDebugLog("Handling getAttributes for app: \(appIdentifier), locator: \(locator)",
                   file: #file, function: #function, line: #line)

        // findTargetElement will handle app element creation and use locator.rootElementPathHint
        let findResult = await findTargetElement(
            for: appIdentifier,
            locator: locator,
            // pathHint parameter removed
            maxDepthForSearch: maxDepth ?? AXMiscConstants.defaultMaxDepthSearch
        )

        guard let foundElement = findResult.element else {
            return HandlerResponse(
                data: nil,
                error: findResult.error ?? "Element not found by handleGetAttributes."
            )
        }
        
        // Get attributes (without path for this specific handler)
        let (attributes, _) = getElementAttributes(
            element: foundElement,
            attributes: requestedAttributes ?? AXorcist.defaultAttributesToFetch,
            outputFormat: outputFormat ?? .smart
        )
        
        // For getAttributes, the data is often just the attributes dictionary directly.
        // Wrapping it in AXElement like query does might be okay, or return attributes directly.
        // For consistency with QueryResponse, let's make data be AXElement with only attributes set.
        let axElementData = AXElement(attributes: attributes, path: nil)


        return HandlerResponse(data: AnyCodable(axElementData), error: nil)
    }

    // MARK: - handleDescribeElement

    @MainActor
    public func handleDescribeElement(
        for appIdentifierOrNil: String?,
        locator: Locator,
        // pathHint: [String]?, // REMOVED
        maxDepth: Int?, // This maxDepth is for the description tree, not necessarily search
        requestedAttributes: [String]?,
        outputFormat: OutputFormat?
    ) async -> HandlerResponse {
        let appIdentifier = appIdentifierOrNil ?? AXMiscConstants.focusedApplicationKey
        axDebugLog("Handling describeElement for app: \(appIdentifier), locator: \(locator)",
                   file: #file, function: #function, line: #line)

        // Search maxDepth for finding the element itself.
        let searchMaxDepth = AXMiscConstants.defaultMaxDepthSearch // Use a sensible default for finding the element

        // findTargetElement will handle app element creation and use locator.rootElementPathHint
        let findResult = await findTargetElement(
            for: appIdentifier,
            locator: locator,
            // pathHint parameter removed
            maxDepthForSearch: searchMaxDepth
        )

        guard let foundElement = findResult.element else {
            return HandlerResponse(
                data: nil,
                error: findResult.error ?? "Element not found by handleDescribeElement."
            )
        }
        
        // Need appElement for path generation if it's part of the description
        guard let appElement = applicationElement(for: appIdentifier) else {
            axErrorLog("Application not found for path context in describeElement: \(appIdentifier)")
            // Fallback or error
            return HandlerResponse(error: "Application \(appIdentifier) not found for describeElement context.")
        }

        // maxDepth for describe is how deep the description tree should go
        let descriptionTreeMaxDepth = maxDepth ?? AXMiscConstants.defaultMaxDepthDescribe

        let elementTree = describeElementTree(
            element: foundElement,
            appElement: appElement, // For path context in description
            maxDepth: descriptionTreeMaxDepth,
            currentDepth: 0,
            requestedAttributes: requestedAttributes,
            outputFormat: outputFormat ?? .smart
        )

        return HandlerResponse(data: AnyCodable(elementTree), error: nil)
    }


    // MARK: - Helper: Describe Element Tree (Recursive)
    // Made internal to be accessible
    @MainActor
    internal func describeElementTree(
        element: Element,
        appElement: Element, // For path generation context
        maxDepth: Int,
        currentDepth: Int,
        requestedAttributes: [String]?,
        outputFormat: OutputFormat
    ) -> AXElementNode { // AXElementNode would be a new struct for tree description
        let (attributes, _) = getElementAttributes(
            element: element,
            attributes: requestedAttributes ?? AXorcist.defaultAttributesToFetch,
            outputFormat: outputFormat
        )
        
        let pathArray = element.generatePathArray(upTo: appElement)

        var childrenNodes: [AXElementNode]?
        if currentDepth < maxDepth {
            if let children = element.children() { // Consider if strict:true should be an option here
                childrenNodes = children.map { childElement in
                    describeElementTree(
                        element: childElement,
                        appElement: appElement,
                        maxDepth: maxDepth,
                        currentDepth: currentDepth + 1,
                        requestedAttributes: requestedAttributes,
                        outputFormat: outputFormat
                    )
                }
            }
        }
        
        // Define AXElementNode if it doesn't exist.
        // For now, assuming it's similar to AXElement but with explicit children for tree.
        return AXElementNode(
            attributes: attributes,
            path: pathArray,
            children: childrenNodes
        )
    }
}


// Define AXElementNode for describeElement output (if not already defined)
// This struct represents a node in the described element tree.
public struct AXElementNode: Codable, HandlerDataRepresentable {
    public var attributes: ElementAttributes?
    public var path: [String]?
    public var children: [AXElementNode]? // Recursive definition for children

    public init(attributes: ElementAttributes?, path: [String]? = nil, children: [AXElementNode]? = nil) {
        self.attributes = attributes
        self.path = path
        self.children = children
    }
}

// Helper function to get an application element - can be shared
// This function is already available globally as applicationElement(for:)
/*
@MainActor
internal func getApplicationElement(for identifier: String) -> Element? {
    return applicationElement(for: identifier)
}
*/

// Removed navigateToElement, as findTargetElement (and its internal findElementViaPathAndCriteria)
// now handles path navigation based on locator.rootElementPathHint.

// findTargetElement should be a global function in ElementSearch.swift or similar,
// not part of AXorcist extension, to be callable by various handlers.
// For now, assuming it's accessible. It takes 'for' (appID), 'locator', 'maxDepthForSearch'.
// The pathHint parameter for findTargetElement will be removed in its own definition.

/**
 Placeholder for the global findTargetElement function.
 Its actual implementation is in ElementSearch.swift and will be modified.
 This is just to satisfy the compiler for this file's changes.
 */
/*
@MainActor
internal func findTargetElement(
    for appIdentifier: String?,
    locator: Locator,
    maxDepthForSearch: Int
) async -> (element: Element?, error: String?) {
    // Actual implementation will be in ElementSearch.swift
    // This will use applicationElement(for:) and then findElementViaPathAndCriteria
    // using locator (which includes locator.rootElementPathHint).
    return (nil, "findTargetElement not yet fully refactored here")
}
*/
// The definition of findTargetElement needs to be adjusted in ElementSearch.swift

// Note: getElementAttributes is already a global helper.
// `search` method is part of AXorcist or ElementSearch.

