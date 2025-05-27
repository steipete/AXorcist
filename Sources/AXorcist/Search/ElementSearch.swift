// ElementSearch.swift - Contains search and element collection logic

import ApplicationServices
import Foundation
import Logging
// GlobalAXLogger, AXMiscConstants, JSONPathHintComponent are assumed available.

// Added logger definition
private let logger = Logger(label: "AXorcist.ElementSearch")

// MARK: - Main Element Finding Orchestration

/**
 Unified function to find a target element based on application, locator (criteria and/or JSON path hint).
 This is the primary entry point for handlers.
 */
@MainActor
public func findTargetElement(
    for appIdentifier: String,
    locator: Locator,
    maxDepthForSearch: Int
) -> (element: Element?, error: String?) {
    
    let pathHintDebugString = locator.rootElementPathHint?.map { $0.descriptionForLog() }.joined(separator: "\n    -> ") ?? "nil"
    let criteriaDebugString = locator.criteria.map { criterion in "[\(criterion.attribute):\(criterion.value), match:\(criterion.matchType?.rawValue ?? "exact")]" }.joined(separator: ", ")
    
    // Use criteriaDebugString in the log message
    var logMessage = """
FindTargetEl: START
  App: '\(appIdentifier)'
  MaxDepth: \(maxDepthForSearch)
"""
    if !criteriaDebugString.isEmpty {
        logMessage += "\n  Initial Criteria: \(criteriaDebugString)"
    } else {
        logMessage += "\n  Initial Criteria: none"
    }
    logMessage += "\n  PathHint (count: \(locator.rootElementPathHint?.count ?? 0)):\n    -> \(pathHintDebugString)"
    logger.info("\(logMessage)")

    guard let appElement = getApplicationElement(for: appIdentifier) else {
        logger.error("FindTargetEl: Could not get application element for \(appIdentifier)")
        return (nil, "Application not found or not accessible: \(appIdentifier)")
    }

    var currentSearchElement = appElement
    var searchStartingPointDescription = "application root \(appElement.briefDescription(option: .smart))"

    // 1. Navigate by pathHint if provided
    if let jsonPathComponents = locator.rootElementPathHint, !jsonPathComponents.isEmpty {
        logger.debug("FindTargetEl: Path hint provided with \(jsonPathComponents.count) components. Navigating path first from \(searchStartingPointDescription).")
        
        // Convert [JSONPathHintComponent] to [PathStep]
        let pathSteps: [PathStep] = jsonPathComponents.map { component in
            let criterion = Criterion(attribute: component.attribute, value: component.value, matchType: component.matchType)
            return PathStep(criteria: [criterion], matchType: component.matchType, matchAllCriteria: true, maxDepthForStep: component.depth)
        }
        
        if let navigatedElement = findDescendantAtPath(
            currentRoot: currentSearchElement,
            pathComponents: pathSteps, // Use converted pathSteps
            maxDepth: maxDepthForSearch, // Path navigation steps might need their own depth concept or use overall
            debugSearch: locator.debugPathSearch ?? false
        ) {
            logger.info("FindTargetEl: Path navigation successful. New search root: \(navigatedElement.briefDescription(option: ValueFormatOption.smart))")
            currentSearchElement = navigatedElement
            searchStartingPointDescription = "navigated path element \(currentSearchElement.briefDescription(option: ValueFormatOption.smart))"
        } else {
            let pathFailedError = "FindTargetEl: Path navigation failed. Could not find element at specified path hint: [\(pathHintDebugString)]"
            logger.warning("\(pathFailedError)")
            return (nil, pathFailedError)
        }
    } else {
        logger.debug("FindTargetEl: No path hint provided, or path hint was empty. Searching from \(searchStartingPointDescription).")
    }

    // 2. After path navigation (or if no path), apply final criteria from locator.criteria
    // If locator.criteria is empty, it means the path navigation itself was meant to find the target.
    if locator.criteria.isEmpty {
        if locator.rootElementPathHint?.isEmpty ?? true {
             let noCriteriaError = "FindTargetEl: No criteria provided in locator and no path hint. Cannot perform search."
            logger.error("\(noCriteriaError)")
            return (nil, noCriteriaError)
        }
        logger.info("FindTargetEl: Path hint was used and no further criteria specified. Returning element found at path: \(currentSearchElement.briefDescription(option: .smart))")
        return (currentSearchElement, nil)
    }
    
    logger.debug("FindTargetEl: Applying final criteria from locator (\(locator.criteria.count) criteria) starting from \(searchStartingPointDescription). MatchAll=\(locator.matchAll ?? true), MatchType=\(locator.criteria.first?.matchType?.rawValue ?? "default/exact")")
    
    // Use matchAll and matchType from the main Locator object for these final criteria, if they exist there.
    // Otherwise, SearchVisitor will use its defaults or what's on individual Criterion objects.
    let finalSearchMatchType = locator.criteria.first?.matchType ?? .exact // Simplified: take from first criterion or default
    let finalSearchMatchAll = locator.matchAll ?? true
    
    let searchVisitor = SearchVisitor(
        criteria: locator.criteria,
        matchType: finalSearchMatchType,
        matchAllCriteria: finalSearchMatchAll,
        stopAtFirstMatch: true, // For the final search, we typically want the first match.
        maxDepth: maxDepthForSearch
    )
    
    traverseAndSearch(element: currentSearchElement, visitor: searchVisitor, currentDepth: 0, maxDepth: maxDepthForSearch)
    
    if let foundMatch = searchVisitor.foundElement { // Changed from foundElements.first
        logger.info("FindTargetEl: Found final descendant matching criteria: \(foundMatch.briefDescription(option: .smart))")
        return (foundMatch, nil)
    } else {
        let criteriaDesc = locator.criteria.map { "\($0.attribute):\($0.value)" }.joined(separator: ", ")
        let finalSearchError = "FindTargetEl: No element found matching final criteria [\(criteriaDesc)] starting from \(searchStartingPointDescription)."
        logger.warning("\(finalSearchError)")
        return (nil, finalSearchError)
    }
}

