// CommandExecutor.swift - Executes AXORC commands

import AppKit // For NSRunningApplication
import AXorcist
import Foundation
// import AXorcist instead of AXorcistLib

// TEMPORARY TEST STRUCT - REMOVED
// struct SimpleTestResponse: Codable {
//     var message: String
//     var logs: [String]?
// }

struct CommandExecutor {

    static func execute(
        command: CommandEnvelope,
        axorcist: AXorcist,
        debugCLI: Bool // Added debugCLI flag
    ) async -> String {
        // Setup logging based on command.debugLogging (per-command debug flag)
        // The debugCLI flag (from main CLI --debug) will be used for log *inclusion in output*.
        let (initialLoggingEnabled, initialDetailLevel) = await setupLogging(for: command)

        // Defer resetting logger to initial state
        defer {
            Task { // Must be in a Task for async calls
                await GlobalAXLogger.shared.setLoggingEnabled(initialLoggingEnabled)
                await GlobalAXLogger.shared.setDetailLevel(initialDetailLevel)
            }
        }

        // Update GlobalAXLogger operation details
        await GlobalAXLogger.shared.updateOperationDetails(commandID: command.commandId, appName: command.application)

        axDebugLog("Executing command: \(command.command) (ID: \(command.commandId)), cmdDebug: \(String(describing: command.debugLogging)), cliDebug: \(debugCLI)")

        // Pass debugCLI to processCommand
        let responseString = await processCommand(command: command, axorcist: axorcist, debugCLI: debugCLI)

        // Clear logs for this specific operation after processing,
        // so next command in a batch (if any) or next CLI call starts fresh for its specific logs.
        await axClearLogs()
        await GlobalAXLogger.shared.updateOperationDetails(commandID: nil, appName: nil) // Reset context

        return responseString
    }

    private static func setupLogging(for command: CommandEnvelope) async -> (Bool, AXLogDetailLevel) {
        // DIAGNOSTIC LOG: Print the received value of command.debugLogging
        fputs("CommandExecutor.setupLogging: Received command.debugLogging = \(command.debugLogging)\n", stderr)
        fflush(stderr) // Ensure it prints immediately for CLI debugging

        // Also log it via axDebugLog so it becomes part of the collected logs
        axDebugLog("[CommandExecutor.setupLogging] Received command.debugLogging = \(command.debugLogging)")

        let initialLoggingEnabled = await GlobalAXLogger.shared.isLoggingEnabled()
        let initialDetailLevel = await GlobalAXLogger.shared.getDetailLevel()

        if command.debugLogging {
            await GlobalAXLogger.shared.setLoggingEnabled(true)
            await GlobalAXLogger.shared.setDetailLevel(.verbose)
        }

        return (initialLoggingEnabled, initialDetailLevel)
    }

    private static func processCommand(command: CommandEnvelope, axorcist: AXorcist, debugCLI: Bool) async -> String {
        switch command.command {
        case .performAction:
            // Pass debugCLI to handler
            return await handlePerformActionCommand(command: command, axorcist: axorcist, debugCLI: debugCLI)

        case .getFocusedElement:
            // Pass debugCLI to handler
            return await handleSimpleCommand(command: command, axorcist: axorcist, debugCLI: debugCLI, executor: executeGetFocusedElement)

        case .getAttributes:
            // Pass debugCLI to handler
            return await handleSimpleCommand(command: command, axorcist: axorcist, debugCLI: debugCLI, executor: executeGetAttributes)

        case .query:
            // Pass debugCLI to handler
            return await handleSimpleCommand(command: command, axorcist: axorcist, debugCLI: debugCLI, executor: executeQuery)

        case .describeElement:
            // Pass debugCLI to handler
            return await handleSimpleCommand(command: command, axorcist: axorcist, debugCLI: debugCLI, executor: executeDescribeElement)

        case .extractText:
            // Pass debugCLI to handler
            return await handleSimpleCommand(command: command, axorcist: axorcist, debugCLI: debugCLI, executor: executeExtractText)

        case .collectAll:
            // For collectAll, the AXorcist library function directly returns the JSON string.
            // This function needs to be made aware of debugCLI if its *returned JSON string*
            // is to conditionally omit logs. This is a deeper change.
            // The debugCLI flag is primarily for the CommandExecutor's own response wrapping.
            // We are now modifying handleCollectAll to accept debugCLI.
            axDebugLog("CollectAll called. debugCLI=\(debugCLI). Passing to axorcist.handleCollectAll.")
            return await axorcist.handleCollectAll(
                for: command.application,
                locator: command.locator,
                maxDepth: command.maxDepth,
                requestedAttributes: command.attributes,
                outputFormat: command.outputFormat,
                commandId: command.commandId,
                debugCLI: debugCLI, // Pass the flag
                filterCriteria: command.filterCriteria // ADDED
            )

        case .batch:
            // Pass debugCLI to handler
            return await handleBatchCommand(command: command, axorcist: axorcist, debugCLI: debugCLI)

        case .ping:
            // Pass debugCLI to handler
            return await handlePingCommand(command: command, debugCLI: debugCLI)

        case .getElementAtPoint:
            // Pass debugCLI to handler
            return await handleNotImplementedCommand(command: command, message: "getElementAtPoint command not yet implemented", debugCLI: debugCLI)

        case .observe:
            // Pass debugCLI to handler
            return await handleObserveCommand(command: command, axorcist: axorcist, debugCLI: debugCLI)

        case .setFocusedValue:
            return await handleSimpleCommand(command: command, axorcist: axorcist, debugCLI: debugCLI, executor: executeSetFocusedValue)
        }
    }

