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

    @MainActor
    private func encode(_ output: CollectAllOutput) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        do {
            let jsonData = try encoder.encode(output)
            return String(data: jsonData, encoding: .utf8) ?? "{\"error\":\"Failed to encode CollectAllOutput to string (fallback)\"}"
        } catch {
            axErrorLog("Exception encoding CollectAllOutput: \(error.localizedDescription)")
            let cmdId = output.commandId
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
        guard let appElement = applicationElement(for: params.appIdentifier) else {
            return createErrorResponse(
                commandId: params.effectiveCommandId,
                appIdentifier: params.appIdentifier,
                error: "Failed to get app element for identifier: \(params.appIdentifier)",
                debugCLI: debugCLI
            )
        }
        let startElementResult = await determineStartElementForCollectAll(
            appElement: appElement,
            locator: locator,
            params: params
        )

        guard let startElement = startElementResult.element else {
            return createErrorResponse(
                commandId: params.effectiveCommandId,
                appIdentifier: params.appIdentifier,
                error: startElementResult.error ?? "Failed to determine start element for collectAll",
                debugCLI: debugCLI
            )
        }

        let collectedElements = await performCollectionTraversal(
            startElement: startElement,
            appElement: appElement,
            params: params
        )
        return createSuccessResponse(
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
        let locatorPathHintDesc = params.locator?.rootElementPathHint?.map { "(attr:\($0.attribute),val:\($0.value),d:\($0.depth ?? -1))" }.joined(separator: " -> ") ?? "nil"
        let maxDepthDesc = String(describing: params.recursionDepthLimit)

        axInfoLog(
            "[AXorcist.handleCollectAll] Starting. App: \(appNameForLog), " +
            "LocatorCriteria: \(locatorCriteriaDesc), LocatorJSONPathHint: [\(locatorPathHintDesc)], MaxDepth: \(maxDepthDesc)"
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
        if let jsonPathComponents = locator?.rootElementPathHint, !jsonPathComponents.isEmpty {
            let pathHintDebug = jsonPathComponents.map { "(attr:\($0.attribute),val:\($0.value),d:\($0.depth ?? -1))" }.joined(separator: " -> ")
            axDebugLog("[CollectAll] Navigating for start element using JSONPathHint: [\(pathHintDebug)] (\(jsonPathComponents.count) components)")

            if let navigatedElement = await navigateToElementByJSONPathHint(
                pathHint: jsonPathComponents, 
                initialSearchElement: appElement
            ) {
                axDebugLog("[CollectAll] JSONPathHint navigation successful. Start element for collectAll: \(navigatedElement.briefDescription())")
                return (navigatedElement, nil)
            } else {
                let errorMsg = "[CollectAll] Failed to navigate to start element using JSONPathHint: [\(pathHintDebug)]"
                axWarningLog(errorMsg)
                return (nil, errorMsg)
            }
        } else {
            axDebugLog("[CollectAll] No rootElementPathHint (JSON) in locator or locator is nil. Starting collectAll from app root: \(appElement.briefDescription())")
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
        
        let effectiveLocatorCriteria = params.locator?.criteria ?? params.filterCriteria ?? [: ]
        let matchingLocator = Locator(criteria: effectiveLocatorCriteria)
        let collectedData = await collectAllElements(
            from: startElement,
            matching: matchingLocator,
            appElementForContext: appElement,
            attributesToFetch: params.attributesToFetch,
            outputFormat: params.effectiveOutputFormat,
            maxElements: AXMiscConstants.defaultMaxElementsToCollect,
            maxSearchDepth: params.recursionDepthLimit
        )
        
        axDebugLog("[CollectAll.performCollectionTraversal] Traversal complete. Collected \(collectedData.count) AXElementData items.")
        return collectedData
    }

    @MainActor
    private func createErrorResponse(
        commandId: String,
        appIdentifier: String,
        error: String,
        debugCLI: Bool
    ) -> String {
        let logs = debugCLI ? axGetLogsAsStrings(format: .text) : nil
        let output = CollectAllOutput(
            commandId: commandId,
            success: false,
            command: "collectAll",
            collectedElements: nil,
            appIdentifier: appIdentifier,
            debugLogs: logs,
            message: error
        )
        return encode(output)
    }

    @MainActor
    private func createSuccessResponse(
        commandId: String,
        appIdentifier: String,
        collectedElements: [AXElementData],
        debugCLI: Bool
    ) -> String {
        let logs = debugCLI ? axGetLogsAsStrings(format: .text) : nil
        let output = CollectAllOutput(
            commandId: commandId,
            success: true,
            command: "collectAll",
            collectedElements: collectedElements,
            appIdentifier: appIdentifier,
            debugLogs: logs,
            message: "Successfully collected \(collectedElements.count) elements."
        )
        return encode(output)
    }
}

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

// Assuming CollectAllOutput and ErrorDetails structs are defined appropriately.
// Removed duplicate definition of CollectAllOutput, it's defined in Core/ResponseModels.swift
// public struct CollectAllOutput: Codable {
//     public let commandId: String
//     public let success: Bool
//     public let command: String // e.g. "collectAll"
//     public var collectedElements: [AXElementData] = []
//     public var errorMessage: String?
//     public var debugLogs: [String]?
//     public var errorDetails: ErrorDetails?
// 
//     enum CodingKeys: String, CodingKey {
//         case commandId = "command_id"
//         case success
//         case command
//         case collectedElements = "collected_elements"
//         case errorMessage = "error_message"
//         case debugLogs = "debug_logs"
//         case errorDetails = "error_details"
//     }
// }

// public struct ErrorDetails: Codable {
//     public var code: Int? // e.g., AXError raw value or a custom error code
//     public var domain: String? // e.g., "AXorcist.AXErrorDomain"
//     public var context: String? // Additional context about the error
// }
