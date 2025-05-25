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
            let cmdId = output.commandId // Assuming these are direct properties
            let cmdType = output.command
            let errorJson = """
            {"command_id":"\(cmdId)", \
            "success":false, \
            "command":"\(cmdType)", \
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
        maxDepth: Int?,
        requestedAttributes: [String]?,
        outputFormat: OutputFormat?,
        commandId: String?,
        debugCLI: Bool,
        filterCriteria: [String: String]? = nil
    ) async -> String {
        let params = CollectAllParameters(
            appIdentifierOrNil: appIdentifierOrNil,
            locator: locator,
            maxDepth: maxDepth,
            requestedAttributes: requestedAttributes,
            outputFormat: outputFormat,
            commandId: commandId,
            focusedAppKey: AXMiscConstants.focusedApplicationKey,
            filterCriteria: filterCriteria
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

        // Determine start element using locator.rootElementPathHint
        let startElementResult = await determineStartElementForCollectAll(
            appElement: appElement,
            locator: locator,
            params: params
        )

        guard let startElement = startElementResult.element else {
            return await createErrorResponse(
                commandId: params.effectiveCommandId,
                appIdentifier: params.appIdentifier,
                error: startElementResult.error ?? "Failed to determine start element for collectAll",
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
        let filterCriteria: [String: String]?

        init(
            appIdentifierOrNil: String?,
            locator: Locator?,
            maxDepth: Int?,
            requestedAttributes: [String]?,
            outputFormat: OutputFormat?,
            commandId: String?,
            focusedAppKey: String,
            filterCriteria: [String: String]?
        ) {
            self.effectiveCommandId = commandId ?? "collectAll_internal_id_\(UUID().uuidString.prefix(8))"
            self.appIdentifier = appIdentifierOrNil ?? focusedAppKey
            self.recursionDepthLimit = (maxDepth != nil && maxDepth! >= 0)
                ? maxDepth!
                : AXMiscConstants.defaultMaxDepthCollectAll
            self.attributesToFetch = requestedAttributes ?? AXorcist.defaultAttributesToFetch
            self.effectiveOutputFormat = outputFormat ?? .smart
            self.locator = locator
            self.filterCriteria = filterCriteria
        }
    }

    @MainActor
    private func logCollectAllStart(_ params: CollectAllParameters) {
        let appNameForLog = params.appIdentifier
        let locatorCriteriaDesc = params.locator?.criteria.isEmpty == false ? String(describing: params.locator!.criteria) : "nil"
        let locatorPathHintDesc = params.locator?.rootElementPathHint?.joined(separator: "->") ?? "nil"
        let maxDepthDesc = String(describing: params.recursionDepthLimit)

        axInfoLog(
            "[AXorcist.handleCollectAll] Starting. App: \(appNameForLog), " +
            "LocatorCriteria: \(locatorCriteriaDesc), LocatorPathHint: \(locatorPathHintDesc), MaxDepth: \(maxDepthDesc)"
        )
        axDebugLog(
            "Effective recursionDepthLimit: \(params.recursionDepthLimit), " +
            "attributesToFetch: \(params.attributesToFetch.count) items, " +
            "effectiveOutputFormat: \(params.effectiveOutputFormat.rawValue)"
        )
        axDebugLog("Using app identifier: \(params.appIdentifier)")
    }

    @MainActor
    private func determineStartElementForCollectAll(
        appElement: Element,
        locator: Locator?,
        params: CollectAllParameters
    ) async -> (element: Element?, error: String?) {
        // If locator.rootElementPathHint is provided, use it to find the start element.
        if let pathHintStrings = locator?.rootElementPathHint, !pathHintStrings.isEmpty {
            let pathHintComponents = pathHintStrings.compactMap { PathHintComponent(pathSegment: $0) }
            
            if pathHintComponents.count != pathHintStrings.count {
                 let errorMsg = "[CollectAll] Invalid path hint components in locator for collectAll."
                 axWarningLog(errorMsg)
                 return (nil, errorMsg)
            }
            
            if pathHintComponents.isEmpty {
                axDebugLog("[CollectAll] Locator provided with empty or unparsable rootElementPathHint. Starting from app root.")
                return (appElement, nil)
            }

            let pathHintString = pathHintStrings.joined(separator: " -> ")
            axDebugLog("[CollectAll] Navigating for start element using locator.rootElementPathHint: \(pathHintString)")

            if let navigatedElement = navigateToElementByPathHint(
                pathHint: pathHintComponents, // Assuming this is already defined, if not, use global one
                initialSearchElement: appElement,
                pathHintMaxDepth: pathHintComponents.count - 1
            ) {
                axDebugLog("[CollectAll] Path navigation successful. Start element for collectAll: \(navigatedElement.briefDescription())")
                return (navigatedElement, nil)
            } else {
                let errorMsg = "[CollectAll] Failed to navigate to start element using locator.rootElementPathHint: \(pathHintString)"
                axWarningLog(errorMsg)
                return (nil, errorMsg)
            }
        } else {
            // No rootElementPathHint in locator, or locator is nil. Start from the application element.
            axDebugLog("[CollectAll] No rootElementPathHint in locator or locator is nil. Starting collectAll from app root: \(appElement.briefDescription())")
            return (appElement, nil)
        }
    }

    @MainActor
    private func performCollectionTraversal(
        startElement: Element,
        appElement: Element,
        params: CollectAllParameters
    ) async -> [AXElementData] {
        axDebugLog(
            "[CollectAll.performCollectionTraversal] Starting traversal from: \(startElement.briefDescription()), " +
            "MaxDepth: \(params.recursionDepthLimit)"
        )
        let visitor = CollectAllVisitor(
            attributesToFetch: params.attributesToFetch,
            outputFormat: params.effectiveOutputFormat,
            appElement: appElement,
            valueFormatOption: .default,
            filterCriteria: params.filterCriteria
        )
        /* ElementSearch. */collectAll(
            appElement: appElement,
            locator: params.locator ?? Locator(criteria: [:]),
            currentElement: startElement,
            depth: 0,
            maxDepth: params.recursionDepthLimit,
            maxElements: AXMiscConstants.defaultMaxElementsToCollect,
            visitor: visitor
        )
        axDebugLog("[CollectAll.performCollectionTraversal] Traversal complete. Collected \(visitor.collectedElements.count) elements.")
        return visitor.collectedElements
    }

    @MainActor
    private func createErrorResponse(
        commandId: String,
        appIdentifier: String,
        error: String,
        debugCLI: Bool
    ) async -> String {
        axErrorLog("[CollectAll] Error for app \(appIdentifier): \(error)")
        let logs = debugCLI ? await GlobalAXLogger.shared.getLogsAsStrings(format: .text) : nil
        let output = CollectAllOutput(
            commandId: commandId,
            success: false,
            command: "collectAll",
            collectedElements: [], // Empty for error response
            appBundleId: appIdentifier,
            debugLogs: logs,
            errorMessage: error
        )
        return encode(output)
    }

    @MainActor
    private func createSuccessResponse(
        commandId: String,
        appIdentifier: String,
        collectedElements collectedElementsData: [AXElementData],
        debugCLI: Bool
    ) async -> String {
        axInfoLog("[CollectAll] Successfully collected \(collectedElementsData.count) elements for app \(appIdentifier).")
        let logs = debugCLI ? await GlobalAXLogger.shared.getLogsAsStrings(format: .text) : nil
        let output = CollectAllOutput(
            commandId: commandId,
            success: true,
            command: "collectAll",
            collectedElements: collectedElementsData, // Pass the data directly
            appBundleId: appIdentifier,
            debugLogs: logs,
            errorMessage: nil
        )
        return encode(output)
    }
}

// Assuming CollectAllOutput is defined something like this:
// struct CollectAllOutput: Codable {
// var commandId: String
// var success: Bool
// var command: String // e.g., "collectAll"
// var errorMessage: String?
// var collectedElements: [AXElementData]
// var appBundleId: String
// var debugLogs: [String]?
//
// enum CodingKeys: String, CodingKey {
// case commandId = "command_id"
// case success
// case command
// case errorMessage = "error_message" // Ensure consistency if CommandEnvelope uses error_message
// case collectedElements = "collected_elements"
// case appBundleId = "app_bundle_id"
// case debugLogs = "debug_logs"
// }
// }

// Make sure AXElementData is defined, probably in DataModels.swift or similar
// public struct AXElementData: Codable { ... }

// Ensure navigateToElementByPathHint is accessible. It is private in ElementSearch.swift.
// For this refactor, we'll assume it's made internal or public, or we use findTargetElement.
// The call `AXorcist.collectAll` in `performCollectionTraversal` refers to the global func in ElementSearch.swift
// It needs to be `ElementSearch.collectAll` or just `collectAll` if in the same module and accessible.
// For the edit, I will assume `collectAll` is callable as a static/global function.
// And `navigateToElementByPathHint` is also made accessible for `determineStartElementForCollectAll`.

// To make `navigateToElementByPathHint` and `collectAll` (from ElementSearch) accessible here,
// they should be marked `internal` or `public` in ElementSearch.swift if AXorcist+CollectAllHandler.swift
// is in a different file but same module, or `public` if different modules.
// For simplicity of this step, I'm writing the logic as if they are callable.
