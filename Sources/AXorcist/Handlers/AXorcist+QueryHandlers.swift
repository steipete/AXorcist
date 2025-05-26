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
        locator: Locator,
        maxDepth: Int?,
        requestedAttributes: [String]?,
        outputFormat: OutputFormat?
    ) async -> HandlerResponse {
        let appIdentifier = appIdentifierOrNil ?? AXMiscConstants.focusedApplicationKey
        axDebugLog("Handling query for app: \(appIdentifier), locator: \(locator)",
                   file: #file, function: #function, line: #line)

        // findTargetElement is sync
        let findResult = await findTargetElement(
            for: appIdentifier,
            locator: locator,
            maxDepthForSearch: maxDepth ?? AXMiscConstants.defaultMaxDepthSearch
        )

        guard let foundElement = findResult.element else {
            return HandlerResponse(
                data: nil,
                error: findResult.error ?? "Element not found by handleQuery."
            )
        }
        
        // applicationElement is sync
        guard let appElement = applicationElement(for: appIdentifier) else {
             axErrorLog("Application not found for path context: \(appIdentifier)")
             return buildQueryResponse(
                 element: foundElement,
                 appElement: nil, 
                 requestedAttributes: requestedAttributes,
                 outputFormat: outputFormat
             )
        }

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
        appElement: Element?,
        requestedAttributes: [String]?,
        outputFormat: OutputFormat?
    ) async -> HandlerResponse {
        let (attributes, _) = await getElementAttributes(
            element: element,
            attributes: requestedAttributes ?? [],
            outputFormat: outputFormat ?? .smart
        )
        // element.generatePathArray is sync
        let axElement = AXElement(
            attributes: attributes,
            path: element.generatePathArray(upTo: appElement)
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
        requestedAttributes: [String]?,
        maxDepth: Int?,
        outputFormat: OutputFormat?
    ) async -> HandlerResponse {
        let appIdentifier = appIdentifierOrNil ?? AXMiscConstants.focusedApplicationKey
        axDebugLog("Handling getAttributes for app: \(appIdentifier), locator: \(locator)",
                   file: #file, function: #function, line: #line)

        // findTargetElement is sync
        let findResult = await findTargetElement(
            for: appIdentifier,
            locator: locator,
            maxDepthForSearch: maxDepth ?? AXMiscConstants.defaultMaxDepthSearch
        )

        guard let foundElement = findResult.element else {
            return HandlerResponse(
                data: nil,
                error: findResult.error ?? "Element not found by handleGetAttributes."
            )
        }
        
        let (attributes, _) = await getElementAttributes(
            element: foundElement,
            attributes: requestedAttributes ?? AXorcist.defaultAttributesToFetch,
            outputFormat: outputFormat ?? .smart
        )
        
        let axElementData = AXElement(attributes: attributes, path: nil)
        return HandlerResponse(data: AnyCodable(axElementData), error: nil)
    }

    // MARK: - handleDescribeElement

    @MainActor
    public func handleDescribeElement(
        for appIdentifierOrNil: String?,
        locator: Locator,
        maxDepth: Int?,
        requestedAttributes: [String]?,
        outputFormat: OutputFormat?
    ) async -> HandlerResponse {
        let appIdentifier = appIdentifierOrNil ?? AXMiscConstants.focusedApplicationKey
        axDebugLog("Handling describeElement for app: \(appIdentifier), locator: \(locator)",
                   file: #file, function: #function, line: #line)

        let searchMaxDepth = AXMiscConstants.defaultMaxDepthSearch
        // findTargetElement is sync
        let findResult = await findTargetElement(
            for: appIdentifier,
            locator: locator,
            maxDepthForSearch: searchMaxDepth
        )

        guard let foundElement = findResult.element else {
            return HandlerResponse(
                data: nil,
                error: findResult.error ?? "Element not found by handleDescribeElement."
            )
        }
        
        // applicationElement is sync
        guard let appElement = applicationElement(for: appIdentifier) else {
            axErrorLog("Application not found for path context in describeElement: \(appIdentifier)")
            return HandlerResponse(error: "Application \(appIdentifier) not found for describeElement context.")
        }

        let descriptionTreeMaxDepth = maxDepth ?? AXMiscConstants.defaultMaxDepthDescribe

        // describeElementTree is sync (assuming its internal calls are sync)
        let elementTree = describeElementTree(
            element: foundElement,
            appElement: appElement,
            maxDepth: descriptionTreeMaxDepth,
            currentDepth: 0,
            requestedAttributes: requestedAttributes,
            outputFormat: outputFormat ?? .smart
        )

        return HandlerResponse(data: AnyCodable(elementTree), error: nil)
    }

    @MainActor
    internal func describeElementTree(
        element: Element,
        appElement: Element,
        maxDepth: Int,
        currentDepth: Int,
        requestedAttributes: [String]?,
        outputFormat: OutputFormat
    ) async -> AXElementNode {
        let (attributes, _) = await getElementAttributes(
            element: element,
            attributes: requestedAttributes ?? AXorcist.defaultAttributesToFetch,
            outputFormat: outputFormat
        )
        // element.generatePathArray is sync
        let pathArray = element.generatePathArray(upTo: appElement)

        var childrenNodes: [AXElementNode]?
        if currentDepth < maxDepth {
            // element.children is sync
            if let children = element.children() { 
                childrenNodes = children.map { childElement in
                    // Recursive call is sync
                    return describeElementTree(
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
        return AXElementNode(attributes: attributes, path: pathArray, children: childrenNodes)
    }
    
    // Gets attributes of an element, handling errors and output format.
    // This function itself doesn't need to be async if its callees (element.attribute, element.computedName) are sync.
    // This is an internal helper, potentially an instance method if it uses instance state,
    // or could be a static/global utility if it doesn't.
    // Renaming to avoid conflict with the global getElementAttributes.
    @MainActor
    internal func fetchInstanceElementAttributes(element: Element, attributes names: [String], outputFormat: OutputFormat) -> (attributes: [String: AnyCodable], errors: [String]) {
        var fetchedAttributes: [String: AnyCodable] = [:]
        var errors: [String] = []
        var effectiveAttributeNames = names

        if names.contains("*") || names.contains("all") {
            // element.attributeNames() is sync
            effectiveAttributeNames = element.attributeNames() ?? []
            // Ensure some defaults if wildcard is used
            let defaults: Set<String> = [AXAttributeNames.kAXRoleAttribute, AXAttributeNames.kAXTitleAttribute, AXAttributeNames.kAXRoleDescriptionAttribute]
            effectiveAttributeNames.append(contentsOf: defaults.filter { !effectiveAttributeNames.contains($0) })
        }
        
        // Always try to include a few key attributes for identification if not present
        let minimumDefaults: Set<String> = [AXAttributeNames.kAXRoleAttribute, AXAttributeNames.kAXTitleAttribute, "computedName"]
        for defaultAttr in minimumDefaults {
            if !effectiveAttributeNames.contains(defaultAttr) {
                effectiveAttributeNames.append(defaultAttr)
            }
        }

        for name in effectiveAttributeNames {
            if name == "computedName" { // Handle pseudo-attribute
                // element.computedName() is sync
                if let computed = element.computedName() {
                    fetchedAttributes[name] = AnyCodable(computed)
                } else {
                    // Optionally represent nil or skip
                }
                continue
            }
            // element.attribute() is sync
            if let value = element.attribute(Attribute<Any>(name)) { // Use Attribute<Any> for generic fetching
                fetchedAttributes[name] = AnyCodable(value)
            } else {
                // errors.append("Attribute '\(name)' not found or nil.") // Optionally log errors for missing attributes
            }
        }
        return (fetchedAttributes, errors)
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

