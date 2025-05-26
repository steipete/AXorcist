// TreeTraversal.swift - Defines protocols and classes for traversing the accessibility tree.

import ApplicationServices
import Foundation
// GlobalAXLogger is assumed available

// MARK: - Tree Traversal Protocols and Classes

// Protocol for a visitor that processes elements during traversal.
@MainActor
public protocol TreeVisitor {
    // Called for each element visited.
    func visit(element: Element, depth: Int, state: inout TraversalState) async -> TraversalAction
}

// Represents the result of a visitor's processing of an element.
public enum TraversalAction {
    case continueTraversal // Continue traversing children and siblings.
    case stop // Stop traversal immediately.
    case found(Element) // Element found, stop traversal.
}

// Holds the current state of a traversal (e.g., depth).
public struct TraversalState {
    public var currentDepth: Int
    public let maxDepth: Int
    public var elementsProcessed: Int
    public var branchesPruned: Int
    public let startTime: Date
    public let startElement: Element // The element from which traversal began.
    public let strictChildren: Bool // Whether to use strict children mode

    public init(maxDepth: Int, startElement: Element, strictChildren: Bool = false) {
        self.currentDepth = 0
        self.maxDepth = maxDepth
        self.elementsProcessed = 0
        self.branchesPruned = 0
        self.startTime = Date()
        self.startElement = startElement
        self.strictChildren = strictChildren
    }

    // Method to check if max depth has been exceeded.
    public func shouldStopForDepth() -> Bool {
        return currentDepth >= maxDepth
    }
    
    public mutating func incrementProcessedCount() {
        elementsProcessed += 1
    }
    
    public mutating func incrementPrunedCount() {
        branchesPruned += 1
    }
}

// REMOVED: TreeTraverser class - keeping the struct version below which is more complete

// REMOVED: CollectAllVisitor class - keeping the more complete version below

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

    public mutating func traverse(from startNode: Element, visitor: TreeVisitor, state: inout TraversalState) async -> Element? {
        let startNodeDesc = startNode.briefDescription(option: .smart)
        let logMaxDepth = state.maxDepth // Capture value for logging
        let logStrictChildren = state.strictChildren // Capture value for logging
        GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "[Traverse Entry] TreeTraverser.traverse starting from: \(startNodeDesc). MaxDepth: \(logMaxDepth), StrictChildren: \(logStrictChildren)"))
        visitedElements.removeAll()
        return await _traverse(currentElement: startNode, depth: 0, visitor: visitor, state: &state)
    }

    private mutating func _traverse(currentElement: Element, depth: Int, visitor: TreeVisitor, state: inout TraversalState) async -> Element? {
        let currentDesc = currentElement.briefDescription(option: .smart)
        GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "[_Traverse Entry] Visiting \(currentDesc) at depth \(depth)"))

        if depth > state.maxDepth {
            let maxDepth = state.maxDepth
            GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "Max depth (\(maxDepth)) reached at \(currentElement.briefDescription(option: .raw))"))
            return nil
        }

        if visitedElements.contains(currentElement) {
            GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "Cycle detected at \(currentElement.briefDescription(option: .raw)). Skipping."))
            return nil
        }
        visitedElements.insert(currentElement)
        GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "Visiting \(currentElement.briefDescription(option: .raw)) at depth \(depth)"))

        switch await visitor.visit(element: currentElement, depth: depth, state: &state) {
        case .found(let foundElement):
            GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "Element found by visitor: \(foundElement.briefDescription(option: .raw))"))
            return foundElement
        case .stop:
            GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "Traversal stopped by visitor at \(currentElement.briefDescription(option: .raw))"))
            return nil
        case .continueTraversal:
            break
        }

        guard let children = currentElement.children(strict: state.strictChildren) else {
            GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "No children for \(currentElement.briefDescription(option: .raw)) or error fetching them."))
            return nil
        }

        for child in children {
            if let found = await _traverse(currentElement: child, depth: depth + 1, visitor: visitor, state: &state) {
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
    private let filterCriteria: [Criterion]?

    public init(attributesToFetch: [String], outputFormat: OutputFormat, appElement: Element, valueFormatOption: ValueFormatOption = .smart, filterCriteria: [Criterion]? = nil) {
        self.attributesToFetch = attributesToFetch
        self.outputFormat = outputFormat
        self.appElement = appElement
        self.valueFormatOption = valueFormatOption
        self.filterCriteria = filterCriteria
    }
    
    // Convenience initializer for backward compatibility with dictionary
    public convenience init(attributesToFetch: [String], outputFormat: OutputFormat, appElement: Element, valueFormatOption: ValueFormatOption = .smart, filterCriteria: [String: String]?) {
        let criterionArray = filterCriteria?.map { key, value in
            Criterion(attribute: key, value: value, match_type: nil)
        }
        self.init(attributesToFetch: attributesToFetch, outputFormat: outputFormat, appElement: appElement, valueFormatOption: valueFormatOption, filterCriteria: criterionArray)
    }

    public func visit(element: Element, depth: Int, state: inout TraversalState) async -> TraversalAction {
        if let criteria = self.filterCriteria, !criteria.isEmpty {
            let matchesFilter = await elementMatchesCriteria(element, criteria: criteria)
            if !matchesFilter {
                GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "[CollectAllVisitor] Element \(element.briefDescription(option: .raw)) did NOT match filterCriteria. Skipping."))
                return .continueTraversal
            }
            GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "[CollectAllVisitor] Element \(element.briefDescription(option: .raw)) MATCHED filterCriteria."))
        }

        let (fetchedAttrs, _) = await getElementAttributes(
            element: element,
            attributes: attributesToFetch,
            outputFormat: outputFormat,
            valueFormatOption: self.valueFormatOption
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

    public init(locator: Locator, requireAction: String? = nil) {
        self.locator = locator
        self.requireAction = requireAction
    }

    public func visit(element: Element, depth: Int, state: inout TraversalState) async -> TraversalAction {
        elementsProcessed += 1

        if foundElement != nil {
            return .stop
        }

        if depth == 0 && elementsProcessed == 1 {
            GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "SearchVisitor: Starting new search. Locator: \(self.locator.criteria)"))
        }

        let matchStatus = await evaluateElementAgainstCriteria(
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
