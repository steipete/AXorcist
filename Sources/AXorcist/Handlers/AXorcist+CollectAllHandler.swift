// AXorcist+CollectAllHandler.swift - CollectAll operation handler

import AppKit
import ApplicationServices
import Foundation

// Define a new generic Response structure if one doesn't exist suitable for this context.
// For now, we'll assume that a general Response structure is available or defined elsewhere.
// If not, one would be:
public struct ResponseContainer: Codable { // Renamed to avoid conflict if a `Response` type exists elsewhere
    public var commandId: String
    public var success: Bool
    public var command: String // e.g., "collectAll"
    public var message: String?
    public var data: ResponseData? // Using a new ResponseData enum/struct
    public var error: String?
    public var debugLogs: [String]?

    enum CodingKeys: String, CodingKey {
        case commandId = "command_id"
        case success
        case command
        case message
        case data
        case error
        case debugLogs = "debug_logs"
    }
}

// Assuming CommandType is an enum with String raw values, e.g.:
// public enum CommandType: String, Codable {
//    case query, collectAll, performAction, ping, extractText, batch
// }

// AXElementData is now defined in TreeTraversal.swift
// public struct AXElementData: Codable { ... }

public enum ResponseData: Codable {
    case elementsList([AXElementData])
    case element(AXElementData?)
    case textContent(String?)
    case status(String)
    case batchResults([ResponseContainer])
}

// MARK: - CollectAll Handler Extension
extension AXorcist {

