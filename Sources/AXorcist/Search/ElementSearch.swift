// ElementSearch.swift - Contains search and element collection logic

import ApplicationServices
import Foundation
// GlobalAXLogger is assumed available

// PathHintComponent and criteriaMatch are now in SearchCriteriaUtils.swift

// MARK: - Main Search Logic (findElementViaPathAndCriteria and its helpers)

@MainActor
private func navigateToElementByPathHint(
    pathHint: [PathHintComponent],
    initialSearchElement: Element,
    pathHintMaxDepth: Int
) -> Element? {
    var currentElementInPath = initialSearchElement
    axDebugLog(
        "PathHintNav: Starting with \(pathHint.count) components from " +
            "\(initialSearchElement.briefDescription())"
    )

    for (index, pathComponent) in pathHint.enumerated() {
        let currentNavigationDepth = index
        let criteriaDesc = pathComponent.criteria.map { "\($0.key):\($0.value)" }.joined(separator: ", ")
        axDebugLog(
            "PathHintNav: Visiting comp #\(index), Depth:\(currentNavigationDepth), " +
                "Elem:\(currentElementInPath.briefDescription(option: .short)), " +
                "Crit:\(criteriaDesc), MaxD:\(pathHintMaxDepth)"
        )

        if !pathComponent.matches(element: currentElementInPath) {
            axDebugLog(
                "PathHintNav: No match for comp #\(index), " +
                    "Elem:\(currentElementInPath.briefDescription(option: .short)), " +
                    "Crit:\(criteriaDesc))"
            )
            return nil
        }

        axDebugLog(
            "PathHintNav: Matched comp #\(index), " +
                "Elem:\(currentElementInPath.briefDescription(option: .short)), " +
                "Crit:\(criteriaDesc))"
        )

        if index == pathHint.count - 1 {
            return currentElementInPath // Reached end of path hint and matched
        }

        let nextPathComponentCriteria = pathHint[index + 1].criteria
        var foundNextChild: Element?
        if let children = currentElementInPath.children() {
            for child in children {
                let tempPathComponent = PathHintComponent(criteria: nextPathComponentCriteria)
                if tempPathComponent.matches(element: child) {
                    currentElementInPath = child
                    foundNextChild = child
                    break
                }
            }
        }

        if foundNextChild == nil {
            let nextCriteriaDesc = nextPathComponentCriteria
                .map { "\($0.key):\($0.value)" }.joined(separator: ", ")
            axDebugLog(
                "PathHintNav: Could not find child for next comp #\(index + 1), " +
                    "Under Elem:\(currentElementInPath.briefDescription(option: .short)), " +
                    "NextCrit:\(nextCriteriaDesc))"
            )
            return nil
        }
    }
    return currentElementInPath
}

@MainActor
private func traverseAndSearch(
    currentElement: Element,
    locator: Locator,
    effectiveMaxDepth: Int
) -> Element? {
    var traverser = TreeTraverser()
    let visitor = SearchVisitor(locator: locator)
    var traversalState = TraversalState(maxDepth: effectiveMaxDepth, startElement: currentElement)
    let result = traverser.traverse(from: currentElement, visitor: visitor, state: &traversalState)
    return result
}

@MainActor
private func processPathHintAndDetermineStartElement(
    application: Element,
    locator: Locator
) -> Element {
    guard let pathHintStrings = locator.rootElementPathHint, !pathHintStrings.isEmpty else {
        axDebugLog("No path hint provided. Searching from application root.")
        return application
    }

    let pathHintComponents = pathHintStrings.compactMap { PathHintComponent(pathSegment: $0) }

    guard !pathHintComponents.isEmpty && pathHintComponents.count == pathHintStrings.count else {
        axDebugLog(
            "Path hint strings provided but failed to parse into components or " +
                "some were invalid. Full search from app root."
        )
        return application
    }

    axDebugLog("Starting path hint navigation. Number of components: \(pathHintComponents.count)")

    if let elementFromPathHint = navigateToElementByPathHint(
        pathHint: pathHintComponents,
        initialSearchElement: application,
        pathHintMaxDepth: pathHintComponents.count - 1
    ) {
        axDebugLog(
            "Path hint navigation successful. New start: " +
                "\(elementFromPathHint.briefDescription()). Starting criteria search."
        )
        return elementFromPathHint
    } else {
        axDebugLog("Path hint navigation failed. Full search from app root.")
        return application
    }
}