    private static func handlePerformActionCommand(command: CommandEnvelope, axorcist: AXorcist, debugCLI: Bool) async -> String {
        guard let actionName = command.actionName else {
            let error = "Missing actionName for performAction"
            axErrorLog(error) // Log error
            // Conditionally include logs in error response based on debugCLI
            let errorResponse = HandlerResponse(data: nil, error: error)
            return await finalizeAndEncodeResponse(
                commandId: command.commandId,
                commandType: command.command.rawValue,
                handlerResponse: errorResponse,
                debugCLI: debugCLI,
                commandDebugLogging: command.debugLogging
            )
        }

        let handlerResponse = await executePerformAction(
            command: command,
            axorcist: axorcist,
            actionName: actionName
        )
        // Pass debugCLI to finalizeAndEncodeResponse
        return await finalizeAndEncodeResponse(
            commandId: command.commandId,
            commandType: command.command.rawValue,
            handlerResponse: handlerResponse,
            debugCLI: debugCLI,
            commandDebugLogging: command.debugLogging
        )
    }

    private static func handleSimpleCommand(
        command: CommandEnvelope,
        axorcist: AXorcist,
        debugCLI: Bool, // Added debugCLI
        executor: (CommandEnvelope, AXorcist) async -> HandlerResponse
    ) async -> String {
        let handlerResponse = await executor(command, axorcist)
        // Pass debugCLI and command.debugLogging to finalizeAndEncodeResponse
        return await finalizeAndEncodeResponse(
            commandId: command.commandId,
            commandType: command.command.rawValue,
            handlerResponse: handlerResponse,
            debugCLI: debugCLI,
            commandDebugLogging: command.debugLogging
        )
    }

    private static func handleBatchCommand(command: CommandEnvelope, axorcist: AXorcist, debugCLI: Bool) async -> String {
        // Batch response likely needs careful handling of debugCLI for its sub-responses
        // and the overall batch response.
        // Assuming executeBatch and its encoding handle this or need similar modifications.
        // For now, passing debugCLI down.
        axDebugLog("handleBatchCommand called with debugCLI: \(debugCLI). Further impl needed for log control in batch items.")
        let batchResponse = await executeBatch(
            command: command,
            axorcist: axorcist,
            debugCLI: debugCLI
        )
        // The top-level batchResponse might also need conditional logging.
        // If BatchQueryResponse has a debugLogs field:
        // var modifiedBatchResponse = batchResponse
        // if !debugCLI { modifiedBatchResponse.debugLogs = nil } // Example

        let jsonString = encodeToJson(batchResponse)
        let fallbackJson = """
        {"error": "Encoding batch response failed"}
        """
        return jsonString ?? fallbackJson
    }

    private static func handlePingCommand(command: CommandEnvelope, debugCLI: Bool) async -> String {
        axDebugLog("Ping command received. Responding with pong.")
        let pingHandlerResponse = HandlerResponse(
            data: nil,
            error: nil
        )
        // Pass debugCLI and command.debugLogging to finalizeAndEncodeResponse
        return await finalizeAndEncodeResponse(
            commandId: command.commandId,
            commandType: command.command.rawValue,
            handlerResponse: pingHandlerResponse,
            debugCLI: debugCLI,
            commandDebugLogging: command.debugLogging
        )
    }

