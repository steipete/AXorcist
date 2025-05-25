// ElementSearch.swift - Contains search and element collection logic

import ApplicationServices
import Foundation
// GlobalAXLogger is assumed available

// PathHintComponent and criteriaMatch are now in SearchCriteriaUtils.swift

// MARK: - Main Element Finding Orchestration

/**
 Unified function to find a target element based on application, locator (criteria and/or path hint).
 This is the primary entry point for handlers.
 */
@MainActor
public func findTargetElement(
    for appIdentifierOrNil: String?,
    locator: Locator,
    maxDepthForSearch: Int
) async -> (element: Element?, error: String?) { // Changed return type to match old handlers
    let appIdentifier = appIdentifierOrNil ?? AXMiscConstants.focusedApplicationKey
    axDebugLog(
        "[findTargetElement ENTRY] App=\(appIdentifier), Locator: criteria=\(locator.criteria), " +
        "pathHint=\(locator.rootElementPathHint?.joined(separator: "->") ?? "nil")"
    )

    guard let appElement = applicationElement(for: appIdentifier) else {
        let msg = "Application not found: \(appIdentifier)"
        axErrorLog(msg)
        return (nil, msg)
    }

    let pathHintStrings = locator.rootElementPathHint
    let criteria = locator.criteria

    // Scenario 1: Only pathHint is provided (or criteria are app-specific)
    let appSpecificCriteriaKeys = ["bundleId", "application", "pid", "path"]
    let hasOnlyAppSpecificCriteria = criteria.isEmpty || criteria.keys.allSatisfy { appSpecificCriteriaKeys.contains($0) }

    if let hintStrings = pathHintStrings, !hintStrings.isEmpty, hasOnlyAppSpecificCriteria {
        axDebugLog("findTargetElement: Using pathHint primarily as criteria are app-specific or empty.")
        let pathComponents = hintStrings.compactMap { PathHintComponent(pathSegment: $0) }
        if pathComponents.count != hintStrings.count {
            let msg = "Invalid path hint components provided."
            axWarningLog(msg)
            // Fall through to regular search if path hint is malformed but criteria exist
            if criteria.isEmpty { return (nil, msg) }
        } else if !pathComponents.isEmpty {
            if let elementFromPath = /* private */ navigateToElementByPathHint(
                pathHint: pathComponents,
                initialSearchElement: appElement,
                pathHintMaxDepth: pathComponents.count - 1 // Navigate full path
            ) {
                axInfoLog("findTargetElement: Found element directly via pathHint: \(elementFromPath.briefDescription())")
                // If caller specified descendantCriteria, search within the located element.
                if let descCrit = locator.descendantCriteria, !descCrit.isEmpty {
                    axDebugLog("findTargetElement: Performing descendantCriteria search within located element. Descendant criteria: \(descCrit)")
                    var descLocator = Locator(criteria: descCrit)
                    if let descendant = traverseAndSearch(currentElement: elementFromPath,
                                                               locator: descLocator,
                                                               effectiveMaxDepth: maxDepthForSearch) {
                        return (descendant, nil)
                    } else {
                        return (nil, "Descendant element not found matching descendantCriteria: \(descCrit)")
                    }
                }
                return (elementFromPath, nil)
            } else {
                let msg = "Element not found via pathHint: \(hintStrings.joined(separator: " -> "))"
                axWarningLog(msg)
                return (nil, msg) // Path hint was specified but failed
            }
        }
    }

    // Scenario 2: Criteria are present (potentially with a pathHint to narrow down search root)
    // findElementViaPathAndCriteria will use pathHint from locator to find searchStartElement,
    // then apply criteria.
    axDebugLog("findTargetElement: Proceeding with criteria-based search (pathHint may refine start).")
    if let foundElement = findElementViaPathAndCriteria(
        application: appElement,
        locator: locator, // This locator contains both criteria and potentially rootElementPathHint
        maxDepth: maxDepthForSearch
    ) {
        axInfoLog("findTargetElement: Found element via criteria (and/or path): \(foundElement.briefDescription())")
        var baseElement = foundElement
        // Apply descendantCriteria if present
        if let descCrit = locator.descendantCriteria, !descCrit.isEmpty {
            axDebugLog("findTargetElement: Performing descendantCriteria search within base element. Descendant criteria: \(descCrit)")
            let descLoc = Locator(criteria: descCrit)
            if let descendant = traverseAndSearch(currentElement: baseElement,
                                                   locator: descLoc,
                                                   effectiveMaxDepth: maxDepthForSearch) {
                baseElement = descendant
            } else {
                let msg = "Descendant element not found matching descendantCriteria: \(descCrit)"
                axWarningLog(msg)
                return (nil, msg)
            }
        }

        return (baseElement, nil)
    } else {
        let msg = "Element not found matching criteria: \(locator.criteria)"
        if let hint = locator.rootElementPathHint, !hint.isEmpty {
            axWarningLog("\(msg) (path hint was: \(hint.joined(separator: " -> ")))")
        } else {
            axWarningLog(msg)
        }
        return (nil, msg)
    }
}

