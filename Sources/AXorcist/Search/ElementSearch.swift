// ElementSearch.swift - Contains search and element collection logic

import ApplicationServices
import Foundation

// MARK: - Environment Variable & Global Constants

private func getEnvVar(_ name: String) -> String? {
    guard let value = getenv(name) else { return nil }
    return String(cString: value)
}

private let AXORC_JSON_LOG_ENABLED: Bool = {
    let envValue = getEnvVar("AXORC_JSON_LOG")?.lowercased()
    fputs("[ElementSearch.swift] AXORC_JSON_LOG env var value: \(envValue ?? "not set") -> JSON logging: \(envValue == "true")\n", stderr)
    return envValue == "true"
}()

// PathHintComponent and criteriaMatch are now in SearchCriteriaUtils.swift

// MARK: - Main Search Logic (findElementViaPathAndCriteria and its helpers)
@MainActor
func findElementViaPathAndCriteria(
    application: Element,
    locator: Locator,
    maxDepth: Int?,
    isDebugLoggingEnabledParam: Bool,
    currentDebugLogs: inout [String]
) -> Element? {
    var tempNilLogs: [String] = []

    // ADDED DEBUG LOGGING
    if isDebugLoggingEnabledParam {
        let pathHintDebug = locator.root_element_path_hint?.joined(separator: " -> ") ?? "nil"
        let initialMessage = "[findElementViaPathAndCriteria ENTRY] locator.criteria: \(locator.criteria), locator.root_element_path_hint: \(pathHintDebug)"
        currentDebugLogs.append(AXorcist.formatDebugLogMessage(initialMessage, applicationName: application.pid(isDebugLoggingEnabled: false, currentDebugLogs: &tempNilLogs).map { String($0) }, commandID: nil, file: #file, function: #function, line: #line))
    }
    // END ADDED DEBUG LOGGING

    func dLog(_ message: String, depth: Int? = nil, status: String? = nil, element: Element? = nil, c: [String: String]? = nil, md: Int? = nil) {
        if !AXORC_JSON_LOG_ENABLED && isDebugLoggingEnabledParam {
            var logMessage = message
            if let depth_ = depth, let status_ = status, let element_ = element {
                let role = element_.role(isDebugLoggingEnabled: false, currentDebugLogs: &tempNilLogs) ?? "nil"
                let title = element_.title(isDebugLoggingEnabled: false, currentDebugLogs: &tempNilLogs)?.truncated(to: 30) ?? "nil"
                let id = element_.identifier(isDebugLoggingEnabled: false, currentDebugLogs: &tempNilLogs)?.truncated(to: 30) ?? "nil"
                let criteriaDesc = c?.description.truncated(to: 50) ?? locator.criteria.description.truncated(to: 50)
                let maxDepthDesc = md ?? maxDepth ?? AXMiscConstants.defaultMaxDepthSearch
                logMessage = "search [D\(depth_)]: Path:\(element_.generatePathArray(upTo: application, isDebugLoggingEnabled: false, currentDebugLogs: &tempNilLogs).suffix(3).joined(separator: "/")), Status:\(status_), Elem:\(role) T:'\(title)' ID:'\(id)', Crit:\(criteriaDesc), MaxD:\(maxDepthDesc)"
            }
            let appPidString = application.pid(isDebugLoggingEnabled: false, currentDebugLogs: &tempNilLogs).map { String($0) }
            currentDebugLogs.append(AXorcist.formatDebugLogMessage(logMessage, applicationName: appPidString, commandID: nil, file: #file, function: #function, line: #line))
        }
    }

    func writeSearchLogEntry(depth: Int, element: Element?, criteriaForEntry: [String: String]?, maxDepthForEntry: Int, status: String, isMatch: Bool?) {
        if AXORC_JSON_LOG_ENABLED && isDebugLoggingEnabledParam {
            let role: String? = element?.role(isDebugLoggingEnabled: false, currentDebugLogs: &tempNilLogs)
            let title: String? = element?.title(isDebugLoggingEnabled: false, currentDebugLogs: &tempNilLogs)
            let identifier: String? = element?.identifier(isDebugLoggingEnabled: false, currentDebugLogs: &tempNilLogs)

            let entry = SearchLogEntry(
                d: depth,
                eR: role?.truncatedToMaxLogAbbrev(),
                eT: title?.truncatedToMaxLogAbbrev(),
                eI: identifier?.truncatedToMaxLogAbbrev(),
                mD: maxDepthForEntry,
                c: criteriaForEntry?.mapValues { $0.truncatedToMaxLogAbbrev() } ?? locator.criteria.mapValues { $0.truncatedToMaxLogAbbrev() },
                s: status,
                iM: isMatch
            )
            if let jsonData = try? JSONEncoder().encode(entry), let jsonString = String(data: jsonData, encoding: .utf8) {
                fputs("\(jsonString)\n", stderr)
            }
        }
    }

    @MainActor
    func navigateToElementByPathHint(pathHint: [PathHintComponent], initialSearchElement: Element, pathHintMaxDepth: Int) -> Element? {
        var currentElementInPath = initialSearchElement
        dLog("PathHintNav: Starting with \(pathHint.count) components from \(initialSearchElement.briefDescription(option: .default, isDebugLoggingEnabled: false, currentDebugLogs: &tempNilLogs))")

        for (index, pathComponent) in pathHint.enumerated() {
            let currentNavigationDepth = index
            dLog("PathHintNav: Visiting comp #\(index)", depth: currentNavigationDepth, status: "pathVis", element: currentElementInPath, c: pathComponent.criteria, md: pathHintMaxDepth)
            writeSearchLogEntry(depth: currentNavigationDepth, element: currentElementInPath, criteriaForEntry: pathComponent.criteria, maxDepthForEntry: pathHintMaxDepth, status: "pathVis", isMatch: nil)

            if !pathComponent.matches(element: currentElementInPath, isDebugLoggingEnabled: isDebugLoggingEnabledParam, axorcJsonLogEnabled: AXORC_JSON_LOG_ENABLED, currentDebugLogs: &currentDebugLogs) {
                dLog("PathHintNav: No match for comp #\(index)", depth: currentNavigationDepth, status: "pathNoMatch", element: currentElementInPath, c: pathComponent.criteria, md: pathHintMaxDepth)
                writeSearchLogEntry(depth: currentNavigationDepth, element: currentElementInPath, criteriaForEntry: pathComponent.criteria, maxDepthForEntry: pathHintMaxDepth, status: "pathNoMatch", isMatch: false)
                return nil
            }

            dLog("PathHintNav: Matched comp #\(index)", depth: currentNavigationDepth, status: "pathMatch", element: currentElementInPath, c: pathComponent.criteria, md: pathHintMaxDepth)
            writeSearchLogEntry(depth: currentNavigationDepth, element: currentElementInPath, criteriaForEntry: pathComponent.criteria, maxDepthForEntry: pathHintMaxDepth, status: "pathMatch", isMatch: true)

            if index == pathHint.count - 1 {
                return currentElementInPath
            }

            let nextPathComponentCriteria = pathHint[index + 1].criteria
            var foundNextChild: Element?
            if let children = currentElementInPath.children(isDebugLoggingEnabled: isDebugLoggingEnabledParam, currentDebugLogs: &currentDebugLogs) {
                for child in children {
                    let tempPathComponent = PathHintComponent(criteria: nextPathComponentCriteria)
                    if tempPathComponent.matches(element: child, isDebugLoggingEnabled: isDebugLoggingEnabledParam, axorcJsonLogEnabled: AXORC_JSON_LOG_ENABLED, currentDebugLogs: &currentDebugLogs) {
                        currentElementInPath = child
                        foundNextChild = child
                        break
                    }
                }
            }

            if foundNextChild == nil {
                dLog("PathHintNav: Could not find child for next comp #\(index + 1)", depth: currentNavigationDepth, status: "pathChildFail", element: currentElementInPath, c: nextPathComponentCriteria, md: pathHintMaxDepth)
                writeSearchLogEntry(depth: currentNavigationDepth, element: currentElementInPath, criteriaForEntry: nextPathComponentCriteria, maxDepthForEntry: pathHintMaxDepth, status: "pathChildFail", isMatch: false)
                return nil
            }
        }
        return currentElementInPath
    }

    // Unified search using TreeTraverser
    var traverser = TreeTraverser()
    @MainActor
    func traverseAndSearch(currentElement: Element, currentDepth: Int, effectiveMaxDepth: Int) -> Element? {
        let visitor = SearchVisitor(locator: locator)
        var context = TraversalContext(
            maxDepth: effectiveMaxDepth,
            isDebugLoggingEnabled: isDebugLoggingEnabledParam,
            currentDebugLogs: currentDebugLogs,
            startElement: currentElement
        )
        
        let result = traverser.traverse(from: currentElement, visitor: visitor, context: &context)
        currentDebugLogs = context.currentDebugLogs
        return result
    }

    var searchStartElement = application
    let resolvedMaxDepth = maxDepth ?? AXMiscConstants.defaultMaxDepthSearch

    if let pathHintStrings = locator.root_element_path_hint, !pathHintStrings.isEmpty {
        let pathHintComponents = pathHintStrings.compactMap { PathHintComponent(pathSegment: $0, isDebugLoggingEnabled: isDebugLoggingEnabledParam, axorcJsonLogEnabled: AXORC_JSON_LOG_ENABLED, currentDebugLogs: &currentDebugLogs) }
        if !pathHintComponents.isEmpty && pathHintComponents.count == pathHintStrings.count {
            dLog("Starting path hint navigation. Number of components: \(pathHintComponents.count)")
            if let elementFromPathHint = navigateToElementByPathHint(pathHint: pathHintComponents, initialSearchElement: application, pathHintMaxDepth: pathHintComponents.count - 1) {
                dLog("Path hint navigation successful. New start: \(elementFromPathHint.briefDescription(option: .default, isDebugLoggingEnabled: false, currentDebugLogs: &tempNilLogs)). Starting criteria search.")
                searchStartElement = elementFromPathHint
            } else {
                dLog("Path hint navigation failed. Full search from app root.")
            }
        } else {
            dLog("Path hint strings provided but failed to parse into components or some were invalid. Full search from app root.")
        }
    } else {
        dLog("No path hint provided. Searching from application root.")
    }

    return traverseAndSearch(currentElement: searchStartElement, currentDepth: 0, effectiveMaxDepth: resolvedMaxDepth)
}

enum ElementMatchStatus {
    case fullMatch
    case partialMatch_actionMissing
    case noMatch
}

@MainActor
internal func evaluateElementAgainstCriteria(
    element: Element,
    locator: Locator,
    actionToVerify: String?,
    depth: Int,
    isDebugLoggingEnabled: Bool,
    currentDebugLogs: inout [String]
) -> ElementMatchStatus {
    var tempContext = TraversalContext(maxDepth: 0, isDebugLoggingEnabled: isDebugLoggingEnabled, currentDebugLogs: currentDebugLogs, startElement: element) // Create a context for logging

    // Initial check for path hint if provided
    if let pathHint = locator.root_element_path_hint, !pathHint.isEmpty {
        // This check is complex, as it implies the current `element` should be at the END of this path hint from the appElement.
        // For now, we assume that if a path hint was given, `navigateToElementByPath` would have been called prior,
        // and `element` is already the result of that. So, we don't re-verify the full path here.
        // However, if the path_hint_match_required flag is true, this might need more rigorous checking.
        // This could be a point of future enhancement.
    }

    // Check criteria using the global criteriaMatch function
    if !criteriaMatch(element: element, criteria: locator.criteria, isDebugLoggingEnabled: isDebugLoggingEnabled, axorcJsonLogEnabled: false /* Assuming false, or pass actual value */, currentDebugLogs: &tempContext.currentDebugLogs) {
        currentDebugLogs.append(contentsOf: tempContext.currentDebugLogs)
        return .noMatch 
    }
    
    // Check for required action if specified - changed to isActionSupported
    if let actionName = actionToVerify, !actionName.isEmpty {
        if !element.isActionSupported(actionName, isDebugLoggingEnabled: isDebugLoggingEnabled, currentDebugLogs: &tempContext.currentDebugLogs) {
            dLog("Element \(element.briefDescriptionForDebug(context: &tempContext)) matches criteria but is missing required action '\(actionName)'.", context: &tempContext)
            currentDebugLogs.append(contentsOf: tempContext.currentDebugLogs)
            return .noMatch // Or a specific status like .partialMatch_actionMissing if defined
        }
        dLog("Element \(element.briefDescriptionForDebug(context: &tempContext)) matches criteria AND has required action '\(actionName)'.", context: &tempContext)
    } else {
        dLog("Element \(element.briefDescriptionForDebug(context: &tempContext)) matches criteria. No specific action required by this check.", context: &tempContext)
    }
    
    currentDebugLogs.append(contentsOf: tempContext.currentDebugLogs)
    return .fullMatch // Assuming .fullMatch is the success status
}

@MainActor
public func search(element: Element,
                   locator: Locator,
                   requireAction: String?,
                   depth: Int = 0,
                   maxDepth: Int = AXMiscConstants.defaultMaxDepthSearch,
                   isDebugLoggingEnabled: Bool,
                   currentDebugLogs: inout [String]) -> Element? {
    if depth > maxDepth { return nil }

    var traverser = TreeTraverser()
    let visitor = SearchVisitor(locator: locator, requireAction: requireAction)
    var context = TraversalContext(
        maxDepth: maxDepth,
        isDebugLoggingEnabled: isDebugLoggingEnabled,
        currentDebugLogs: currentDebugLogs,
        startElement: element
    )
    
    let result = traverser.traverse(from: element, visitor: visitor, context: &context)
    currentDebugLogs = context.currentDebugLogs
    return result
}

// Simplified search function for specific use cases
@MainActor
public func searchWithCycleDetection(element: Element,
                                   locator: Locator,
                                   requireAction: String?,
                                   depth: Int = 0,
                                   maxDepth: Int = AXMiscConstants.defaultMaxDepthSearch,
                                   isDebugLoggingEnabled: Bool,
                                   currentDebugLogs: inout [String],
                                   visitedElements: inout Set<Element>) -> Element? {
    // This function is now redundant as the unified traverser handles cycle detection
    return search(element: element, locator: locator, requireAction: requireAction, 
                  depth: depth, maxDepth: maxDepth, isDebugLoggingEnabled: isDebugLoggingEnabled, 
                  currentDebugLogs: &currentDebugLogs)
}

@MainActor
public func collectAll(
    appElement: Element,
    locator: Locator,
    currentElement: Element,
    depth: Int,
    maxDepth: Int,
    maxElements: Int,
    currentPath: [Element],
    elementsBeingProcessed: inout Set<Element>,
    foundElements: inout [Element],
    isDebugLoggingEnabled: Bool,
    currentDebugLogs: inout [String]
) {
    var tempLogs: [String] = []
    if elementsBeingProcessed.contains(currentElement) || currentPath.contains(currentElement) { return }
    elementsBeingProcessed.insert(currentElement)

    if foundElements.count >= maxElements || depth > maxDepth {
        elementsBeingProcessed.remove(currentElement)
        return
    }

    let matchStatus = evaluateElementAgainstCriteria(element: currentElement,
                                                     locator: locator,
                                                     actionToVerify: locator.requireAction,
                                                     depth: depth,
                                                     isDebugLoggingEnabled: isDebugLoggingEnabled,
                                                     currentDebugLogs: &currentDebugLogs)

    if matchStatus == .fullMatch {
        if !foundElements.contains(currentElement) {
            foundElements.append(currentElement)
        }
    }

    let childrenToExplore: [Element] = currentElement.children(isDebugLoggingEnabled: isDebugLoggingEnabled, currentDebugLogs: &tempLogs) ?? []
    elementsBeingProcessed.remove(currentElement)

    let newPath = currentPath + [currentElement]
    for child in childrenToExplore {
        if foundElements.count >= maxElements { break }
        collectAll(
            appElement: appElement,
            locator: locator,
            currentElement: child,
            depth: depth + 1,
            maxDepth: maxDepth,
            maxElements: maxElements,
            currentPath: newPath,
            elementsBeingProcessed: &elementsBeingProcessed,
            foundElements: &foundElements,
            isDebugLoggingEnabled: isDebugLoggingEnabled,
            currentDebugLogs: &currentDebugLogs
        )
    }
}

// Notes for compilation:
// 1. ValueUnwrapper.unwrap should be available.
// 2. AXorcist.formatDebugLogMessage should be available.
// 3. Element struct and its methods must be correctly defined.
// 4. Locator struct must be defined with `criteria: [String: String]`, `root_element_path_hint: [String]?`, and `requireAction: String?`.
// 5. AXAttributeNames.kAXRoleAttribute should be a defined constant (String).
// 6. ValueFormatOption enum (with .default, .short cases) must be available for Element.briefDescription.
// 7. SearchLogEntry struct is now in Models.swift

// MARK: - Element Search Logic

@MainActor
func findElement(
    appElement: Element,
    locator: Locator,
    requireAction: String? = nil, // Optional action to verify
    isDebugLoggingEnabled: Bool,
    currentDebugLogs: inout [String],
    customStartElement: Element? = nil, // Optional start element for search
    maxDepth: Int? = nil // Optional max depth for this specific search call
) -> Element? {
    let searchStartElement = customStartElement ?? appElement
    let effectiveMaxDepth = maxDepth ?? AXMiscConstants.defaultMaxDepthSearch
    
    var traverser = TreeTraverser()
    let visitor = SearchVisitor(locator: locator, requireAction: requireAction)
    var context = TraversalContext(
        maxDepth: effectiveMaxDepth,
        isDebugLoggingEnabled: isDebugLoggingEnabled,
        currentDebugLogs: currentDebugLogs,
        startElement: searchStartElement
    )
    
    dLog("Starting unified element search. Start: \(searchStartElement.briefDescriptionForDebug(context: &context)), MaxDepth: \(effectiveMaxDepth), Locator: \(locator)", context: &context)
    
    let foundElement = traverser.traverse(from: searchStartElement, visitor: visitor, context: &context)
    currentDebugLogs = context.currentDebugLogs // Retrieve updated logs
    
    if let found = foundElement {
        dLog("Unified search found element: \(found.briefDescriptionForDebug(context: &context))", context: &context)
    } else {
        dLog("Unified search did not find any matching element.", context: &context)
    }
    return foundElement
}

// MARK: - Path Navigator (Remains mostly the same, but uses TraversalContext for logging)

// Assuming PathElementHint was intended to be a simple String for each segment of a path.
// If it was a more complex struct, its definition needs to be found or recreated.
public typealias PathElementHint = String // Placeholder definition

@MainActor
func navigateToElementByPath(
    rootElement: Element,
    path: [PathElementHint], // Now an array of Strings
    isDebugLoggingEnabled: Bool,
    currentDebugLogs: inout [String]
) -> Element? {
    var currentElement = rootElement
    var pathTraversalLogs: [String] = []
    
    var tempContext = TraversalContext(maxDepth: 0, isDebugLoggingEnabled: isDebugLoggingEnabled, currentDebugLogs: currentDebugLogs, startElement: rootElement)

    dLog("Starting path navigation from root: \(rootElement.briefDescriptionForDebug(context: &tempContext))", context: &tempContext)
    pathTraversalLogs.append(contentsOf: tempContext.currentDebugLogs)
    tempContext.currentDebugLogs.removeAll() 

    for (index, pathSegment) in path.enumerated() { // pathSegment is now a String
        // The logic for matching pathSegment (String) to a child needs to be defined.
        // This simplistic approach tries to match the pathSegment against common attributes.
        // This is a significant simplification and likely needs to be more robust based on
        // how PathElementHint was originally structured and used.
        
        dLog("Path step [\(index + 1)/\(path.count)]: Target '\(pathSegment)'", context: &tempContext)
        pathTraversalLogs.append(contentsOf: tempContext.currentDebugLogs)
        tempContext.currentDebugLogs.removeAll()

        guard let children = currentElement.children(isDebugLoggingEnabled: isDebugLoggingEnabled, currentDebugLogs: &tempContext.currentDebugLogs) else {
            dLog("Failed to get children for \(currentElement.briefDescriptionForDebug(context: &tempContext)) at path step \(index + 1)", context: &tempContext)
            pathTraversalLogs.append(contentsOf: tempContext.currentDebugLogs)
            currentDebugLogs.append(contentsOf: pathTraversalLogs)
            return nil
        }
        pathTraversalLogs.append(contentsOf: tempContext.currentDebugLogs)
        tempContext.currentDebugLogs.removeAll()

        var matchedChild: Element? = nil
        var childSearchDebugLogs: [String] = []

        // Attempt to match pathSegment against title, role, or identifier of children
        for child in children {
            var matched = false
            if let title = child.title(isDebugLoggingEnabled: isDebugLoggingEnabled, currentDebugLogs: &childSearchDebugLogs), title == pathSegment {
                matched = true
            } else if let role = child.role(isDebugLoggingEnabled: isDebugLoggingEnabled, currentDebugLogs: &childSearchDebugLogs), role == pathSegment {
                matched = true
            } else if let identifier = child.identifier(isDebugLoggingEnabled: isDebugLoggingEnabled, currentDebugLogs: &childSearchDebugLogs), identifier == pathSegment {
                matched = true
            }
            
            if matched {
                matchedChild = child
                dLog("Matched child by attribute for segment '\(pathSegment)': \(child.briefDescriptionForDebug(context: &tempContext))", context: &tempContext)
                childSearchDebugLogs.append(contentsOf: tempContext.currentDebugLogs); tempContext.currentDebugLogs.removeAll()
                break
            }
        }
        
        pathTraversalLogs.append(contentsOf: childSearchDebugLogs)

        if let foundChild = matchedChild {
            currentElement = foundChild
            dLog("Advanced to: \(currentElement.briefDescriptionForDebug(context: &tempContext))", context: &tempContext)
            pathTraversalLogs.append(contentsOf: tempContext.currentDebugLogs); tempContext.currentDebugLogs.removeAll()
        } else {
            dLog("Failed to match path segment '\(pathSegment)' at this level. Current parent: \(currentElement.briefDescriptionForDebug(context: &tempContext))", context: &tempContext)
            pathTraversalLogs.append(contentsOf: tempContext.currentDebugLogs); tempContext.currentDebugLogs.removeAll()
            currentDebugLogs.append(contentsOf: pathTraversalLogs)
            return nil
        }
    }

    dLog("Path navigation successful. Final element: \(currentElement.briefDescriptionForDebug(context: &tempContext))", context: &tempContext)
    pathTraversalLogs.append(contentsOf: tempContext.currentDebugLogs)
    currentDebugLogs.append(contentsOf: pathTraversalLogs)
    return currentElement
}