// MARK: - Element Collection Logic

@MainActor
public func collectAllElements(
    from startElement: Element,
    matching criteria: [Criterion]? = nil,
    maxDepth: Int = AXMiscConstants.defaultMaxDepthSearch,
    includeIgnored: Bool = false
) -> [Element] {
    let criteriaDebugString = criteria?.map { "\($0.attribute):\($0.value)(\($0.match_type?.rawValue ?? "exact"))" }.joined(separator: ", ") ?? "all"
    logger.info("CollectAll: From [\(startElement.briefDescription(option: ValueFormatOption.smart))], Criteria: [\(criteriaDebugString)], MaxDepth: \(maxDepth), Ignored: \(includeIgnored)")
    
    let visitor = CollectAllVisitor(criteria: criteria, includeIgnored: includeIgnored)
    traverseAndSearch(element: startElement, visitor: visitor, currentDepth: 0, maxDepth: maxDepth)
    
    logger.info("CollectAll: Found \(visitor.collectedElements.count) elements.")
    return visitor.collectedElements
}

// MARK: - Generic Tree Traversal with Visitor

// Protocol for visitors used in tree traversal
@MainActor
public protocol ElementVisitor {
    // If visit returns .stop, traversal stops. If .skipChildren, children of current element are not visited.
    // Otherwise, traversal continues (.continue).
    func visit(element: Element, depth: Int) -> TreeVisitorResult
}

public enum TreeVisitorResult {
    case `continue`
    case skipChildren
    case stop
}

@MainActor
public func traverseAndSearch(
    element: Element,
    visitor: ElementVisitor,
    currentDepth: Int,
    maxDepth: Int
) {
    if currentDepth > maxDepth {
        logger.debug("Traverse: Max depth \(maxDepth) reached at [\(element.briefDescription(option: ValueFormatOption.smart))]. Stopping this branch.")
        return
    }

    let visitResult = visitor.visit(element: element, depth: currentDepth)

    switch visitResult {
    case .stop:
        logger.debug("Traverse: Visitor requested STOP at [\(element.briefDescription(option: ValueFormatOption.smart))] depth \(currentDepth).")
        return
    case .skipChildren:
        logger.debug("Traverse: Visitor requested SKIP_CHILDREN at [\(element.briefDescription(option: ValueFormatOption.smart))] depth \(currentDepth).")
        return // Do not process children
    case .continue:
        logger.debug("Traverse: Visitor requested CONTINUE at [\(element.briefDescription(option: ValueFormatOption.smart))] depth \(currentDepth). Processing children.")
        // Continue to process children
        break 
    }

    if let children = element.children() {
        for child in children {
            traverseAndSearch(element: child, visitor: visitor, currentDepth: currentDepth + 1, maxDepth: maxDepth)
             // If the visitor is a SearchVisitor that stops at first match, check if it found something.
            if let searchVisitor = visitor as? SearchVisitor, searchVisitor.stopAtFirstMatchInternal, searchVisitor.foundElement != nil {
                logger.debug("Traverse: SearchVisitor found match and stopAtFirstMatch is true. Stopping traversal early.")
                return // Stop traversal early
            }
        }
    }
}

// MARK: - Search Visitor Implementation

@MainActor
public class SearchVisitor: ElementVisitor {
    public var foundElement: Element? // Stores the first element that matches criteria
    public var allFoundElements: [Element] = [] // Stores all elements that match criteria
    private let criteria: [Criterion]
    internal let stopAtFirstMatchInternal: Bool
    private let maxDepth: Int
    private var currentMaxDepthReachedByVisitor: Int = 0
    private let matchType: JSONPathHintComponent.MatchType // Added
    private let matchAllCriteriaBool: Bool // Added (renamed to avoid conflict with func name)

