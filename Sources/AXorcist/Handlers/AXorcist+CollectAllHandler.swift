// AXorcist+CollectAllHandler.swift - CollectAll operation handler

import AppKit
import ApplicationServices
import Foundation

// Define a new generic Response structure if one doesn't exist suitable for this context.
// For now, we'll assume that a general Response structure is available or defined elsewhere.
// If not, one would be:
public struct ResponseContainer: Codable { // Renamed to avoid conflict if a `Response` type exists elsewhere
    public var command_id: String
    public var success: Bool
    public var command: String // e.g., "collectAll"
    public var message: String?
    public var data: ResponseData? // Using a new ResponseData enum/struct
    public var error: String?
    public var debug_logs: [String]?
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

    private func encode(_ output: CollectAllOutput) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        do {
            let jsonData = try encoder.encode(output)
            return String(data: jsonData, encoding: .utf8) ?? "{\"error\":\"Failed to encode CollectAllOutput to string (fallback)\"}"
        } catch {
            let errorMsgForLog = "Exception encoding CollectAllOutput: \(error.localizedDescription)"
            self.recursiveCallDebugLogs.append(errorMsgForLog)
            return "{\"command_id\":\"Unknown\", \"success\":false, \"command\":\"Unknown\", \"error_message\":\"Catastrophic JSON encoding failure for CollectAllOutput. Original error logged.\", \"collected_elements\":[], \"debug_logs\":[\"Catastrophic JSON encoding failure as well.\"]}"
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
        isDebugLoggingEnabled: Bool,
        currentDebugLogs: [String]
    ) -> String {
        self.recursiveCallDebugLogs.removeAll()
        self.recursiveCallDebugLogs.append(contentsOf: currentDebugLogs)

        let effectiveCommandId = commandId ?? "collectAll_internal_id_error"

        func dLog(
            _ message: String,
            _ file: String = #file,
            _ function: String = #function,
            _ line: Int = #line
        ) {
            let logMessage = AXorcist.formatDebugLogMessage(
                message,
                applicationName: appIdentifierOrNil,
                commandID: effectiveCommandId,
                file: file,
                function: function,
                line: line
            )
            self.recursiveCallDebugLogs.append(logMessage)
        }

        let appNameForLog = appIdentifierOrNil ?? "N/A"
        let locatorDesc = locator != nil ? String(describing: locator!.criteria) : "nil"
        let pathHintDesc = String(describing: pathHint)
        let maxDepthDesc = String(describing: maxDepth)
        dLog(
            "[AXorcist.handleCollectAll] Starting. App: \(appNameForLog), Locator: \(locatorDesc), PathHint: \(pathHintDesc), MaxDepth: \(maxDepthDesc)"
        )

        let recursionDepthLimit = (maxDepth != nil && maxDepth! >= 0) ? maxDepth! : AXMiscConstants.defaultMaxDepthCollectAll
        let attributesToFetch = requestedAttributes ?? AXorcist.defaultAttributesToFetch
        let effectiveOutputFormat = outputFormat ?? .smart

        dLog(
            "Effective recursionDepthLimit: \(recursionDepthLimit), attributesToFetch: \(attributesToFetch.count) items, effectiveOutputFormat: \(effectiveOutputFormat.rawValue)"
        )

        let appIdentifier = appIdentifierOrNil ?? focusedAppKeyValue
        dLog("Using app identifier: \(appIdentifier)")

        guard let appElement = applicationElement(
            for: appIdentifier,
            isDebugLoggingEnabled: isDebugLoggingEnabled,
            currentDebugLogs: &self.recursiveCallDebugLogs
        ) else {
            let errorMsg = "Failed to get app element for identifier: \(appIdentifier)"
            dLog(errorMsg)
            return encode(CollectAllOutput(
                command_id: effectiveCommandId,
                success: false,
                command: "collectAll",
                collected_elements: [],
                app_bundle_id: appIdentifier,
                debug_logs: self.recursiveCallDebugLogs
            ))
        }

        var startElement: Element
        if let hint = pathHint, !hint.isEmpty {
            let pathHintString = hint.joined(separator: " -> ")
            dLog("Navigating to path hint: \(pathHintString)")
            guard let navigatedElement = navigateToElement(
                from: appElement,
                pathHint: hint,
                isDebugLoggingEnabled: isDebugLoggingEnabled,
                currentDebugLogs: &self.recursiveCallDebugLogs
            ) else {
                let lastLogBeforeError = self.recursiveCallDebugLogs.last
                var errorMsg = "Failed to navigate to path: \(pathHintString)"
                if let lastLog = lastLogBeforeError, lastLog == "CRITICAL_NAV_PARSE_FAILURE_MARKER" {
                    errorMsg = "Navigation parsing failed: Critical marker found."
                } else if let lastLog = lastLogBeforeError, lastLog == "CHILD_MATCH_FAILURE_MARKER" {
                    errorMsg = "Navigation child match failed: Child match marker found."
                }
                dLog(errorMsg)
                return encode(CollectAllOutput(
                    command_id: effectiveCommandId,
                    success: false,
                    command: "collectAll",
                    collected_elements: [],
                    app_bundle_id: appIdentifier,
                    debug_logs: self.recursiveCallDebugLogs
                ))
            }
            startElement = navigatedElement
        } else {
            dLog("Using app element as start element")
            startElement = appElement
        }

        if let loc = locator {
            dLog("Locator provided. Searching for element from current startElement: \(startElement.briefDescription(option: ValueFormatOption.default, isDebugLoggingEnabled: isDebugLoggingEnabled, currentDebugLogs: &self.recursiveCallDebugLogs)) with locator criteria: \(String(describing: loc.criteria))")

            let searchResultCollectAll = self.search(element: startElement,
                                                     locator: loc,
                                                     requireAction: loc.requireAction,
                                                     depth: 0,
                                                     maxDepth: AXMiscConstants.defaultMaxDepthSearch,
                                                     isDebugLoggingEnabled: isDebugLoggingEnabled,
                                                     currentDebugLogs: &self.recursiveCallDebugLogs)
            self.recursiveCallDebugLogs.append(contentsOf: searchResultCollectAll.logs)

            if let locatedStartElement = searchResultCollectAll.foundElement {
                dLog("Locator found element: \(locatedStartElement.briefDescription(option: ValueFormatOption.default, isDebugLoggingEnabled: isDebugLoggingEnabled, currentDebugLogs: &self.recursiveCallDebugLogs)). This will be the root for collectAll recursion.")
                startElement = locatedStartElement
            } else {
                let errorMsg = "Failed to find element with provided locator criteria: \(String(describing: loc.criteria)). Cannot start collectAll."
                dLog(errorMsg)
                return encode(CollectAllOutput(
                    command_id: effectiveCommandId,
                    success: false,
                    command: "collectAll",
                    collected_elements: [],
                    app_bundle_id: appIdentifier,
                    debug_logs: self.recursiveCallDebugLogs
                ))
            }
        }

        var collectedElementsOutput: [AXElement] = [] // Type for CollectAllOutput
        var traverser = TreeTraverser()
        
        let visitor = CollectAllVisitor(
            attributesToFetch: attributesToFetch,
            outputFormat: effectiveOutputFormat,
            appElement: appElement
        )
        
        var traversalContext = TraversalContext(
            maxDepth: recursionDepthLimit,
            isDebugLoggingEnabled: isDebugLoggingEnabled,
            currentDebugLogs: self.recursiveCallDebugLogs,
            startElement: startElement
        )
        
        dLog("Starting unified tree traversal from start element: \(startElement.briefDescription(option: ValueFormatOption.default, isDebugLoggingEnabled: isDebugLoggingEnabled, currentDebugLogs: &self.recursiveCallDebugLogs))")
        
        if !self.recursiveCallDebugLogs.contains(where: { $0.contains("Failed to find element with provided locator criteria") && $0.contains("Cannot start collectAll") }) {
            _ = traverser.traverse(from: startElement, visitor: visitor, context: &traversalContext)
            // Access the public property directly
            // The visitor.collectedElements is [AXElementData]. CollectAllOutput expects [AXElement].
            // This requires a mapping if AXElementData is not directly usable or if AXElement is a different type.
            // For now, assuming AXElementData can be mapped or cast, or CollectAllOutput needs to change.
            // This is a placeholder: you might need to map properties from AXElementData to create AXElement instances.
            collectedElementsOutput = visitor.collectedElements.map { data in 
                // This mapping is highly dependent on AXElement's structure and what AXElementData holds.
                // If AXElement just needs attributes and path, and AXElementData provides them:
                AXElement(attributes: data.attributes, path: data.path)
            } 
            self.recursiveCallDebugLogs = traversalContext.currentDebugLogs
        }

        let output = CollectAllOutput(
            command_id: effectiveCommandId,
            success: true,
            command: "collectAll",
            collected_elements: collectedElementsOutput, // Use the mapped elements
            app_bundle_id: appIdentifier,
            debug_logs: self.recursiveCallDebugLogs
        )
        return encode(output)
    }