    // Helper to encode CollectAllOutput, now using GlobalAXLogger for errors
    @MainActor
    private func encode(_ output: CollectAllOutput) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        do {
            let jsonData = try encoder.encode(output)
            return String(data: jsonData, encoding: .utf8) ?? "{\"error\":\"Failed to encode CollectAllOutput to string (fallback)\"}"
        } catch {
            axErrorLog("Exception encoding CollectAllOutput: \(error.localizedDescription)")
            let errorJson = """
            {"command_id":"\(output.commandId)", \
            "success":false, \
            "command":"\(output.command)", \
            "error_message":"Catastrophic JSON encoding failure for CollectAllOutput. Original error logged.", \
            "collected_elements":[], \
            "debug_logs":["Catastrophic JSON encoding failure as well."]}
            """
            return errorJson
        }
    }

    @MainActor
    public func handleCollectAll(
        for appIdentifierOrNil: String?,
        locator: Locator?,
        pathHint: [String]?,
        maxDepth: Int?,
        requestedAttributes: [String]?,
        outputFormat: OutputFormat?,
        commandId: String?,
        debugCLI: Bool
    ) async -> String {
        let params = CollectAllParameters(
            appIdentifierOrNil: appIdentifierOrNil,
            locator: locator,
            pathHint: pathHint,
            maxDepth: maxDepth,
            requestedAttributes: requestedAttributes,
            outputFormat: outputFormat,
            commandId: commandId,
            focusedAppKey: AXMiscConstants.focusedApplicationKey
        )

        logCollectAllStart(params)

        // Get app element
        guard let appElement = applicationElement(for: params.appIdentifier) else {
            return await createErrorResponse(
                commandId: params.effectiveCommandId,
                appIdentifier: params.appIdentifier,
                error: "Failed to get app element for identifier: \(params.appIdentifier)",
                debugCLI: debugCLI
            )
        }

        // Determine start element
        let startElementResult = await determineStartElement(
            appElement: appElement,
            pathHint: pathHint,
            locator: locator,
            params: params
        )

        guard let startElement = startElementResult.element else {
            return await createErrorResponse(
                commandId: params.effectiveCommandId,
                appIdentifier: params.appIdentifier,
                error: startElementResult.error ?? "Failed to determine start element",
                debugCLI: debugCLI
            )
        }

        // Perform collection
        let collectedElements = await performCollectionTraversal(
            startElement: startElement,
            appElement: appElement,
            params: params
        )

        return await createSuccessResponse(
            commandId: params.effectiveCommandId,
            appIdentifier: params.appIdentifier,
            collectedElements: collectedElements,
            debugCLI: debugCLI
        )
    }

    @MainActor
    private struct CollectAllParameters {
        let effectiveCommandId: String
        let appIdentifier: String
        let recursionDepthLimit: Int
        let attributesToFetch: [String]
        let effectiveOutputFormat: OutputFormat
        let locator: Locator?
        let pathHint: [String]?

        init(
            appIdentifierOrNil: String?,
            locator: Locator?,
            pathHint: [String]?,
            maxDepth: Int?,
            requestedAttributes: [String]?,
            outputFormat: OutputFormat?,
            commandId: String?,
            focusedAppKey: String
        ) {
            self.effectiveCommandId = commandId ?? "collectAll_internal_id_\(UUID().uuidString.prefix(8))"
            self.appIdentifier = appIdentifierOrNil ?? focusedAppKey
            self.recursionDepthLimit = (maxDepth != nil && maxDepth! >= 0)
                ? maxDepth!
                : AXMiscConstants.defaultMaxDepthCollectAll
            self.attributesToFetch = requestedAttributes ?? AXorcist.defaultAttributesToFetch
            self.effectiveOutputFormat = outputFormat ?? .smart
            self.locator = locator
            self.pathHint = pathHint
        }
    }

    @MainActor
    private func logCollectAllStart(_ params: CollectAllParameters) {
        let appNameForLog = params.appIdentifier
        let locatorDesc = params.locator != nil ? String(describing: params.locator!.criteria) : "nil"
        let pathHintDesc = String(describing: params.pathHint)
        let maxDepthDesc = String(describing: params.recursionDepthLimit)

        axInfoLog(
            "[AXorcist.handleCollectAll] Starting. App: \(appNameForLog), " +
                "Locator: \(locatorDesc), PathHint: \(pathHintDesc), MaxDepth: \(maxDepthDesc)"
        )

        axDebugLog(
            "Effective recursionDepthLimit: \(params.recursionDepthLimit), " +
                "attributesToFetch: \(params.attributesToFetch.count) items, " +
                "effectiveOutputFormat: \(params.effectiveOutputFormat.rawValue)"
        )

        axDebugLog("Using app identifier: \(params.appIdentifier)")
    }

    @MainActor
    private func determineStartElement(
        appElement: Element,
        pathHint: [String]?,
        locator: Locator?,
        params: CollectAllParameters
    ) async -> (element: Element?, error: String?) {
        var startElement = appElement
        var pathNavigated = false

        // Navigate to path hint if provided
        if let hint = pathHint, !hint.isEmpty {
            let pathHintString = hint.joined(separator: " -> ")
            axDebugLog("[CollectAll] Navigating to path hint: \(pathHintString)")

            guard let navigatedElement = navigateToElement(
                from: appElement,
                pathHint: hint,
                maxDepth: AXMiscConstants.defaultMaxDepthSearch
            ) else {
                return (nil, "Failed to navigate to path: \(pathHintString)")
            }
            startElement = navigatedElement
            pathNavigated = true
            axDebugLog("[CollectAll] Path navigation successful. Current startElement: \(startElement.briefDescription())")
        } else {
            axDebugLog("[CollectAll] No pathHint provided. Current startElement: \(startElement.briefDescription()) (app root)")
        }

        if !pathNavigated, let loc = locator, !loc.criteria.isEmpty {
            axDebugLog("[CollectAll] Path navigation did not occur. Trying locator.criteria from startElement: \(startElement.briefDescription())")
            if let locatedElement = findElementByLocator(
                startElement: startElement,
                locator: loc
            ) {
                axDebugLog(
                    "[CollectAll] Locator (criteria-only) found element: \(locatedElement.briefDescription()). " +
                        "This will be the root for collectAll recursion."
                )
                startElement = locatedElement
            } else {
                let locatorDescription = String(describing: loc.criteria)
                let currentStartDesc = startElement.briefDescription()
                axWarningLog(
                    "[CollectAll] Locator (criteria-only) provided but no element found for: \(locatorDescription) from \(currentStartDesc). " +
                        "CollectAll will proceed from \(currentStartDesc)."
                )
            }
        } else if pathNavigated {
            axDebugLog("[CollectAll] Path navigation occurred. Using element from path as definitive root: \(startElement.briefDescription()). Locator.criteria (if any) will not be used to further refine this root.")
        } else if let loc = locator, loc.criteria.isEmpty {
            axDebugLog("[CollectAll] Locator provided with empty criteria and no path hint. Using current startElement: \(startElement.briefDescription()) as root.")
        }

        return (startElement, nil)
    }

    @MainActor
    private func findElementByLocator(
        startElement: Element,
        locator: Locator
    ) -> Element? {
        var treeTraverser = TreeTraverser()
        let searchVisitor = SearchVisitor(locator: locator, requireAction: locator.requireAction)
        var traversalState = TraversalState(
            maxDepth: AXMiscConstants.defaultMaxDepthSearch,
            startElement: startElement
        )

        return treeTraverser.traverse(
            from: startElement,
            visitor: searchVisitor,
            state: &traversalState
        )
    }

    @MainActor
    private func performCollectionTraversal(
        startElement: Element,
        appElement: Element,
        params: CollectAllParameters
    ) async -> [AXElement] {
        var traverser = TreeTraverser()
        let visitor = CollectAllVisitor(
            attributesToFetch: params.attributesToFetch,
            outputFormat: params.effectiveOutputFormat,
            appElement: appElement
        )

        var traversalState = TraversalState(
            maxDepth: params.recursionDepthLimit,
            startElement: startElement,
            strictChildren: true
        )

        axDebugLog("[Pre-Traverse PCT] Handler: validStartElement is: \(startElement.briefDescription(option: .default)) with strictChildren=true")
        _ = traverser.traverse(from: startElement, visitor: visitor, state: &traversalState)

        let collectedElementsData = visitor.collectedElements
        let collectedElementsOutput = collectedElementsData.map { data in
            AXElement(attributes: data.attributes, path: data.path)
        }

        axDebugLog("Traversal complete. Collected \(collectedElementsOutput.count) elements.")
        if collectedElementsOutput.isEmpty {
            axInfoLog("No elements collected, but traversal itself was successful.")
        }

        return collectedElementsOutput
    }

    @MainActor
    private func createErrorResponse(
        commandId: String,
        appIdentifier: String,
        error: String,
        debugCLI: Bool
    ) async -> String {
        axErrorLog(error)
        // Conditionally fetch logs based on debugCLI
        let logs = debugCLI ? await GlobalAXLogger.shared.getLogsAsStrings(format: .text) : nil
        return encode(CollectAllOutput(
            commandId: commandId,
            success: false,
            command: "collectAll",
            collectedElements: [],
            appBundleId: appIdentifier,
            debugLogs: logs,
            errorMessage: error
        ))
    }

    @MainActor
    private func createSuccessResponse(
        commandId: String,
        appIdentifier: String,
        collectedElements: [AXElement],
        debugCLI: Bool
    ) async -> String {
        // Conditionally fetch logs based on debugCLI
        let logs = debugCLI ? await GlobalAXLogger.shared.getLogsAsStrings(format: .text) : nil
        let output = CollectAllOutput(
            commandId: commandId,
            success: true,
            command: "collectAll",
            collectedElements: collectedElements,
            appBundleId: appIdentifier,
            debugLogs: logs,
            errorMessage: nil
        )
        return encode(output)
    }
}