    init(
        criteria: [Criterion], 
        matchType: JSONPathHintComponent.MatchType = .exact, // Added with default
        matchAllCriteria: Bool = true, // Added with default
        stopAtFirstMatch: Bool = false, 
        maxDepth: Int = AXMiscConstants.defaultMaxDepthSearch
    ) {
        self.criteria = criteria
        self.matchType = matchType // Store
        self.matchAllCriteriaBool = matchAllCriteria // Store
        self.stopAtFirstMatchInternal = stopAtFirstMatch
        self.maxDepth = maxDepth
        logger.debug("SearchVisitor Init: Criteria: \(criteria.map { "\($0.attribute):\($0.value)(\($0.match_type?.rawValue ?? "exact"))" }.joined(separator: ", ")), StopAtFirst: \(stopAtFirstMatchInternal), MaxDepth: \(maxDepth), MatchType: \(matchType), MatchAll: \(matchAllCriteria)")
    }

    @MainActor
    public func visit(element: Element, depth: Int) -> TreeVisitorResult {
        currentMaxDepthReachedByVisitor = max(currentMaxDepthReachedByVisitor, depth)
        if depth > maxDepth {
            logger.debug("SearchVisitor: Max depth \(maxDepth) reached internally at [\(element.briefDescription(option: ValueFormatOption.smart))]. Skipping.")
            return .skipChildren // Or .stop, depending on desired behavior beyond maxDepth by visitor
        }

        let elementDesc = element.briefDescription(option: ValueFormatOption.smart)
        logger.debug("SearchVisitor Visiting: [\(elementDesc)] at depth \(depth). Criteria: \(criteria.map { "\($0.attribute):\($0.value)"}.joined(separator: ", "))")

        var matches = false
        if matchAllCriteriaBool {
            // Use the stored matchType
            if elementMatchesAllCriteria(element: element, criteria: criteria, matchType: self.matchType) {
                matches = true
            }
        } else {
            // Use the stored matchType
            if elementMatchesAnyCriterion(element: element, criteria: criteria, matchType: self.matchType) {
                matches = true
            }
        }

        if matches {
            logger.debug("SearchVisitor MATCH: [\(elementDesc)] at depth \(depth).")
            foundElement = element
            allFoundElements.append(element)
            if stopAtFirstMatchInternal {
                logger.debug("SearchVisitor: stopAtFirstMatchInternal is true. Stopping search.")
                return .stop
            }
        } else {
            logger.debug("SearchVisitor NO MATCH: [\(elementDesc)] at depth \(depth).")
        }
        return .continue
    }

    // Resets the visitor state for reuse, e.g., when searching different branches of a tree.
    public func reset() {
        self.foundElement = nil
        self.allFoundElements.removeAll()
        self.currentMaxDepthReachedByVisitor = 0 // Reset depth
        // logger.debug("SearchVisitor reset.") // Optional: for debugging visitor lifecycle
    }
}

// MARK: - Collect All Visitor Implementation

@MainActor
public class CollectAllVisitor: ElementVisitor {
    private(set) var collectedElements: [Element] = []
    let criteria: [Criterion]?
    let includeIgnored: Bool

    init(criteria: [Criterion]? = nil, includeIgnored: Bool = false) {
        self.criteria = criteria
        self.includeIgnored = includeIgnored
        let criteriaDebug = criteria?.map { "\($0.attribute):\($0.value)(\($0.match_type?.rawValue ?? "exact"))" }.joined(separator: ", ") ?? "all"
        logger.debug("CollectAllVisitor Init: Criteria: [\(criteriaDebug)], IncludeIgnored: \(includeIgnored)")
    }

    public func visit(element: Element, depth: Int) -> TreeVisitorResult {
        let elementDesc = element.briefDescription(option: ValueFormatOption.smart)
        logger.debug("CollectAllVisitor Visiting: [\(elementDesc)] at depth \(depth).")

        if !includeIgnored && element.isIgnored() {
            logger.debug("CollectAllVisitor: Skipping ignored element [\(elementDesc)] because includeIgnored is false.")
            return .skipChildren // Skip ignored elements and their children if not including ignored
        }

        if let criteria = criteria {
            if elementMatchesAllCriteria(element: element, criteria: criteria) {
                logger.debug("CollectAllVisitor: Adding [\(elementDesc)] (matched criteria).")
                collectedElements.append(element)
            } else {
                logger.debug("CollectAllVisitor: [\(elementDesc)] did NOT match criteria.")
            }
        } else {
            // No criteria, collect all (respecting includeIgnored)
            logger.debug("CollectAllVisitor: Adding [\(elementDesc)] (no criteria given).")
            collectedElements.append(element)
        }
        return .continue
    }
}

// Note: Ensure `getApplicationElement` from PathNavigator is accessible and synchronous.
// Ensure `navigateToElementByJSONPathHint` from PathNavigator is accessible and synchronous.
// Ensure `elementMatchesAllCriteria` from SearchCriteriaUtils is accessible and synchronous.
// Ensure `Criterion` struct and `Locator` struct are defined and accessible.
// AXMiscConstants should be available. Example: public enum AXMiscConstants { public static let defaultMaxDepthSearch: Int = 10 }