    private static func handleNotImplementedCommand(command: CommandEnvelope, message: String, debugCLI: Bool) async -> String {
        let notImplementedResponse = HandlerResponse(
            data: nil,
            error: message
        )
        // Pass debugCLI and command.debugLogging to finalizeAndEncodeResponse
        return await finalizeAndEncodeResponse(
            commandId: command.commandId,
            commandType: command.command.rawValue,
            handlerResponse: notImplementedResponse,
            debugCLI: debugCLI,
            commandDebugLogging: command.debugLogging
        )
    }

    // MARK: - Command Execution Functions (Refactored: no logging params)

    private static func executePerformAction(
        command: CommandEnvelope,
        axorcist: AXorcist,
        actionName: String
    ) async -> HandlerResponse {
        var locator: Locator? = command.locator
        
        // If CommandEnvelope.pathHint (old [String] format) is valid and locator is nil, 
        // we create a default empty locator. However, we cannot directly use this old pathHint 
        // with the new JSONPathHintComponent system.
        // The expectation is that new-style path hints come via locator.rootElementPathHint.
        if let oldPathHint = command.pathHint, !oldPathHint.isEmpty, locator == nil {
            locator = Locator(criteria: []) // Create an empty locator
            axDebugLog("CommandExecutor: Created default empty locator because CommandEnvelope.pathHint (old format) was provided but locator was nil. This old pathHint will NOT be used for navigation.")
        }
        
        // If locator is still nil (no pathHint provided and no locator in command), return error
        guard var validLocator = locator else {
            let error = "Missing locator for performAction (and no old-format CommandEnvelope.pathHint to trigger default locator creation)"
            axErrorLog(error)
            return HandlerResponse(data: nil, error: error)
        }

        // If CommandEnvelope.pathHint ([String]?) is provided, AND locator.rootElementPathHint ([JSONPathHintComponent]?) is NOT,
        // this indicates an attempt to use the old path hint format. We log a warning as it won't be used by the new system.
        if let topLevelOldPathHint = command.pathHint, !topLevelOldPathHint.isEmpty, validLocator.rootElementPathHint == nil {
            axWarningLog("CommandExecutor: CommandEnvelope.pathHint (old [String] format) was provided, but locator.rootElementPathHint (new JSON format) is nil. The old format pathHint will NOT be used for navigation. Please update your query to use the new JSON format for rootElementPathHint within the locator object.")
            // DO NOT ASSIGN: validLocator.rootElementPathHint = topLevelOldPathHint // This would be a type error
        }

        return await axorcist.handlePerformAction(
            for: command.application,
            locator: validLocator,
            actionName: actionName,
            actionValue: command.actionValue,
            maxDepth: command.maxElements
        )
    }

    private static func executeGetFocusedElement(
        command: CommandEnvelope,
        axorcist: AXorcist
    ) async -> HandlerResponse {
        return await axorcist.handleGetFocusedElement(
            for: command.application,
            requestedAttributes: command.attributes
        )
    }

    private static func executeGetAttributes(
        command: CommandEnvelope,
        axorcist: AXorcist
    ) async -> HandlerResponse {
        var locator: Locator? = command.locator
        if let oldPathHint = command.pathHint, !oldPathHint.isEmpty, locator == nil {
            locator = Locator(criteria: [])
            axDebugLog("CommandExecutor: Created default empty locator for getAttributes because CommandEnvelope.pathHint (old format) was provided but locator was nil. This old pathHint will NOT be used.")
        }
        guard var validLocator = locator else {
            let error = "Missing locator for getAttributes"
            axErrorLog(error)
            return HandlerResponse(data: nil, error: error)
        }
        if let topLevelOldPathHint = command.pathHint, !topLevelOldPathHint.isEmpty, validLocator.rootElementPathHint == nil {
            axWarningLog("CommandExecutor: CommandEnvelope.pathHint (old [String] format) provided for getAttributes, but new JSON format (locator.rootElementPathHint) is nil. Old pathHint will NOT be used.")
        }
        return await axorcist.handleGetAttributes(
            for: command.application,
            locator: validLocator,
            requestedAttributes: command.attributes,
            maxDepth: command.maxDepth,
            outputFormat: command.outputFormat
        )
    }