    @MainActor
    func handleCollectAll(
        commandRequest: CommandEnvelope, 
        appElement: Element,
        startElement: Element,
        attributesToFetch: [String],
        maxElements: Int,
        recursionDepthLimit: Int,
        outputFormat: OutputFormat,
        isDebugLoggingEnabled: Bool
    ) -> Result<ResponseContainer, AccessibilityError> {
        var operationDebugLogs: [String] = [] 
        var tempContextForInitialLog = TraversalContext(maxDepth: 0, isDebugLoggingEnabled: isDebugLoggingEnabled, currentDebugLogs: operationDebugLogs, startElement: startElement)
        dLog("Starting collectAll operation. Command ID: \(commandRequest.command_id)", context: &tempContextForInitialLog)
        operationDebugLogs = tempContextForInitialLog.currentDebugLogs

        var traverser = TreeTraverser()
        let visitor = CollectAllVisitor(
            attributesToFetch: attributesToFetch,
            outputFormat: outputFormat,
            appElement: appElement
        )
        
        var traversalContext = TraversalContext(
            maxDepth: recursionDepthLimit,
            isDebugLoggingEnabled: isDebugLoggingEnabled,
            currentDebugLogs: operationDebugLogs, 
            startElement: startElement
        )
        
        dLog("Beginning tree traversal for collectAll from: \(startElement.briefDescriptionForDebug(context: &traversalContext))", context: &traversalContext)
        
        _ = traverser.traverse(from: startElement, visitor: visitor, context: &traversalContext)
        
        let collectedElementsData = visitor.collectedElements 
        operationDebugLogs = traversalContext.currentDebugLogs

        dLog("Traversal complete. Collected \(collectedElementsData.count) elements.", context: &traversalContext)
        operationDebugLogs = traversalContext.currentDebugLogs

        if collectedElementsData.isEmpty {
            dLog("No elements collected, but traversal itself was successful.", context: &traversalContext)
            operationDebugLogs = traversalContext.currentDebugLogs
        }
        
        let response = ResponseContainer(
            command_id: commandRequest.command_id,
            success: true,
            command: commandRequest.command.rawValue, 
            message: "Successfully collected \(collectedElementsData.count) elements.",
            data: ResponseData.elementsList(collectedElementsData), 
            debug_logs: isDebugLoggingEnabled ? operationDebugLogs : nil
        )
        return .success(response)
    }
}
