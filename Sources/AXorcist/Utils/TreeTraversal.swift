// TreeTraversal.swift - Unified accessibility tree traversal with cycle detection

import ApplicationServices
import Foundation
// GlobalAXLogger is assumed available

// MARK: - Core Traversal Types & Protocols

public enum TraversalAction {
    case continueTraversal
    case found(Element)
    case stop
}

// TraversalState now only holds non-logging related traversal state.
public struct TraversalState {
    public let maxDepth: Int
    public let startElement: Element // Could be useful for context if GlobalAXLogger needs it indirectly
    public let strictChildren: Bool // New flag
    // Add other non-logging state if needed by visitors, e.g., a shared Set for specific tracking.

    public init(maxDepth: Int, startElement: Element, strictChildren: Bool = false) { // Default to false
        self.maxDepth = maxDepth
        self.startElement = startElement
        self.strictChildren = strictChildren
    }
}

public protocol TreeVisitor {
    @MainActor func visit(element: Element, depth: Int, state: inout TraversalState) -> TraversalAction
}

// This is the actual data structure that CollectAllVisitor.collectedElements will contain.
// Moved here from CollectAllHandler as it's part of the traversal output.
public struct AXElementData: Codable {
    public var path: [String]?
    public var attributes: [String: AnyCodable]
    public var role: String?
    public var computedName: String?
}

// MARK: - Unified Tree Traverser

@MainActor
public struct TreeTraverser {
    private var visitedElements: Set<Element> = []

    public init() {}

    public mutating func traverse(from startNode: Element, visitor: TreeVisitor, state: inout TraversalState) -> Element? {
        let startNodeDesc = startNode.briefDescription(option: .default)
        let logMaxDepth = state.maxDepth // Capture value for logging
        let logStrictChildren = state.strictChildren // Capture value for logging
        axDebugLog("[Traverse Entry] TreeTraverser.traverse starting from: \(startNodeDesc). MaxDepth: \(logMaxDepth), StrictChildren: \(logStrictChildren)")
        visitedElements.removeAll()
        return _traverse(currentElement: startNode, depth: 0, visitor: visitor, state: &state)
    }

    private mutating func _traverse(currentElement: Element, depth: Int, visitor: TreeVisitor, state: inout TraversalState) -> Element? {
        let currentDesc = currentElement.briefDescription(option: .default) // Corrected label
        axDebugLog("[_Traverse Entry] Visiting \(currentDesc) at depth \(depth)") // MODIFIED LOG

        if depth > state.maxDepth {
            let maxDepth = state.maxDepth
            axDebugLog("Max depth (\(maxDepth)) reached at \(currentElement.briefDescription())")
            return nil
        }

        if visitedElements.contains(currentElement) {
            axDebugLog("Cycle detected at \(currentElement.briefDescription()). Skipping.")
            return nil
        }
        visitedElements.insert(currentElement)
        axDebugLog("Visiting \(currentElement.briefDescription()) at depth \(depth)")

        switch visitor.visit(element: currentElement, depth: depth, state: &state) {
        case .found(let foundElement):
            axDebugLog("Element found by visitor: \(foundElement.briefDescription())")
            return foundElement
        case .stop:
            axDebugLog("Traversal stopped by visitor at \(currentElement.briefDescription())")
            return nil
        case .continueTraversal:
            break
        }

        guard let children = currentElement.children(strict: state.strictChildren) else {
            axDebugLog("No children for \(currentElement.briefDescription()) or error fetching them.")
            return nil
        }

        for child in children {
            if let found = _traverse(currentElement: child, depth: depth + 1, visitor: visitor, state: &state) {
                return found
            }
        }
        return nil
    }
}

// MARK: - Visitor Implementations

@MainActor
public class CollectAllVisitor: TreeVisitor {
    private let attributesToFetch: [String]
    private let outputFormat: OutputFormat
    private let appElement: Element // Used for path generation relative to app root
    public var collectedElements: [AXElementData] = []
    // Default valueFormatOption for CollectAllVisitor if not specified otherwise
    private let valueFormatOption: ValueFormatOption

    public init(attributesToFetch: [String], outputFormat: OutputFormat, appElement: Element, valueFormatOption: ValueFormatOption = .default) {
        self.attributesToFetch = attributesToFetch
        self.outputFormat = outputFormat
        self.appElement = appElement
        self.valueFormatOption = valueFormatOption
    }

    public func visit(element: Element, depth: Int, state: inout TraversalState) -> TraversalAction {
        // getElementAttributes is now a global function
        let (fetchedAttrs, _) = getElementAttributes(
            element: element,
            attributes: attributesToFetch, // Pass the correct attributes list
            outputFormat: outputFormat,
            valueFormatOption: self.valueFormatOption // Use the stored/defaulted option
        )

        let elementPath = element.generatePathArray(upTo: appElement)
        let role = element.role()
        let compName = element.computedName()

        let elementData = AXElementData(
            path: elementPath,
            attributes: fetchedAttrs,
            role: role,
            computedName: compName
        )
        collectedElements.append(elementData)
        return .continueTraversal
    }
}

@MainActor
public class SearchVisitor: TreeVisitor {
    private let locator: Locator
    private let requireAction: String?
    private var foundElement: Element?
    private var elementsProcessed: Int = 0
    public static var totalVisitsGlobally: Int = 0
    public static var lastLoggedTotalVisits: Int = 0

    public static func resetGlobalVisitCount() {
        totalVisitsGlobally = 0
        lastLoggedTotalVisits = 0
    }

    public init(locator: Locator, requireAction: String? = nil) {
        self.locator = locator
        self.requireAction = requireAction
    }

    public func visit(element: Element, depth: Int, state: inout TraversalState) -> TraversalAction {
        elementsProcessed += 1
        SearchVisitor.totalVisitsGlobally += 1

        if SearchVisitor.totalVisitsGlobally % 250 == 0 {
            axDebugLog("[TEMP DEBUG] SearchVisitor Global Visits: \(SearchVisitor.totalVisitsGlobally)")
        }

        if SearchVisitor.totalVisitsGlobally % 500 == 0 && SearchVisitor.totalVisitsGlobally > SearchVisitor.lastLoggedTotalVisits {
            axDebugLog("SearchVisitor.visit global call count reached: \(SearchVisitor.totalVisitsGlobally)")
            SearchVisitor.lastLoggedTotalVisits = SearchVisitor.totalVisitsGlobally
        }

        if foundElement != nil {
            return .stop
        }

        if depth == 0 && elementsProcessed == 1 {
            axDebugLog("SearchVisitor: Starting new search. Global visits: \(SearchVisitor.totalVisitsGlobally). Locator: \(self.locator.criteria)")
        }

        let matchStatus = evaluateElementAgainstCriteria(
            element: element,
            locator: locator,
            actionToVerify: requireAction ?? locator.requireAction,
            depth: depth
        )

        switch matchStatus {
        case .fullMatch:
            foundElement = element
            return .found(element)
        case .noMatch, .partialMatchActionMissing:
            return .continueTraversal
        }
    }
}

// REMOVED: dLog global helper - use GlobalAXLogger directly.
// REMOVED: Element extensions for briefDescriptionForDebug and pidString - use refactored Element methods.