// MARK: - Core Search Logic (findElementViaPathAndCriteria and its helpers)

@MainActor
/* private -> internal */ internal func navigateToElementByPathHint(
    pathHint: [PathHintComponent],
    initialSearchElement: Element,
    pathHintMaxDepth: Int // Max depth for THIS path navigation segment
) -> Element? {
    var currentElementInPath = initialSearchElement
    axDebugLog(
        "PathHintNav: Starting with \(pathHint.count) components from " +
            "\(initialSearchElement.briefDescription()), maxNavDepth: \(pathHintMaxDepth)"
    )

    for (index, pathComponent) in pathHint.enumerated() {
        if index > pathHintMaxDepth { // Respect max depth for this navigation
            axDebugLog("PathHintNav: Max navigation depth (\(pathHintMaxDepth)) reached at component #\(index).")
            return currentElementInPath // Return what we have so far
        }
        
        let criteriaDesc = pathComponent.criteria.map { "\($0.key):\($0.value)" }.joined(separator: ", ")
        axDebugLog(
            "PathHintNav: Visiting comp #\(index), Depth:\(index), " +
                "Elem:\(currentElementInPath.briefDescription(option: .short)), " +
                "Crit:\(criteriaDesc))"
        )

        // Check if the current element in path matches the current path component
        // This logic was a bit off. The component should match the *current* element, not its children.
        if !pathComponent.matches(element: currentElementInPath) {
            axDebugLog(
                "PathHintNav: Current element \(currentElementInPath.briefDescription(option: .short)) " +
                "does NOT match comp #\(index) Crit:\(criteriaDesc))"
            )
            return nil // Path broken
        }

        axDebugLog(
            "PathHintNav: Matched comp #\(index), " +
                "Elem:\(currentElementInPath.briefDescription(option: .short)), " +
                "Crit:\(criteriaDesc))"
        )

        // If this is the last component, we've successfully navigated the path
        if index == pathHint.count - 1 {
            return currentElementInPath
        }

        // Not the last component, so we need to find a child that matches the *next* component
        guard let children = currentElementInPath.children() else {
            axDebugLog("PathHintNav: Current element \(currentElementInPath.briefDescription(option: .short)) has no children. Cannot proceed to next component.")
            return nil // Path broken, cannot find next step
        }
        
        let nextPathComponent = pathHint[index + 1]
        var foundNextChildInPath: Element? = nil
        for child in children {
            if nextPathComponent.matches(element: child) {
                currentElementInPath = child // Advance current element
                foundNextChildInPath = child
                break
            }
        }

        if foundNextChildInPath == nil {
            let nextCriteriaDesc = nextPathComponent.criteria.map { "\($0.key):\($0.value)" }.joined(separator: ", ")
            axDebugLog(
                "PathHintNav: Could not find child matching next comp #\(index + 1) " +
                "(Crit: \(nextCriteriaDesc)) under Elem:\(currentElementInPath.briefDescription(option: .short))"
            )
            return nil // Path broken, cannot find next step
        }
    }
    // Should have returned from within the loop if path was fully matched or broken
    // If loop finishes it means pathHint was empty or logic error
    return pathHint.isEmpty ? initialSearchElement : nil 
}

