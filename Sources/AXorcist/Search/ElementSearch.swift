// ElementSearch.swift - Contains search and element collection logic

import ApplicationServices
import Foundation
// GlobalAXLogger is assumed available

// JSONPathHintComponent is in Models/JSONPathHintComponent.swift

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
) async -> (element: Element?, error: String?) {
    
    let pathHintDebugString = locator.rootElementPathHint?.map { component in "(attr: \\(component.attribute), val: \\(component.value), depth: \\(component.depth ?? -1))" }.joined(separator: "; ") ?? "nil"
    GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: 
        "[findTargetElement ENTRY] App=\\(appIdentifier), Locator: criteria=\(locator.criteria), " +
        "jsonPathHint=[\\(pathHintDebugString)]"
    ))

    guard let appElement = applicationElement(for: appIdentifier) else {
        let msg = "Application not found: \\(appIdentifier)"
        GlobalAXLogger.shared.log(AXLogEntry(level: .error, message: msg))
        return (nil, msg)
    }

    let jsonPathComponents = locator.rootElementPathHint ?? []
    let hasOnlyAppSpecificCriteria = locator.criteria.allSatisfy { criterion in 
        let key = criterion.attribute.lowercased()
        return key == "pid" || key == "bundleid" || key == "appname" 
    }

    if !jsonPathComponents.isEmpty && hasOnlyAppSpecificCriteria {
        GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "findTargetElement: Using JSONPathHint primarily as criteria are app-specific or empty."))
        if let elementFromPath = await navigateToElementByJSONPathHint(
            pathHint: jsonPathComponents,
            initialSearchElement: appElement
        ) {
            GlobalAXLogger.shared.log(AXLogEntry(level: .info, message: "findTargetElement: Found element directly via JSONPathHint: \\(elementFromPath.briefDescription(option: .smart))"))
            if let descCrit = locator.descendantCriteria, !descCrit.isEmpty {
                GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "findTargetElement: Performing descendantCriteria search. DescCriteria: \\(descCrit)"))
                // Convert descendantCriteria dictionary to [Criterion]
                let descCriteria = descCrit.map { key, value in
                    Criterion(attribute: key, value: value, match_type: nil)
                }
                let descLocator = Locator(criteria: descCriteria)
                if let descendant = await traverseAndSearch(currentElement: elementFromPath,
                                                          locator: descLocator,
                                                          maxDepth: maxDepthForSearch) {
                    return (descendant, nil)
                } else {
                    return (nil, "Element found by path hint, but descendant criteria did not match.")
                }
            }
            return (elementFromPath, nil)
        } else {
            let msg = "Element not found via JSONPathHint: [\\(pathHintDebugString)]"
            GlobalAXLogger.shared.log(AXLogEntry(level: .warning, message: msg))
            return (nil, msg)
        }
    }

    GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "findTargetElement: Proceeding with criteria-based search (JSONPathHint may refine start)."))
    if let foundElement = await findElementViaCriteriaAndJSONPathHint(
        application: appElement,
        locator: locator,
        maxDepth: maxDepthForSearch
    ) {
        GlobalAXLogger.shared.log(AXLogEntry(level: .info, message: "findTargetElement: Found via criteria (and/or JSONPathHint): \\(foundElement.briefDescription(option: .smart))"))
        var baseElement = foundElement
        if let descCrit = locator.descendantCriteria, !descCrit.isEmpty {
            GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "findTargetElement: Performing descendantCriteria search. DescCriteria: \\(descCrit)"))
            // Convert descendantCriteria dictionary to [Criterion]
            let descCriteria = descCrit.map { key, value in
                Criterion(attribute: key, value: value, match_type: nil)
            }
            let descLoc = Locator(criteria: descCriteria)
            if let descendant = await traverseAndSearch(currentElement: baseElement,
                                                      locator: descLoc,
                                                      maxDepth: maxDepthForSearch) {
                baseElement = descendant
            } else {
                let msg = "Descendant element not found matching: \\(descCrit)"
                GlobalAXLogger.shared.log(AXLogEntry(level: .warning, message: msg))
                return (nil, msg)
            }
        }
        return (baseElement, nil)
    } else {
        let msg = "Element not found matching criteria: \\(locator.criteria)"
        if !jsonPathComponents.isEmpty {
            GlobalAXLogger.shared.log(AXLogEntry(level: .warning, message: "\\(msg) (JSONPathHint was: [\\(pathHintDebugString)])"))
        } else {
            GlobalAXLogger.shared.log(AXLogEntry(level: .warning, message: msg))
        }
        return (nil, msg)
    }
}

// MARK: - Core Search Logic