    private static func executeQuery(
        command: CommandEnvelope,
        axorcist: AXorcist
    ) async -> HandlerResponse {
        var locator: Locator? = command.locator
        if let oldPathHint = command.pathHint, !oldPathHint.isEmpty, locator == nil {
            locator = Locator(criteria: [])
            axDebugLog("CommandExecutor: Created default empty locator for query because CommandEnvelope.pathHint (old format) was provided but locator was nil. This old pathHint will NOT be used.")
        }
        guard var validLocator = locator else {
            let error = "Missing locator for query"
            axErrorLog(error)
            return HandlerResponse(data: nil, error: error)
        }
        if let topLevelOldPathHint = command.pathHint, !topLevelOldPathHint.isEmpty, validLocator.rootElementPathHint == nil {
            axWarningLog("CommandExecutor: CommandEnvelope.pathHint (old [String] format) provided for query, but new JSON format (locator.rootElementPathHint) is nil. Old pathHint will NOT be used.")
        }
        return await axorcist.handleQuery(
            for: command.application,
            locator: validLocator,
            maxDepth: command.maxDepth,
            requestedAttributes: command.attributes,
            outputFormat: command.outputFormat
        )
    }

    private static func executeDescribeElement(
        command: CommandEnvelope,
        axorcist: AXorcist
    ) async -> HandlerResponse {
        var locator: Locator? = command.locator
        if let oldPathHint = command.pathHint, !oldPathHint.isEmpty, locator == nil {
            locator = Locator(criteria: [])
            axDebugLog("CommandExecutor: Created default empty locator for describeElement because CommandEnvelope.pathHint (old format) was provided but locator was nil. This old pathHint will NOT be used.")
        }
        guard var validLocator = locator else {
            let error = "Missing locator for describeElement"
            axErrorLog(error)
            return HandlerResponse(data: nil, error: error)
        }
        if let topLevelOldPathHint = command.pathHint, !topLevelOldPathHint.isEmpty, validLocator.rootElementPathHint == nil {
            axWarningLog("CommandExecutor: CommandEnvelope.pathHint (old [String] format) provided for describeElement, but new JSON format (locator.rootElementPathHint) is nil. Old pathHint will NOT be used.")
        }
        return await axorcist.handleDescribeElement(
            for: command.application,
            locator: validLocator,
            maxDepth: command.maxDepth,
            requestedAttributes: command.attributes,
            outputFormat: command.outputFormat
        )
    }

    private static func executeExtractText(
        command: CommandEnvelope,
        axorcist: AXorcist
    ) async -> HandlerResponse {
        var locator: Locator? = command.locator
        if let oldPathHint = command.pathHint, !oldPathHint.isEmpty, locator == nil {
            locator = Locator(criteria: [])
            axDebugLog("CommandExecutor: Created default empty locator for extractText because CommandEnvelope.pathHint (old format) was provided but locator was nil. This old pathHint will NOT be used.")
        }
        guard var validLocator = locator else {
            let error = "Missing locator for extractText"
            axErrorLog(error)
            return HandlerResponse(data: nil, error: error)
        }
        if let topLevelOldPathHint = command.pathHint, !topLevelOldPathHint.isEmpty, validLocator.rootElementPathHint == nil {
            axWarningLog("CommandExecutor: CommandEnvelope.pathHint (old [String] format) provided for extractText, but new JSON format (locator.rootElementPathHint) is nil. Old pathHint will NOT be used.")
        }
        return await axorcist.handleExtractText(
            for: command.application,
            locator: validLocator,
            maxDepth: command.maxDepth
        )
    }

