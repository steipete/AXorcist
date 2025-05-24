// AXorcist+QueryHandlers.swift - Query and search operation handlers

import AppKit
import ApplicationServices
import Foundation
// GlobalAXLogger is assumed to be available

// Define arrow separator constant for joining path hints
private let arrowSeparator = " -> "

// MARK: - Query & Search Handlers Extension
extension AXorcist {

    // MARK: - handleQuery

    @MainActor
    public func handleQuery(
        for appIdentifierOrNil: String?,
        locator: Locator,
        pathHint: [String]?,
        maxDepth: Int?,
        requestedAttributes: [String]?,
        outputFormat: OutputFormat?
    ) async -> HandlerResponse {
        SearchVisitor.resetGlobalVisitCount()

        let appIdentifier = appIdentifierOrNil ?? self.focusedAppKeyValue
        axDebugLog("Handling query for app: \(appIdentifier)",
                   file: #file,
                   function: #function,
                   line: #line
        )

        // Get the application element
        guard let appElement = applicationElement(for: appIdentifier) else {
            axErrorLog("Application not found: \(appIdentifier)",
                       file: #file,
                       function: #function,
                       line: #line
            )
            return HandlerResponse(
                data: nil,
                error: "Application not found: \(appIdentifier)"
            )
        }

        // Navigate using path hint if provided
        let effectiveElementResult = navigateWithPathHintIfNeeded(
            appElement: appElement,
            pathHint: pathHint
        )

        guard let effectiveElement = effectiveElementResult.element else {
            return HandlerResponse(
                data: nil,
                error: effectiveElementResult.error ?? "Failed to navigate with path hint"
            )
        }

        // Find the target element based on the locator
        let foundElementResult = findElementWithLocator(
            locator: locator,
            effectiveElement: effectiveElement,
            appElement: appElement,
            maxDepth: maxDepth
        )

        guard let foundElement = foundElementResult.element else {
            return HandlerResponse(
                data: nil,
                error: foundElementResult.error ?? "Element not found"
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

    // Helper: Navigate with path hint if provided
    @MainActor
    private func navigateWithPathHintIfNeeded(
        appElement: Element,
        pathHint: [String]?
    ) -> (element: Element?, error: String?) {
        var effectiveElement = appElement

        if let pathHint = pathHint, !pathHint.isEmpty {
            let pathHintString = pathHint.joined(separator: arrowSeparator)
            axDebugLog("Navigating with path_hint: \(pathHintString)",
                       file: #file,
                       function: #function,
                       line: #line
            )

            if let navigatedElement = navigateToElement(
                from: effectiveElement,
                pathHint: pathHint,
                maxDepth: AXMiscConstants.defaultMaxDepthSearch
            ) {
                effectiveElement = navigatedElement
            } else {
                let errorMsg = "Element not found via path hint: \(pathHintString)"
                axErrorLog(errorMsg,
                           file: #file,
                           function: #function,
                           line: #line
                )
                return (nil, errorMsg)
            }
        }

        return (effectiveElement, nil)
    }

    // Helper: Find element with locator
    @MainActor
    private func findElementWithLocator(
        locator: Locator,
        effectiveElement: Element,
        appElement: Element,
        maxDepth: Int?
    ) -> (element: Element?, error: String?) {
        let appSpecifiers = ["application", "bundle_id", "pid", "path"]
        let criteriaKeys = locator.criteria.keys
        let isAppOnlyLocator = criteriaKeys.allSatisfy { appSpecifiers.contains($0) } && criteriaKeys.count == 1

        if isAppOnlyLocator {
            axDebugLog("Locator is app-only (criteria: \(locator.criteria)). Using appElement directly.",
                       file: #file,
                       function: #function,
                       line: #line
            )
            return (effectiveElement, nil)
        }

        // Find search start element based on rootElementPathHint
        let searchStartResult = findSearchStartElement(
            locator: locator,
            effectiveElement: effectiveElement,
            appElement: appElement
        )

        guard let searchStartElement = searchStartResult.element else {
            return (nil, searchStartResult.error)
        }

        // Perform the search
        let searchResult = self.search(
            element: searchStartElement,
            locator: locator,
            requireAction: locator.requireAction,
            depth: 0,
            maxDepth: maxDepth ?? AXMiscConstants.defaultMaxDepthSearch
        )

        if searchResult == nil {
            axWarningLog("No element matches single query criteria with locator or app-only locator failed to resolve.",
                         file: #file,
                         function: #function,
                         line: #line
            )
            return (nil, "No element matches single query criteria with locator or app-only locator failed to resolve.")
        }

        return (searchResult, nil)
    }

    // Helper: Find search start element
    @MainActor
    private func findSearchStartElement(
        locator: Locator,
        effectiveElement: Element,
        appElement: Element
    ) -> (element: Element?, error: String?) {
        axDebugLog("Locator contains element-specific criteria or is complex. Proceeding with search.",
                   file: #file,
                   function: #function,
                   line: #line
        )

        var searchStartElement = effectiveElement

        if let rootPathHint = locator.rootElementPathHint, !rootPathHint.isEmpty {
            axDebugLog("Locator has rootElementPathHint: \(rootPathHint.joined(separator: " -> ")). Navigating from app element first.",
                       file: #file,
                       function: #function,
                       line: #line
            )

            guard let containerElement = navigateToElement(
                from: appElement,
                pathHint: rootPathHint,
                maxDepth: AXMiscConstants.defaultMaxDepthSearch
            ) else {
                let errorMsg = "Container for locator not found via rootElementPathHint: \(rootPathHint.joined(separator: " -> "))"
                axErrorLog(errorMsg,
                           file: #file,
                           function: #function,
                           line: #line
                )
                return (nil, errorMsg)
            }

            searchStartElement = containerElement
            axDebugLog(
                "Searching with locator within container found by root_element_path_hint: " +
                    "\(searchStartElement.briefDescription(option: .default))",
                file: #file,
                function: #function,
                line: #line
            )
        } else {
            axDebugLog(
                "Searching with locator from element (determined by main path_hint or app root): " +
                    "\(searchStartElement.briefDescription(option: .default))",
                file: #file,
                function: #function,
                line: #line
            )
        }

        return (searchStartElement, nil)
    }

    // Helper: Build query response
    @MainActor
    private func buildQueryResponse(
        element: Element,
        appElement: Element,
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
        pathHint: [String]?,
        maxDepth: Int?,
        outputFormat: OutputFormat?
    ) async -> HandlerResponse {
        SearchVisitor.resetGlobalVisitCount()

        let appIdentifier = appIdentifierOrNil ?? self.focusedAppKeyValue
        axDebugLog("Handling get_attributes command for app: \(appIdentifier)",
                   file: #file,
                   function: #function,
                   line: #line
        )

        let targetElementResult = await self.findTargetElement(
            for: appIdentifier,
            locator: locator,
            pathHint: pathHint,
            maxDepthForSearch: maxDepth ?? AXMiscConstants.defaultMaxDepthSearch
        )

        let foundElement: Element
        switch targetElementResult {
        case .failure(let errorData):
            axErrorLog("Failed to find target element in handleGetAttributes: \(errorData.message)",
                       file: #file,
                       function: #function,
                       line: #line
            )
            return HandlerResponse(data: nil, error: errorData.message)
        case .success(let element):
            foundElement = element
        }

        let attributesDescription = (requestedAttributes ?? ["all"]).joined(separator: ", ")
        let logMessage = "handleGetAttributes: Element found: \(foundElement.briefDescription(option: .default))."
        axDebugLog(logMessage, details: ["requestedAttributes": attributesDescription], file: #file, function: #function, line: #line)

        let elementToQuery = foundElement
        let (attributes, _) = getElementAttributes(
            element: elementToQuery,
            attributes: requestedAttributes ?? [],
            outputFormat: outputFormat ?? .smart
        )
        // Removed: if outputFormat == .json_string { attributes = encodeAttributesToJSONStringRepresentation(attributes) }
        axDebugLog("Successfully fetched attributes for element \(elementToQuery.briefDescription(option: .default)).",
                   file: #file,
                   function: #function,
                   line: #line
        )

        let axElement = AXElement(attributes: attributes, path: elementToQuery.generatePathArray()) // Assuming generatePathArray without arg is fine or adjust
        return HandlerResponse(data: AnyCodable(axElement), error: nil)
    }

    @MainActor
    public func handleDescribeElement(
        for appIdentifierOrNil: String?,
        locator: Locator,
        pathHint: [String]?,
        maxDepth: Int?,
        requestedAttributes: [String]?,
        outputFormat: OutputFormat?
    ) async -> HandlerResponse {
        SearchVisitor.resetGlobalVisitCount()

        let appIdentifier = appIdentifierOrNil ?? self.focusedAppKeyValue
        axDebugLog("Handling describe_element for app: \(appIdentifier)",
                   file: #file,
                   function: #function,
                   line: #line
        )

        let searchMaxDepth = AXMiscConstants.defaultMaxDepthSearch

        let targetElementResult = await self.findTargetElement(
            for: appIdentifier,
            locator: locator,
            pathHint: pathHint,
            maxDepthForSearch: searchMaxDepth
        )

        let elementToDescribe: Element
        switch targetElementResult {
        case .failure(let errorData):
            axErrorLog("Failed to find target element in handleDescribeElement: \(errorData.message)",
                       file: #file,
                       function: #function,
                       line: #line
            )
            return HandlerResponse(data: nil, error: errorData.message)
        case .success(let element):
            elementToDescribe = element
        }

        axDebugLog("Element to describe found: \(elementToDescribe.briefDescription(option: .default)). Building tree...",
                   file: #file,
                   function: #function,
                   line: #line
        )

        let treeElement = await buildElementTree(
            from: elementToDescribe,
            depth: 0,
            maxDepth: maxDepth ?? AXMiscConstants.defaultMaxDepthDescribe,
            requestedAttributes: requestedAttributes ?? AXorcist.defaultAttributesToFetch,
            includeActions: true,
            outputFormat: outputFormat ?? .smart
        )

        return HandlerResponse(data: AnyCodable(treeElement), error: nil)
    }

    // MARK: - fetchElementTree (Core tree building logic for CollectAll and DescribeElement)
    @MainActor
    public func fetchElementTree(
        for appIdentifierOrNil: String?,
        targeting elementRef: AXUIElement?,
        locator: Locator?,
        pathHint: [String]?,
        maxDepth: Int?,
        requestedAttributes: [String]?,
        includeActions: Bool,
        outputFormat: OutputFormat?
    ) async -> HandlerResponse {
        SearchVisitor.resetGlobalVisitCount()

        let appIdentifier = appIdentifierOrNil ?? self.focusedAppKeyValue
        axDebugLog("Fetching element tree for app: \(appIdentifier)",
                   file: #file,
                   function: #function,
                   line: #line
        )

        var rootElementForTreeBuild: Element?

        if let ref = elementRef {
            axDebugLog("Using provided AXUIElement ref as root for tree build.",
                       file: #file,
                       function: #function,
                       line: #line
            )
            rootElementForTreeBuild = Element(ref)
        } else {
            guard let appElement = applicationElement(for: appIdentifier) else {
                axErrorLog("Application element not found for \(appIdentifier) in fetchElementTree",
                           file: #file,
                           function: #function,
                           line: #line
                )
                return HandlerResponse(data: nil, error: "Application not found: \(appIdentifier)")
            }

            if let loc = locator {
                let findResult = await findTargetElement(for: appIdentifier, locator: loc, pathHint: pathHint, maxDepthForSearch: AXMiscConstants.defaultMaxDepthSearch)
                switch findResult {
                case .success(let foundEl):
                    rootElementForTreeBuild = foundEl
                case .failure(let err):
                    axErrorLog("Failed to find element with locator for tree root: \(err.message)",
                               file: #file,
                               function: #function,
                               line: #line
                    )
                    return HandlerResponse(data: nil, error: "Element for tree root not found with locator: \(err.message)")
                }
            } else if let hint = pathHint, !hint.isEmpty {
                if let navigated = navigateToElement(from: appElement, pathHint: hint, maxDepth: AXMiscConstants.defaultMaxDepthSearch) {
                    rootElementForTreeBuild = navigated
                } else {
                    let errorMsg = "Element for tree root not found via path hint: \(hint.joined(separator: " -> "))"
                    axErrorLog(errorMsg,
                               file: #file,
                               function: #function,
                               line: #line
                    )
                    return HandlerResponse(data: nil, error: errorMsg)
                }
            } else {
                rootElementForTreeBuild = appElement // Default to app element if no locator or pathHint for specific root
            }
        }

        guard let finalRootElement = rootElementForTreeBuild else {
            axErrorLog("Could not determine a root element for tree building.",
                       file: #file,
                       function: #function,
                       line: #line
            )
            return HandlerResponse(data: nil, error: "Could not determine root element for tree.")
        }

        axDebugLog("Final root for tree build: \(finalRootElement.briefDescription(option: .default)). Building tree...",
                   file: #file,
                   function: #function,
                   line: #line
        )

        let treeElement = await buildElementTree(
            from: finalRootElement,
            depth: 0,
            maxDepth: maxDepth ?? AXMiscConstants.defaultMaxDepthDescribe,
            requestedAttributes: requestedAttributes ?? AXorcist.defaultAttributesToFetch,
            includeActions: includeActions,
            outputFormat: outputFormat ?? .smart
        )

        return HandlerResponse(data: AnyCodable(treeElement), error: nil)
    }

    // MARK: - Internal Helper: buildElementTree
    @MainActor
    private func buildElementTree(
        from element: Element,
        depth: Int,
        maxDepth: Int,
        requestedAttributes: [String],
        includeActions: Bool,
        outputFormat: OutputFormat
    ) async -> AXElement {
        // Removed: SearchVisitor.incrementVisitCount()
        axDebugLog("buildElementTree: Visiting \(element.briefDescription(option: .short)), Depth: \(depth)/\(maxDepth)", file: #file, function: #function, line: #line)

        let (currentElementAttributes, _) = getElementFullDescription(
            element: element,
            valueFormatOption: .default, // Or make configurable
            includeActions: includeActions,
            includeStoredAttributes: true // Usually true for a full description
        )

        var processedAttributes = currentElementAttributes
        // Removed: if outputFormat == .json_string { processedAttributes = encodeAttributesToJSONStringRepresentation(processedAttributes) }

        var childrenAXElements: [AXElement]? // Initialize as nil

        if depth < maxDepth {
            // Removed: if SearchVisitor.globalVisitCount > AXMiscConstants.maxTotalElementsVisitLimit logic

            if let childElements = element.children() { // Element.children() returns [Element]?
                childrenAXElements = [] // Initialize array if there are children
                for childElement in childElements {
                    // Removed: if SearchVisitor.globalVisitCount > AXMiscConstants.maxTotalElementsVisitLimit check before recursive call
                    let childAXElement = await buildElementTree(
                        from: childElement,
                        depth: depth + 1,
                        maxDepth: maxDepth,
                        requestedAttributes: requestedAttributes,
                        includeActions: includeActions,
                        outputFormat: outputFormat
                    )
                    childrenAXElements!.append(childAXElement)
                }
            }
        } else {
            if depth >= maxDepth {
                axDebugLog("Max depth (\(maxDepth)) reached for element \(element.briefDescription(option: .short)). Not recursing further.",
                           file: #file,
                           function: #function,
                           line: #line
                )
                processedAttributes["WARNING_recursion_stopped_max_depth"] = AnyCodable("Max depth reached.")
            }
        }

        // Store children directly in the AXElement attributes if they exist
        if let children = childrenAXElements, !children.isEmpty {
            processedAttributes["ComputedChildren"] = AnyCodable(children)
        }

        return AXElement(
            attributes: processedAttributes,
            path: element.generatePathArray()
        )
    }

    // MARK: - Attribute Fetching Logic (Internal)

    /// Internal helper to fetch and format attributes for a given element.
    /// This is distinct from the global `getElementAttributes` in `AttributeHelpers.swift`.
    @MainActor
    internal func fetchAndFormatElementAttributes( // Renamed from getElementAttributes
        element: Element,
        requestedAttributes: [String]?,
        outputFormat: OutputFormat,
        valueFormatOption: ValueFormatOption
    ) -> ([String: AnyCodable], [AXLogEntry]) {

        let attributesToFetch = requestedAttributes ?? []

        let (attributes, _) = getElementAttributes(
            element: element,
            attributes: attributesToFetch,
            outputFormat: outputFormat,
            valueFormatOption: valueFormatOption
        )

        return (attributes, [])
    }

    // MARK: - Internal Helper: navigateToElement
    @MainActor
    internal func navigateToElement(
        from startElement: Element,
        pathHint: [String],
        maxDepth: Int
    ) -> Element? {
        let pathHintString = pathHint.joined(separator: arrowSeparator)
        let logMessage = "Navigating from \(startElement.briefDescription(option: .default)) with path hint: \(pathHintString)"
        axDebugLog(logMessage,
                   file: #file,
                   function: #function,
                   line: #line
        )

        var currentElement = startElement
        var currentDepth = 0

        for (index, hintSegment) in pathHint.enumerated() {
            if currentDepth >= maxDepth {
                axWarningLog("Navigation max depth (\(maxDepth)) reached at segment '\(hintSegment)'. Stopping.",
                             file: #file,
                             function: #function,
                             line: #line
                )
                return nil
            }

            // Process the hint segment
            let segmentResult = processHintSegment(
                hintSegment: hintSegment,
                currentElement: currentElement,
                pathHint: pathHint,
                currentIndex: index
            )

            if let foundChild = segmentResult {
                currentElement = foundChild
                currentDepth += 1
            } else {
                return nil
            }
        }

        let finalPathHintString = pathHint.joined(separator: arrowSeparator)
        let infoMessage = "Successfully navigated path hint: \(finalPathHintString). Final element: \(currentElement.briefDescription(option: .default))"
        axInfoLog(infoMessage, file: #file, function: #function, line: #line)
        return currentElement
    }

    // Helper: Process a single hint segment
    @MainActor
    private func processHintSegment(
        hintSegment: String,
        currentElement: Element,
        pathHint: [String],
        currentIndex: Int
    ) -> Element? {
        guard let children = currentElement.children(), !children.isEmpty else {
            let pathTraversedString = pathHint.prefix(currentIndex).joined(separator: arrowSeparator)
            let errMessage = "Element \(currentElement.briefDescription(option: .short)) has no children. " +
                "Cannot navigate further for hint segment '\(hintSegment)'. " +
                "Path traversed so far: \(pathTraversedString)"
            axDebugLog(errMessage,
                       file: #file,
                       function: #function,
                       line: #line
            )
            return nil
        }

        // Parse the hint segment
        let segmentParts = hintSegment.split(separator: "=", maxSplits: 1)
        let identifier = String(segmentParts[0])
        let value = segmentParts.count > 1 ? String(segmentParts[1]) : nil

        // Try to find a matching child
        let matchedChild = findMatchingChildForHint(
            children: children,
            identifier: identifier,
            value: value
        )

        if let foundChild = matchedChild {
            axDebugLog("Matched segment '\(hintSegment)' to child: \(foundChild.briefDescription())",
                       file: #file,
                       function: #function,
                       line: #line
            )
            return foundChild
        } else {
            let pathTraversedString = pathHint.prefix(currentIndex).joined(separator: arrowSeparator)
            let warnMessage = "No child matched segment '\(hintSegment)' under \(currentElement.briefDescription(option: .short)). Path traversed: \(pathTraversedString)"
            axWarningLog(warnMessage,
                         file: #file,
                         function: #function,
                         line: #line
            )
            return nil
        }
    }

    // Helper: Find matching child for hint
    @MainActor
    private func findMatchingChildForHint(
        children: [Element],
        identifier: String,
        value: String?
    ) -> Element? {
        // Handle index-based navigation
        if identifier.starts(with: "@") {
            return handleIndexBasedNavigation(
                identifier: identifier,
                children: children
            )
        }

        // Handle attribute-based navigation
        for child in children {
            if let match = checkChildMatchesHint(
                child: child,
                identifier: identifier,
                value: value
            ) {
                return match
            }
        }

        return nil
    }

    // Helper: Handle index-based navigation
    @MainActor
    private func handleIndexBasedNavigation(
        identifier: String,
        children: [Element]
    ) -> Element? {
        if let indexValue = Int(identifier.dropFirst()),
           indexValue >= 0,
           indexValue < children.count {
            let matchedChild = children[indexValue]
            axDebugLog("Matched child by index \(indexValue): \(matchedChild.briefDescription())",
                       file: #file,
                       function: #function,
                       line: #line
            )
            return matchedChild
        } else {
            axDebugLog("Invalid index '\(identifier)' for children count \(children.count).",
                       file: #file,
                       function: #function,
                       line: #line
            )
            return nil
        }
    }

    // Helper: Check if child matches hint
    @MainActor
    private func checkChildMatchesHint(
        child: Element,
        identifier: String,
        value: String?
    ) -> Element? {
        let attributeToMatch = determineAttributeToMatch(identifier: identifier)
        let expectedValue = value

        // If no value specified, try common attributes
        if value == nil && attributeToMatch == identifier {
            if child.title() == identifier ||
                child.role() == identifier ||
                child.roleDescription() == identifier {
                return child
            }
            return nil
        }

        // Check attribute value
        let attrName = attributeToMatch
        if let valToCompare = expectedValue {
            if let attrValue: String = child.attribute(Attribute(attrName)) {
                if attrValue.localizedCaseInsensitiveContains(valToCompare) {
                    return child
                }
            } else if let attrValueAny = child.attribute(Attribute<Any>(attrName)) {
                if String(describing: attrValueAny).localizedCaseInsensitiveContains(valToCompare) {
                    return child
                }
            }
        }

        return nil
    }

    // Helper: Determine which attribute to match
    @MainActor
    private func determineAttributeToMatch(identifier: String) -> String {
        switch identifier.lowercased() {
        case "role":
            return AXAttributeNames.kAXRoleAttribute
        case "subrole":
            return AXAttributeNames.kAXSubroleAttribute
        case "title":
            return AXAttributeNames.kAXTitleAttribute
        case "identifier":
            return AXAttributeNames.kAXIdentifierAttribute
        case "value":
            return AXAttributeNames.kAXValueAttribute
        case "description":
            return AXAttributeNames.kAXDescriptionAttribute
        default:
            return identifier
        }
    }

    // MARK: - Internal Helper: findTargetElement (Common logic for locating elements)
    @MainActor
    internal func findTargetElement(
        for appIdentifierOrNil: String?,
        locator: Locator?,
        pathHint: [String]?,
        maxDepthForSearch: Int
    ) async -> Result<Element, HandlerErrorInfo> {
        let appIdentifier = appIdentifierOrNil ?? self.focusedAppKeyValue
        axDebugLog("findTargetElement: App=\(appIdentifier), Locator=\(String(describing: locator?.criteria)), PathHint=\(String(describing: pathHint))", file: #file, function: #function, line: #line)

        guard let appElement = applicationElement(for: appIdentifier) else {
            let msg = "Application not found: \(appIdentifier)"
            axErrorLog(msg,
                       file: #file,
                       function: #function,
                       line: #line
            )
            return .failure(HandlerErrorInfo(message: msg, logs: nil))
        }

        var effectiveElement = appElement
        if let hint = pathHint, !hint.isEmpty {
            axDebugLog("findTargetElement: Navigating with path_hint: \(hint.joined(separator: " -> "))",
                       file: #file,
                       function: #function,
                       line: #line
            )
            guard let navigated = navigateToElement(from: effectiveElement, pathHint: hint, maxDepth: AXMiscConstants.defaultMaxDepthSearch) else {
                let msg = "Element not found via path hint: \(hint.joined(separator: " -> "))"
                axErrorLog(msg,
                           file: #file,
                           function: #function,
                           line: #line
                )
                return .failure(HandlerErrorInfo(message: msg, logs: nil))
            }
            effectiveElement = navigated
            axDebugLog("findTargetElement: Path hint navigated to: \(effectiveElement.briefDescription())",
                       file: #file,
                       function: #function,
                       line: #line
            )
        }

        if let loc = locator {
            var searchStartElement = effectiveElement
            if let rootPathHint = loc.rootElementPathHint, !rootPathHint.isEmpty {
                axDebugLog(
                    "findTargetElement: Locator has rootElementPathHint: " +
                        "\(rootPathHint.joined(separator: " -> ")). Navigating from app element.",
                    file: #file,
                    function: #function,
                    line: #line
                )
                guard let container = navigateToElement(from: appElement, pathHint: rootPathHint, maxDepth: AXMiscConstants.defaultMaxDepthSearch) else {
                    let msg = "Container for locator not found via root_element_path_hint: \(rootPathHint.joined(separator: " -> "))"
                    axErrorLog(msg,
                               file: #file,
                               function: #function,
                               line: #line
                    )
                    return .failure(HandlerErrorInfo(message: msg, logs: nil))
                }
                searchStartElement = container
                axDebugLog("findTargetElement: Search for locator will start from container: \(searchStartElement.briefDescription())",
                           file: #file,
                           function: #function,
                           line: #line
                )
            }

            let searchResult = self.search( // search returns SearchResult
                element: searchStartElement,
                locator: loc,
                requireAction: loc.requireAction,
                depth: 0, // Start search from depth 0 relative to searchStartElement
                maxDepth: maxDepthForSearch
            )

            if let found = searchResult {
                axInfoLog("findTargetElement: Found element with locator: \(found.briefDescription())", file: #file, function: #function, line: #line)
                return .success(found)
            } else {
                let msg = "Element not found matching locator criteria: \(loc.criteria)"
                axWarningLog(msg,
                             file: #file,
                             function: #function,
                             line: #line
                )
                return .failure(HandlerErrorInfo(message: msg, logs: nil))
            }
        } else {
            // No locator, so the element determined by path_hint (or appElement if no path_hint) is the target.
            axInfoLog("findTargetElement: No locator provided, using element from path_hint (or app root): \(effectiveElement.briefDescription())", file: #file, function: #function, line: #line)
            return .success(effectiveElement)
        }
    }
}

// Helper struct for findTargetElement's error case
internal struct HandlerErrorInfo: Error {
    let message: String
    let logs: [String]? // This will be nil now as logs are global
}

// NOTE: The `search` method in AXorcist.swift also needs refactoring to remove `currentDebugLogs`
// and use GlobalAXLogger. It currently returns a tuple (foundElement: Element?, logs: [String]).
// It should be changed to return just `Element?`.
// The calls to `self.search(...).foundElement` in this file anticipate that change.
// `findElementViaPathAndCriteria` (a global func) also needs this refactoring.

// `AXorcist.formatDebugLogMessage` is no longer needed.
// `SearchVisitor` and other utility structs/classes might also have logging to update.

// `encodeAttributesToJSONStringRepresentation` may or may not need logging changes.