@MainActor
internal func navigateToElementByJSONPathHint(pathHint: [JSONPathHintComponent], initialSearchElement: Element) async -> Element? {
    var currentElementInPath = initialSearchElement
    let pathHintDesc = pathHint.map { component in "(attr:\\(component.attribute),val:\\(component.value),d:\\(component.depth ?? -1))" }.joined(separator: " -> ")
    GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: 
        "navigateToElementByJSONPathHint: Starting with \\(pathHint.count) JSON components [\\(pathHintDesc)] from " +
        "\\(initialSearchElement.briefDescription(option: .smart))"
    ))

    for (index, component) in pathHint.enumerated() {
        guard let componentCriteria = component.simpleCriteria else {
            GlobalAXLogger.shared.log(AXLogEntry(level: .warning, message: "navigateToElementByJSONPathHint: Skipping component #\\(index) (attr:\\(component.attribute)) due to invalid/unresolved attribute type. Path broken."))
            return nil
        }
        let depthForThisStep = component.depth ?? JSONPathHintComponent.defaultDepthForSegment
        GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: 
            "navigateToElementByJSONPathHint: Processing component #\\(index) {attr:\"\\(component.attribute)\", val:\"\\(component.value)\", depth:\\(depthForThisStep)} " +
            "starting from \\(currentElementInPath.briefDescription(option: .raw))."
        ))

        if let foundElementForThisStep = await findDescendantMatchingCriteria(
            startElement: currentElementInPath,
            criteria: componentCriteria,
            matchType: component.matchType ?? .exact,
            maxDepthForThisHintStep: depthForThisStep
        ) {
            GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "navigateToElementByJSONPathHint: Matched component #\\(index). Found: \\(foundElementForThisStep.briefDescription(option: .raw)). Advancing."))
            currentElementInPath = foundElementForThisStep
        } else {
            GlobalAXLogger.shared.log(AXLogEntry(level: .warning, message: "navigateToElementByJSONPathHint: Failed component #\\(index) {attr:\"\\(component.attribute)\", val:\"\\(component.value)\"} from \\(currentElementInPath.briefDescription(option: .raw)) depth \\(depthForThisStep). Path broken."))
            return nil
        }
    }
    GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "navigateToElementByJSONPathHint: Successfully navigated all \\(pathHint.count) JSON components. Final element: \\(currentElementInPath.briefDescription(option: .smart))"))
    return currentElementInPath
}

@MainActor
internal func findDescendantMatchingCriteria(startElement: Element, criteria: [String: String], matchType: JSONPathHintComponent.MatchType, maxDepthForThisHintStep: Int) async -> Element? {
    guard !criteria.isEmpty else {
        GlobalAXLogger.shared.log(AXLogEntry(level: .warning, message: "findDescendantMatchingCriteria: Called with empty criteria."))
        return nil
    }
    // Convert dictionary criteria to [Criterion]
    let criterionArray = criteria.map { key, value in
        Criterion(attribute: key, value: value, match_type: nil)
    }
    let tempLocator = Locator(criteria: criterionArray)
    return await traverseAndSearch(currentElement: startElement, locator: tempLocator, maxDepth: maxDepthForThisHintStep)
}

@MainActor
internal func traverseAndSearch(currentElement: Element, locator: Locator, maxDepth: Int) async -> Element? {
    if locator.criteria.isEmpty {
        GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "traverseAndSearch: Called with empty criteria. Returning current element: \\(currentElement.briefDescription(option: .smart))"))
        return currentElement 
    }

    let visitor = SearchVisitor(locator: locator)
    var traverser = TreeTraverser()
    var traversalState = TraversalState(maxDepth: maxDepth, startElement: currentElement)
    return await traverser.traverse(from: currentElement, visitor: visitor, state: &traversalState)
}

@MainActor
internal func processPathHintAndDetermineStartElement(application: Element, locator: Locator) async -> Element {
    guard let jsonPathComponents = locator.rootElementPathHint, !jsonPathComponents.isEmpty else {
        GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "processPathHint: No rootElementPathHint (JSON) provided or empty. Searching from app root."))
        return application
    }
    let pathHintDebug = jsonPathComponents.map { component in "(attr:\\(component.attribute),val:\\(component.value),d:\\(component.depth ?? -1))" }.joined(separator: " -> ")
    GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "processPathHint: Starting JSON path hint navigation [\\(pathHintDebug)] for search root. \\(jsonPathComponents.count) components."))
    if let elementFromPathHint = await navigateToElementByJSONPathHint(
        pathHint: jsonPathComponents,
        initialSearchElement: application
    ) {
        GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "processPathHint: JSON path hint navigation successful. New search start: \\(elementFromPathHint.briefDescription(option: .smart))."))
        return elementFromPathHint
    } else {
        GlobalAXLogger.shared.log(AXLogEntry(level: .warning, message: "processPathHint: JSON path hint navigation failed [\\(pathHintDebug)]. Full search will be from app root."))
        return application
    }
}