    private static func executeBatch(
        command: CommandEnvelope,
        axorcist: AXorcist,
        debugCLI: Bool // Added debugCLI
    ) async -> BatchResponse {
        guard let subCommands = command.subCommands else {
            let error = "Missing subCommands for batch command"
            axErrorLog(error)
            // Conditionally include logs in BatchResponse for error case
            let logsToInclude = debugCLI ? await axGetLogsAsStrings(format: .text) : nil
            return BatchResponse(
                commandId: command.commandId,
                success: false,
                results: [],
                debugLogs: logsToInclude
            )
        }

        // AXorcist.handleBatchCommands was refactored to use GlobalAXLogger internally.
        // It no longer takes isDebugLoggingEnabled or currentDebugLogs.
        // It will manage its own sub-command logging context.
        let batchResults: [HandlerResponse] = await axorcist.handleBatchCommands(
            commandEnvelopes: subCommands, // Corrected parameter name
            batchCommandID: command.commandId 
        )

        let overallSuccess = batchResults.allSatisfy { $0.error == nil }

        let queryResults = batchResults.enumerated().map { index, handlerResp -> QueryResponse in
            let subCommandId = subCommands.indices.contains(index) ? subCommands[index].commandId : "sub_cmd_id_missing"
            let subCommandType = subCommands.indices.contains(index) ? subCommands[index].command.rawValue : "sub_cmd_type_missing"

            // HandlerResponse (handlerResp) no longer has debug_logs.
            // If sub-command specific logs are needed in QueryResponse,
            // GlobalAXLogger would need a mechanism to provide logs scoped to sub-operations,
            // or QueryResponse's debug_logs field should be populated by finalizeAndEncodeResponse logic if desired.
            // For now, individual QueryResponses in batch will not have scoped logs here.
            // The top-level BatchResponse will get all logs accumulated during the batch.
            return QueryResponse(
                commandId: subCommandId,
                success: handlerResp.error == nil,
                command: subCommandType,
                handlerResponse: handlerResp, // handlerResp.data, handlerResp.error
                debugLogs: nil // No individual debug logs here for sub-commands in this structure.
                // Logs will be part of the main BatchResponse.
            )
        }

        // Conditionally include logs in the final BatchResponse
        let finalLogsToInclude = debugCLI ? await axGetLogsAsStrings(format: .text) : nil
        return BatchResponse(
            commandId: command.commandId,
            success: overallSuccess,
            results: queryResults,
            debugLogs: finalLogsToInclude // All logs from the batch operation, conditional
        )
    }

    // MARK: - NEW COMMAND: setFocusedValue

    private static func executeSetFocusedValue(
        command: CommandEnvelope,
        axorcist: AXorcist
    ) async -> HandlerResponse {
        var locator: Locator? = command.locator
        if let oldPathHint = command.pathHint, !oldPathHint.isEmpty, locator == nil {
            locator = Locator(criteria: [])
            axDebugLog("CommandExecutor: Created default empty locator for setFocusedValue because CommandEnvelope.pathHint (old format) was provided but locator was nil. This old pathHint will NOT be used.")
        }
        guard var validLocator = locator else {
            let error = "Missing locator for setFocusedValue"
            axErrorLog(error)
            return HandlerResponse(data: nil, error: error)
        }
        if let topLevelOldPathHint = command.pathHint, !topLevelOldPathHint.isEmpty, validLocator.rootElementPathHint == nil {
            axWarningLog("CommandExecutor: CommandEnvelope.pathHint (old [String] format) provided for setFocusedValue, but new JSON format (locator.rootElementPathHint) is nil. Old pathHint will NOT be used.")
        }
        return await axorcist.handleSetFocusedValue(
            for: command.application,
            locator: validLocator,
            actionName: command.actionName ?? "AXSetValue",
            actionValue: command.actionValue
        )
    }

    // MARK: - Helper Functions

    private static func finalizeAndEncodeResponse(
        commandId: String,
        commandType: String,
        handlerResponse: HandlerResponse, // This is from AXorcist library
        debugCLI: Bool, // Added debugCLI
        commandDebugLogging: Bool // MODIFIED: Now non-optional Bool
    ) async -> String {
        let shouldIncludeLogs = debugCLI || commandDebugLogging
        fputs("[FEAR] shouldIncludeLogs: \(shouldIncludeLogs), debugCLI: \(debugCLI), cmdDebugLogging: \(commandDebugLogging)\n", stderr) // fputs DIAGNOSTIC
        axDebugLog("[finalizeAndEncodeResponse] shouldIncludeLogs: \(shouldIncludeLogs), debugCLI: \(debugCLI), cmdDebugLogging: \(commandDebugLogging)") // DIAGNOSTIC
        
        let logsToInclude: [String]?
        if shouldIncludeLogs {
            fputs("[FEAR] Attempting to fetch logs...\n", stderr) // fputs DIAGNOSTIC
            axDebugLog("[finalizeAndEncodeResponse] Attempting to fetch logs...") // DIAGNOSTIC
            logsToInclude = await GlobalAXLogger.shared.getLogsAsStrings(
                format: .text, 
                includeTimestamps: false, 
                includeLevels: false, 
                includeDetails: false,
                includeAppName: false,
                includeCommandID: false
            )
            fputs("[FEAR] Fetched logs. Count: \(logsToInclude?.count ?? -1)\n", stderr) // fputs DIAGNOSTIC
            axDebugLog("[finalizeAndEncodeResponse] Fetched logs. Count: \(logsToInclude?.count ?? -1)") // DIAGNOSTIC
        } else {
            fputs("[FEAR] Not fetching logs.\n", stderr) // fputs DIAGNOSTIC
            logsToInclude = nil
            axDebugLog("[finalizeAndEncodeResponse] Not fetching logs.") // DIAGNOSTIC
        }
        fflush(stderr) // Ensure all fputs are flushed

        // Use the specialized QueryResponse initializer that takes a HandlerResponse
        let response = QueryResponse(
            commandId: commandId,
            success: handlerResponse.error == nil, // Success is determined by error presence
            command: commandType,
            handlerResponse: handlerResponse, // Pass the whole HandlerResponse
            debugLogs: logsToInclude
        )

        let jsonString = encodeToJson(response)
        let fallbackJson = """
        {"error": "Encoding response failed"}
        """
        return jsonString ?? fallbackJson
    }