@MainActor
private func traverseAndSearch(
    currentElement: Element,
    locator: Locator,
    effectiveMaxDepth: Int
) -> Element? {
    // Ensure criteria exist if we are in traverseAndSearch. 
    // If only path hint was used, findTargetElement should have returned earlier.
    if locator.criteria.isEmpty {
        axDebugLog("traverseAndSearch: Called with empty criteria. This usually means element should have been found by path hint alone. Returning current element: \(currentElement.briefDescription())")
        // This might be the element found by path hint if criteria were indeed empty.
        return currentElement 
    }

    var traverser = TreeTraverser()
    let visitor = SearchVisitor(locator: locator) // SearchVisitor uses locator.criteria
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
        axDebugLog("processPathHint: No rootElementPathHint provided in locator. Searching from application root.")
        return application
    }

    let pathHintComponents = pathHintStrings.compactMap { PathHintComponent(pathSegment: $0) }

    guard !pathHintComponents.isEmpty && pathHintComponents.count == pathHintStrings.count else {
        axDebugLog(
            "processPathHint: rootElementPathHint strings provided but failed to parse into components or " +
                "some were invalid. Full search from app root."
        )
        return application
    }

    axDebugLog("processPathHint: Starting path hint navigation for search root. Number of components: \(pathHintComponents.count)")

    if let elementFromPathHint = /* private -> internal */ navigateToElementByPathHint(
        pathHint: pathHintComponents,
        initialSearchElement: application,
        pathHintMaxDepth: pathHintComponents.count - 1 // Navigate the full path to find the start element
    ) {
        axDebugLog(
            "processPathHint: Path hint navigation successful. New search start: " +
                "\(elementFromPathHint.briefDescription())."
        )
        return elementFromPathHint
    } else {
        axWarningLog("processPathHint: Path hint navigation failed. Full search will be from app root. Path: \(pathHintStrings.joined(separator: " -> "))")
        return application
    }
}

/**
 This function is the core for criteria-based search, potentially starting from an element 
 determined by a path hint (via locator.rootElementPathHint).
 */
@MainActor
/* internal -> func */ func findElementViaPathAndCriteria(
    application: Element,
    locator: Locator,
    maxDepth: Int?
) -> Element? {
    let pathHintDebug = locator.rootElementPathHint?.joined(separator: " -> ") ?? "nil"
    let criteriaDebug = locator.criteria
    axDebugLog(
        "[findElementViaPathAndCriteria ENTRY] AppPID: \(application.pid() ?? -1), Locator.criteria: \(criteriaDebug), " +
            "Locator.rootElementPathHint: \(pathHintDebug)"
    )

    // Determine the actual starting element for the criteria search.
    // If locator.rootElementPathHint is present, navigate to it. Otherwise, start from app root.
    let searchStartElement = processPathHintAndDetermineStartElement(
        application: application,
        locator: locator
    )
    
    // If criteria are empty at this point, it means the path hint (if any) was the sole specifier.
    // The searchStartElement is our target.
    if locator.criteria.isEmpty {
        if locator.rootElementPathHint != nil && !locator.rootElementPathHint!.isEmpty {
             axInfoLog("[findElementViaPathAndCriteria] Criteria are empty, path hint was primary. Returning element from path: \(searchStartElement.briefDescription())")
             return searchStartElement // Element found by path hint is the target
        } else {
            axWarningLog("[findElementViaPathAndCriteria] Criteria are empty and no path hint. Returning application root by default.")
            return application // Or nil if this case isn't desired
        }
    }
    
    axDebugLog("[findElementViaPathAndCriteria] Search start element: \(searchStartElement.briefDescription()). Now applying criteria: \(locator.criteria)")

    let resolvedMaxDepth = maxDepth ?? AXMiscConstants.defaultMaxDepthSearch

    return traverseAndSearch(
        currentElement: searchStartElement,
        locator: locator, // Locator contains criteria
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

    // Path hint check here might be less relevant if pre-navigation is robust
    // if locator.rootElementPathHint != nil, !locator.rootElementPathHint!.isEmpty {
    //     axDebugLog(
    //         "evaluateElement: Path hint was present in locator, assuming pre-navigated. " +
    //             "Element: \(element.briefDescription())"
    //     )
    // }

    if !criteriaMatch(element: element, criteria: locator.criteria) {
        return .noMatch
    }

    if let actionName = actionToVerify, !actionName.isEmpty {
        if !element.isActionSupported(actionName) {
            axDebugLog(
                "Element \(element.briefDescription()) matches criteria but is " +
                    "missing required action '\(actionName)'."
            )
            return .noMatch // Changed from partialMatchActionMissing to noMatch for stricter interpretation
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
/* public -> internal */ internal func collectAll(
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
    // The traverse method in TreeTraverser doesn't directly use maxElements from TraversalState to stop.
    // The CollectAllVisitor's visit method should implement the maxElements check.
    _ = traverser.traverse(from: currentElement, visitor: visitor, state: &state)
    // Result of traverse is Element? (the first one found), but for collectAll we rely on visitor's side effects.
    axDebugLog("collectAll: Traversal complete. Collected \(visitor.collectedElements.count) elements.")
}

// Remaining functions in this file (like path navigation helpers if any outside findElementViaPathAndCriteria)
// would need similar review and refactoring if they use the old logging pattern.

// MARK: - Element Search Logic

// [REMOVED OLD findElement FUNCTION]

// MARK: - Path Navigator (Remains mostly the same, but uses TraversalContext for logging)

// [REMOVED OLD navigateToElementByPath FUNCTION]