@MainActor
internal func findElementViaCriteriaAndJSONPathHint(
    application: Element,
    locator: Locator,
    maxDepth: Int
) async -> Element? {
    let pathHintForLog = locator.rootElementPathHint?.map { component in "(attr:\\(component.attribute),val:\\(component.value),d:\\(component.depth ?? -1))" }.joined(separator: " -> ") ?? "nil"
    GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: 
        "[findElementViaCriteriaAndJSONPathHint ENTRY] AppPID: \\(application.pid() ?? -1), Locator.criteria: \\(locator.criteria), " +
        "JSONPathHint: [\\(pathHintForLog)]"
    ))

    let searchStartElement = await processPathHintAndDetermineStartElement(application: application, locator: locator)
    if locator.criteria.isEmpty && (locator.rootElementPathHint != nil && !locator.rootElementPathHint!.isEmpty) {
        GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "[findElementViaCriteriaAndJSONPathHint] Criteria empty, JSON path hint used. Returning: \\(searchStartElement.briefDescription(option: .smart))"))
        return searchStartElement
    }
    GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "[findElementViaCriteriaAndJSONPathHint] Search start: \\(searchStartElement.briefDescription(option: .smart)). Applying criteria: \\(locator.criteria)"))
    return await traverseAndSearch(
        currentElement: searchStartElement,
        locator: locator,
        maxDepth: maxDepth
    )
}

// MARK: - Element Collection

@MainActor
internal func collectAllElements(
    from startElement: Element,
    matching locator: Locator, 
    appElementForContext: Element, 
    attributesToFetch: [String], 
    outputFormat: OutputFormat, 
    maxElements: Int?,
    maxSearchDepth: Int
) async -> [AXElementData] {
    let effectiveFilterCriteria = locator.criteria 

    let visitor = CollectAllVisitor(
        attributesToFetch: attributesToFetch,
        outputFormat: outputFormat,
        appElement: appElementForContext, 
        filterCriteria: effectiveFilterCriteria 
    )
    var traverser = TreeTraverser()
    var traversalState = TraversalState(maxDepth: maxSearchDepth, startElement: startElement)

    GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "CollectAll: Starting from \\(startElement.briefDescription(option: .smart)), FilterCriteria: \\(effectiveFilterCriteria), MaxDepth: \\(maxSearchDepth)"))
    
    _ = await traverser.traverse(from: startElement, visitor: visitor, state: &traversalState)
    
    GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "CollectAll: Visitor collected \\(visitor.collectedElements.count) AXElementData items."))
    
    if let maxEl = maxElements, visitor.collectedElements.count > maxEl {
        GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "CollectAll: Truncating to \\(maxEl) elements."))
        return Array(visitor.collectedElements.prefix(maxEl))
    }
    return visitor.collectedElements
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
    depth: Int
) async -> ElementMatchStatus {
    if await !elementMatchesCriteria(element, criteria: locator.criteria) {
        return .noMatch
    }

    if let actionName = actionToVerify, !actionName.isEmpty {
        if element.isActionSupported(actionName) {
            return .fullMatch
        } else {
            return .partialMatchActionMissing
        }
    }
    return .fullMatch
}

@MainActor
public func search(element: Element,
                   locator: Locator,
                   requireAction: String?,
                   depth: Int = 0,
                   maxDepth: Int = AXMiscConstants.defaultMaxDepthSearch
) async -> Element? {
    var traverser = TreeTraverser()
    let visitor = SearchVisitor(locator: locator, requireAction: requireAction)
    var state = TraversalState(maxDepth: maxDepth, startElement: element)
    let result = await traverser.traverse(from: element, visitor: visitor, state: &state)
    return result
}

@MainActor
/* public -> internal */ internal func collectAll(
    appElement: Element,
    locator: Locator,
    currentElement: Element,
    depth: Int,
    maxDepth: Int,
    maxElements: Int?,
    visitor: CollectAllVisitor
) async -> [AXElementData]? {
    var traverser = TreeTraverser()
    var state = TraversalState(maxDepth: maxDepth, startElement: currentElement)
    _ = await traverser.traverse(from: currentElement, visitor: visitor, state: &state)
    GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "collectAll: Traversal complete. Collected \\(visitor.collectedElements.count) elements."))
    return visitor.collectedElements
}

// Remaining functions in this file (like path navigation helpers if any outside findElementViaPathAndCriteria)
// would need similar review and refactoring if they use the old logging pattern.

// MARK: - Element Search Logic

// [REMOVED OLD findElement FUNCTION]

// MARK: - Path Navigator (Remains mostly the same, but uses TraversalContext for logging)

// [REMOVED OLD navigateToElementByPath FUNCTION]

// MARK: - Tree Traversal Utilities (SearchVisitor, TreeTraverser, TraversalState)
// SearchVisitor is now defined in TreeTraversal.swift to avoid duplication