    private static func encodeToJson<T: Codable>(_ object: T) -> String? {
        let encoder = JSONEncoder()
        // encoder.outputFormatting = .prettyPrinted // Keep for debug, can be removed for prod

        do {
            let data = try encoder.encode(object)
            return String(data: data, encoding: .utf8)
        } catch {
            let errorDescription = "JSON ENCODING ERROR: \(error.localizedDescription). Details: \(error)"
            // Standard error logging for the CLI tool itself, not part of JSON response normally
            FileHandle.standardError.write(errorDescription.data(using: .utf8) ?? Data())
            axFatalLog("JSON ENCODING ERROR: \(error.localizedDescription). Details: \(error)") // Also log to GlobalAXLogger
            return nil
        }
    }

    // Placeholder for handleObserveCommand
    private static func handleObserveCommand(command: CommandEnvelope, axorcist: AXorcist, debugCLI: Bool) async -> String {
        axDebugLog("Observe command received by CommandExecutor. debugCLI: \(debugCLI)")

        guard let notifications = command.notifications, !notifications.isEmpty else {
            let errorMsg = "Missing or empty 'notifications' array for observe command."
            axErrorLog(errorMsg)
            return await finalizeAndEncodeResponse(
                commandId: command.commandId,
                commandType: command.command.rawValue,
                handlerResponse: HandlerResponse(data: nil, error: errorMsg),
                debugCLI: debugCLI,
                commandDebugLogging: command.debugLogging
            )
        }

        let includeDetails = command.includeElementDetails ?? []
        let watchChildren = command.watchChildren ?? false

        let observerSetupSuccess = await axorcist.handleObserve(
            for: command.application,
            notifications: notifications,
            includeElementDetails: includeDetails,
            watchChildren: watchChildren,
            commandId: command.commandId,
            debugCLI: debugCLI
        )

        if observerSetupSuccess {
            // Observer started successfully. Print initial success message to stdout.
            // Further notification data will be streamed directly to stdout by AXorcist.handleObserve's callback.
            
            let successResponsePayload: [String: AnyCodable] = [
                "commandId": AnyCodable(command.commandId),
                "command": AnyCodable(command.command.rawValue),
                "status": AnyCodable("observer_started"),
                "success": AnyCodable(true) // Indicate successful setup
            ]
            // let logs = await GlobalAXLogger.shared.getLogsAsStringsIfEnabled(format: .text)
            // No logs are added to this initial success message for observe, 
            // as the primary output is the stream of notifications.

            do {
                let jsonData = try JSONEncoder().encode(successResponsePayload)
                if let jsonString = String(data: jsonData, encoding: .utf8) {
                    // This will be the only JSON output from CommandExecutor for a successful observe setup.
                    // AXORCMain will need to ensure the process stays alive.
                    return jsonString
                } else {
                    let errorMsg = "{\"error\": \"Failed to encode initial success response for observe command.\"}"
                    fputs("\(errorMsg)\n", stderr)
                    fflush(stderr)
                    return errorMsg // Return error string
                }
            } catch {
                let errorMsg = "{\"error\": \"Exception encoding initial success response: \(error.localizedDescription)\"}"
                fputs("\(errorMsg)\n", stderr)
                fflush(stderr)
                return errorMsg // Return error string
            }

            // DO NOT CALL RunLoop.current.run() here.
            // AXORCMain will handle keeping the process alive.
        } else {
            // Failed to start observer
            let errorMsg = "Failed to start observer for application: \(command.application ?? "focused")"
            axErrorLog(errorMsg)
            return await finalizeAndEncodeResponse(
                commandId: command.commandId,
                commandType: command.command.rawValue,
                handlerResponse: HandlerResponse(data: nil, error: errorMsg),
                debugCLI: debugCLI,
                commandDebugLogging: command.debugLogging
            )
        }
    }
}