@MainActor
func findElementViaPathAndCriteria(
    application: Element,
    locator: Locator,
    maxDepth: Int?
) -> Element? {
    let pathHintDebug = locator.rootElementPathHint?.joined(separator: " -> ") ?? "nil"
    axDebugLog(
        "[findElementViaPathAndCriteria ENTRY] locator.criteria: \(locator.criteria), " +
            "locator.rootElementPathHint: \(pathHintDebug) from app PID \(application.pid() ?? -1)"
    )

    let searchStartElement = processPathHintAndDetermineStartElement(
        application: application,
        locator: locator
    )
    let resolvedMaxDepth = maxDepth ?? AXMiscConstants.defaultMaxDepthSearch

    return traverseAndSearch(
        currentElement: searchStartElement,
        locator: locator,
        effectiveMaxDepth: resolvedMaxDepth
    )
}

enum ElementMatchStatus {
    case fullMatch
    case partialMatchActionMissing
    case noMatch
}

@MainActor
internal func evaluateElementAgainstCriteria(
    element: Element,
    locator: Locator,
    actionToVerify: String?,
    depth: Int // Depth might still be useful for logical purposes, not for logging state
) -> ElementMatchStatus {

    if locator.rootElementPathHint != nil, !locator.rootElementPathHint!.isEmpty {
        axDebugLog(
            "evaluateElement: Path hint was present in locator, assuming pre-navigated. " +
                "Element: \(element.briefDescription())"
        )
    }

    if !criteriaMatch(element: element, criteria: locator.criteria) {
        return .noMatch
    }

    if let actionName = actionToVerify, !actionName.isEmpty {
        if !element.isActionSupported(actionName) {
            axDebugLog(
                "Element \(element.briefDescription()) matches criteria but is " +
                    "missing required action '\(actionName)'."
            )
            return .noMatch
        }
        axDebugLog("Element \(element.briefDescription()) matches criteria AND has required action '\(actionName)'.")
    } else {
        axDebugLog("Element \(element.briefDescription()) matches criteria. No specific action required by this check.")
    }

    return .fullMatch
}

@MainActor
public func search(element: Element,
                   locator: Locator,
                   requireAction: String?,
                   depth: Int = 0, // Default depth for initial call
                   maxDepth: Int = AXMiscConstants.defaultMaxDepthSearch
) -> Element? {
    var traverser = TreeTraverser() // Refactored
    let visitor = SearchVisitor(locator: locator, requireAction: requireAction) // Refactored init

    var state = TraversalState(maxDepth: maxDepth, startElement: element)

    let result = traverser.traverse(from: element, visitor: visitor, state: &state)
    return result
}

// searchWithCycleDetection is now fully redundant because TreeTraverser handles cycle detection.
// It can be removed or kept as an alias if existing code calls it extensively.
// For now, let's comment it out as its logic is covered by the main `search`.
/*
 @MainActor
 public func searchWithCycleDetection(element: Element,
 locator: Locator,
 requireAction: String?,
 depth: Int = 0,
 maxDepth: Int = AXMiscConstants.defaultMaxDepthSearch,
 visitedElements: inout Set<Element>
 // This param is problematic for a global logger model
 ) -> Element? {
 // This function's original purpose is now handled by TreeTraverser's internal visitedElements set.
 axDebugLog("searchWithCycleDetection called (now an alias for regular search). Consider direct use of search().")
 return search(element: element, locator: locator, requireAction: requireAction,
 depth: depth, maxDepth: maxDepth)
 }
 */

@MainActor
public func collectAll(
    appElement: Element, // Root element of the application, for path context
    locator: Locator,
    // Criteria for matching elements (though CollectAllVisitor doesn't use it for filtering currently)
    currentElement: Element, // The element to start collecting from
    depth: Int, // Initial depth, usually 0
    maxDepth: Int, // Max depth to traverse
    maxElements: Int,
    // Max number of elements to collect (Note: visitor collects, traverser doesn't stop based on this yet)
    visitor: CollectAllVisitor // Pass in an initialized CollectAllVisitor
) {
    axDebugLog(
        "collectAll: Setting up traversal. MaxDepth: \(maxDepth), " +
            "MaxElements: \(maxElements) for locator: \(locator.criteria)"
    )

    var traverser = TreeTraverser()
    var state = TraversalState(maxDepth: maxDepth, startElement: currentElement)

    _ = traverser.traverse(from: currentElement, visitor: visitor, state: &state)

    axDebugLog("collectAll: Traversal complete. Visitor collected \(visitor.collectedElements.count) elements.")
}

// Remaining functions in this file (like path navigation helpers if any outside findElementViaPathAndCriteria)
// would need similar review and refactoring if they use the old logging pattern.

// MARK: - Element Search Logic

// [REMOVED OLD findElement FUNCTION]

// MARK: - Path Navigator (Remains mostly the same, but uses TraversalContext for logging)

// [REMOVED OLD navigateToElementByPath FUNCTION]
