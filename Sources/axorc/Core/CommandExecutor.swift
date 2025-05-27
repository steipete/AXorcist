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

@MainActor
struct CommandExecutor {

    @MainActor
    static func execute(
        command: CommandEnvelope,
        axorcist: AXorcist,
        debugCLI: Bool // This is from the --debug CLI flag
    ) -> String {
        // let (initialLoggingEnabled, initialDetailLevel) = setupLogging(for: command)
        // The main AXORCCommand.run() now sets the global logging based on --debug.
        // CommandExecutor.setupLogging can adjust detail level if command.debugLogging is true.
        let previousDetailLevel = setupDetailLevelForCommand(commandDebugLogging: command.debugLogging, cliDebug: debugCLI)

        defer {
            // Restore only the detail level if it was changed.
            if let prevLevel = previousDetailLevel {
                GlobalAXLogger.shared.detailLevel = prevLevel
            }
        }

        // GlobalAXLogger.shared.updateOperationDetails(commandID: command.commandId, appName: command.application) // Commented out for now

        axDebugLog("Executing command: \(command.command) (ID: \(command.commandId)), cmdDebug: \(command.debugLogging), cliDebug: \(debugCLI)")

        let responseString = processCommand(command: command, axorcist: axorcist, debugCLI: debugCLI)

        // Logs are cleared by AXORCMain after printing, if appropriate.
        // GlobalAXLogger.shared.updateOperationDetails(commandID: nil, appName: nil) // Commented out for now

        return responseString
    }

    // Simplified to only adjust detail level based on command specific flag, if CLI debug is on.
    private static func setupDetailLevelForCommand(commandDebugLogging: Bool, cliDebug: Bool) -> AXLogDetailLevel? {
        var previousDetailLevel: AXLogDetailLevel? = nil
        if cliDebug { // Only adjust if CLI debugging is already enabled
            if commandDebugLogging && GlobalAXLogger.shared.detailLevel != .verbose {
                previousDetailLevel = GlobalAXLogger.shared.detailLevel
                GlobalAXLogger.shared.detailLevel = .verbose
                axDebugLog("[CommandExecutor.setupDetailLevel] Upped detail level to verbose for this command.")
            }
        } else {
            // If CLI debug is not on, command.debugLogging by itself does not turn on logging here.
            // AXORCMain is the authority for enabling logging globally via --debug.
            // However, if command.debugLogging is true but CLI is not, we might want to enable JUST for this command?
            // For now, keeping it simple: CLI --debug is master switch.
        }
        return previousDetailLevel
    }

    @MainActor
    private static func processCommand(command: CommandEnvelope, axorcist: AXorcist, debugCLI: Bool) -> String {
        switch command.command {
        case .performAction:
            return handlePerformActionCommand(command: command, axorcist: axorcist, debugCLI: debugCLI)

        case .getFocusedElement:
            return handleSimpleCommand(command: command, axorcist: axorcist, debugCLI: debugCLI, executor: executeGetFocusedElement)

        case .getAttributes:
            return handleSimpleCommand(command: command, axorcist: axorcist, debugCLI: debugCLI, executor: executeGetAttributes)

        case .query:
            return handleSimpleCommand(command: command, axorcist: axorcist, debugCLI: debugCLI, executor: executeQuery)

        case .describeElement:
            return handleSimpleCommand(command: command, axorcist: axorcist, debugCLI: debugCLI, executor: executeDescribeElement)

        case .extractText:
            return handleSimpleCommand(command: command, axorcist: axorcist, debugCLI: debugCLI, executor: executeExtractText)

        case .collectAll:
            axDebugLog("CollectAll called. debugCLI=\(debugCLI). Passing to axorcist.handleCollectAll.")
            guard let axCommand = command.command.toAXCommand(commandEnvelope: command) else {
                 axErrorLog("Failed to convert CollectAll to AXCommand")
                 let errorResponse = HandlerResponse(data: nil, error: "Internal error: Failed to create AXCommand for CollectAll")
                 return finalizeAndEncodeResponse(commandId: command.commandId, commandType: command.command.rawValue, handlerResponse: errorResponse, debugCLI: debugCLI, commandDebugLogging: command.debugLogging)
            }
            let axResponse = axorcist.runCommand(AXCommandEnvelope(commandID: command.commandId, command: axCommand))
            let handlerResponse: HandlerResponse
            if axResponse.status == "success" {
                handlerResponse = HandlerResponse(data: axResponse.payload, error: nil)
            } else {
                handlerResponse = HandlerResponse(data: nil, error: axResponse.error?.message ?? "CollectAll failed")
            }
            return finalizeAndEncodeResponse(commandId: command.commandId, commandType: command.command.rawValue, handlerResponse: handlerResponse, debugCLI: debugCLI, commandDebugLogging: command.debugLogging)

        case .batch:
            return handleBatchCommand(command: command, axorcist: axorcist, debugCLI: debugCLI)

        case .ping:
            return handlePingCommand(command: command, debugCLI: debugCLI)

        case .getElementAtPoint:
            guard let axCommand = command.command.toAXCommand(commandEnvelope: command) else {
                 axErrorLog("Failed to convert GetElementAtPoint to AXCommand")
                 let errorResponse = HandlerResponse(data: nil, error: "Internal error: Failed to create AXCommand for GetElementAtPoint")
                 return finalizeAndEncodeResponse(commandId: command.commandId, commandType: command.command.rawValue, handlerResponse: errorResponse, debugCLI: debugCLI, commandDebugLogging: command.debugLogging)
            }
            let axResponse = axorcist.runCommand(AXCommandEnvelope(commandID: command.commandId, command: axCommand))
            let handlerResponse = HandlerResponse(from: axResponse)
            return finalizeAndEncodeResponse(commandId: command.commandId, commandType: command.command.rawValue, handlerResponse: handlerResponse, debugCLI: debugCLI, commandDebugLogging: command.debugLogging)

        case .observe:
            return handleObserveCommand(command: command, axorcist: axorcist, debugCLI: debugCLI)

        case .setFocusedValue:
            return handleSimpleCommand(command: command, axorcist: axorcist, debugCLI: debugCLI, executor: executeSetFocusedValue)
            
        case .stopObservation, .isProcessTrusted, .isAXFeatureEnabled, .setNotificationHandler, .removeNotificationHandler, .getElementDescription:
            return handleNotImplementedCommand(command: command, message: "Command '\(command.command.rawValue)' is not yet implemented", debugCLI: debugCLI)
        }
    }

    @MainActor
    private static func handlePerformActionCommand(command: CommandEnvelope, axorcist: AXorcist, debugCLI: Bool) -> String {
        guard command.actionName != nil else {
            let error = "Missing action details for performAction"
            axErrorLog(error)
            let errorResponse = HandlerResponse(data: nil, error: error)
            return finalizeAndEncodeResponse(
                commandId: command.commandId,
                commandType: command.command.rawValue,
                handlerResponse: errorResponse,
                debugCLI: debugCLI,
                commandDebugLogging: command.debugLogging
            )
        }

        guard let axCommand = command.command.toAXCommand(commandEnvelope: command) else {
            axErrorLog("Failed to convert PerformAction to AXCommand")
            let errorResponse = HandlerResponse(data: nil, error: "Internal error: Failed to create AXCommand for PerformAction")
            return finalizeAndEncodeResponse(commandId: command.commandId, commandType: command.command.rawValue, handlerResponse: errorResponse, debugCLI: debugCLI, commandDebugLogging: command.debugLogging)
        }
        
        let axResponse = axorcist.runCommand(AXCommandEnvelope(commandID: command.commandId, command: axCommand))
        let handlerResponse = HandlerResponse(from: axResponse)

        return finalizeAndEncodeResponse(
            commandId: command.commandId,
            commandType: command.command.rawValue,
            handlerResponse: handlerResponse,
            debugCLI: debugCLI,
            commandDebugLogging: command.debugLogging
        )
    }

    @MainActor
    private static func handleSimpleCommand(
        command: CommandEnvelope,
        axorcist: AXorcist,
        debugCLI: Bool,
        executor: (CommandEnvelope, AXorcist) -> HandlerResponse
    ) -> String {
        let handlerResponse = executor(command, axorcist)
        return finalizeAndEncodeResponse(
            commandId: command.commandId,
            commandType: command.command.rawValue,
            handlerResponse: handlerResponse,
            debugCLI: debugCLI,
            commandDebugLogging: command.debugLogging
        )
    }

    @MainActor
    private static func handleBatchCommand(command: CommandEnvelope, axorcist: AXorcist, debugCLI: Bool) -> String {
        axDebugLog("handleBatchCommand called with debugCLI: \(debugCLI).")
        
        guard command.command == .batch else {
            let errorMsg = "Batch command structure is incorrect or not a batch command type."
            axErrorLog(errorMsg)
            let errorResponse = HandlerResponse(data: nil, error: errorMsg)
            return finalizeAndEncodeResponse(commandId: command.commandId, commandType: CommandType.batch.rawValue, handlerResponse: errorResponse, debugCLI: debugCLI, commandDebugLogging: command.debugLogging)
        }

        guard let axBatchCommand = command.command.toAXCommand(commandEnvelope: command) else {
             axErrorLog("Failed to convert Batch to AXCommand")
             let errorResponse = HandlerResponse(data: nil, error: "Internal error: Failed to create AXCommand for Batch")
             return finalizeAndEncodeResponse(commandId: command.commandId, commandType: CommandType.batch.rawValue, handlerResponse: errorResponse, debugCLI: debugCLI, commandDebugLogging: command.debugLogging)
        }

        let axResponse = axorcist.runCommand(AXCommandEnvelope(commandID: command.commandId, command: axBatchCommand))
        
        var finalResponseObject: BatchQueryResponse
        var logsForResponse: [String]? = nil

        if axResponse.status == "success" {
            if let batchPayload = axResponse.payload?.value as? BatchResponsePayload {
                finalResponseObject = BatchQueryResponse(commandId: command.commandId, status: "success", data: batchPayload.results, errors: batchPayload.errors, debugLogs: nil)
            } else {
                finalResponseObject = BatchQueryResponse(commandId: command.commandId, status: "error", message: "Batch success but payload was not BatchResponsePayload", debugLogs: nil)
            }
        } else {
            let errorMessage = axResponse.error?.message ?? "Batch operation failed with unknown error."
            if let batchPayload = axResponse.payload?.value as? BatchResponsePayload {
                 finalResponseObject = BatchQueryResponse(commandId: command.commandId, status: "error", message: errorMessage, data: batchPayload.results, errors: batchPayload.errors, debugLogs: nil)
            } else {
                 finalResponseObject = BatchQueryResponse(commandId: command.commandId, status: "error", message: errorMessage, debugLogs: nil)
            }
        }
        
        if debugCLI || command.debugLogging {
            logsForResponse = axGetLogsAsStrings()
            finalResponseObject.debugLogs = logsForResponse
        }

        return encodeToJson(finalResponseObject) ?? "{\"error\": \"Encoding batch response failed\", \"commandId\": \"\(command.commandId)\"}"
    }

    private static func handlePingCommand(command: CommandEnvelope, debugCLI: Bool) -> String {
        axDebugLog("Ping command received. Responding with pong.")
        let pingHandlerResponse = HandlerResponse(data: AnyCodable("pong"), error: nil)
        return finalizeAndEncodeResponse(
            commandId: command.commandId,
            commandType: command.command.rawValue,
            handlerResponse: pingHandlerResponse,
            debugCLI: debugCLI,
            commandDebugLogging: command.debugLogging
        )
    }

    private static func handleNotImplementedCommand(command: CommandEnvelope, message: String, debugCLI: Bool) -> String {
        let notImplementedResponse = HandlerResponse(data: nil, error: message)
        return finalizeAndEncodeResponse(
            commandId: command.commandId,
            commandType: command.command.rawValue,
            handlerResponse: notImplementedResponse,
            debugCLI: debugCLI,
            commandDebugLogging: command.debugLogging
        )
    }

    @MainActor
    private static func handleObserveCommand(command: CommandEnvelope, axorcist: AXorcist, debugCLI: Bool) -> String {
        guard let axObserveCommand = command.command.toAXCommand(commandEnvelope: command) else {
            axErrorLog("Failed to convert Observe to AXCommand")
            let errorResponse = HandlerResponse(data: nil, error: "Internal error: Failed to create AXCommand for Observe")
            return finalizeAndEncodeResponse(commandId: command.commandId, commandType: command.command.rawValue, handlerResponse: errorResponse, debugCLI: debugCLI, commandDebugLogging: command.debugLogging)
        }
        
        let axResponse = axorcist.runCommand(AXCommandEnvelope(commandID: command.commandId, command: axObserveCommand))
        let handlerResponse = HandlerResponse(from: axResponse)
        
        return finalizeAndEncodeResponse(
            commandId: command.commandId,
            commandType: command.command.rawValue,
            handlerResponse: handlerResponse,
            debugCLI: debugCLI,
            commandDebugLogging: command.debugLogging
        )
    }

    // MARK: - Command Execution Functions (now call AXorcist.runCommand)

    @MainActor
    private static func executeQuery(command: CommandEnvelope, axorcist: AXorcist) -> HandlerResponse {
        guard let axQueryCommand = command.command.toAXCommand(commandEnvelope: command) else {
            axErrorLog("Failed to convert Query to AXCommand")
            return HandlerResponse(data: nil, error: "Internal error: Failed to create AXCommand for Query")
        }
        
        let axResponse = axorcist.runCommand(AXCommandEnvelope(commandID: command.commandId, command: axQueryCommand))
        return HandlerResponse(from: axResponse)
    }

    @MainActor
    private static func executeGetFocusedElement(command: CommandEnvelope, axorcist: AXorcist) -> HandlerResponse {
         guard let axGetFocusedCmd = command.command.toAXCommand(commandEnvelope: command) else {
            axErrorLog("Failed to convert GetFocusedElement to AXCommand")
            return HandlerResponse(data: nil, error: "Internal error: Failed to create AXCommand for GetFocusedElement")
        }
        let axResponse = axorcist.runCommand(AXCommandEnvelope(commandID: command.commandId, command: axGetFocusedCmd))
        return HandlerResponse(from: axResponse)
    }

    @MainActor
    private static func executeGetAttributes(command: CommandEnvelope, axorcist: AXorcist) -> HandlerResponse {
        guard let axGetAttrsCmd = command.command.toAXCommand(commandEnvelope: command) else {
            axErrorLog("Failed to convert GetAttributes to AXCommand")
            return HandlerResponse(data: nil, error: "Internal error: Failed to create AXCommand for GetAttributes")
        }
        let axResponse = axorcist.runCommand(AXCommandEnvelope(commandID: command.commandId, command: axGetAttrsCmd))
        return HandlerResponse(from: axResponse)
    }

    @MainActor
    private static func executeDescribeElement(command: CommandEnvelope, axorcist: AXorcist) -> HandlerResponse {
        guard let axDescribeCmd = command.command.toAXCommand(commandEnvelope: command) else {
            axErrorLog("Failed to convert DescribeElement to AXCommand")
            return HandlerResponse(data: nil, error: "Internal error: Failed to create AXCommand for DescribeElement")
        }
        let axResponse = axorcist.runCommand(AXCommandEnvelope(commandID: command.commandId, command: axDescribeCmd))
        return HandlerResponse(from: axResponse)
    }

    @MainActor
    private static func executeExtractText(command: CommandEnvelope, axorcist: AXorcist) -> HandlerResponse {
        guard let axExtractCmd = command.command.toAXCommand(commandEnvelope: command) else {
            axErrorLog("Failed to convert ExtractText to AXCommand")
            return HandlerResponse(data: nil, error: "Internal error: Failed to create AXCommand for ExtractText")
        }
        let axResponse = axorcist.runCommand(AXCommandEnvelope(commandID: command.commandId, command: axExtractCmd))
        return HandlerResponse(from: axResponse)
    }
    
    @MainActor
    private static func executeSetFocusedValue(command: CommandEnvelope, axorcist: AXorcist) -> HandlerResponse {
        guard let axSetFocusedValueCmd = command.command.toAXCommand(commandEnvelope: command) else {
            axErrorLog("Failed to convert SetFocusedValue to AXCommand")
            return HandlerResponse(data: nil, error: "Internal error: Failed to create AXCommand for SetFocusedValue")
        }
        let axResponse = axorcist.runCommand(AXCommandEnvelope(commandID: command.commandId, command: axSetFocusedValueCmd))
        return HandlerResponse(from: axResponse)
    }

    // MARK: - Response Finalization

    private static func finalizeAndEncodeResponse(
        commandId: String,
        commandType: String,
        handlerResponse: HandlerResponse,
        debugCLI: Bool,
        commandDebugLogging: Bool
    ) -> String {
        let dataForResponse: AnyCodable?
        if let axElement = handlerResponse.data?.value as? AXElement {
            axDebugLog("finalizeAndEncodeResponse: handlerResponse.data contained AXElement. Converting to AXElementForEncoding.")
            dataForResponse = AnyCodable(AXElementForEncoding(from: axElement))
        } else if handlerResponse.data != nil {
            axDebugLog("finalizeAndEncodeResponse: handlerResponse.data was AnyCodable but not AXElement. Passing through. Type: \(type(of: handlerResponse.data!.value))")
            dataForResponse = handlerResponse.data // Pass through other AnyCodable types directly
        } else {
            axDebugLog("finalizeAndEncodeResponse: handlerResponse.data was nil.")
            dataForResponse = nil
        }

        var queryResponse = GenericQueryResponse(
            commandId: commandId,
            commandType: commandType,
            status: handlerResponse.error == nil ? "success" : "error",
            data: dataForResponse, // Use the potentially converted data
            message: handlerResponse.error
        )

        if debugCLI || commandDebugLogging {
            queryResponse.debugLogs = axGetLogsAsStrings()
        } else {
            queryResponse.debugLogs = nil
        }

        let jsonString = encodeToJson(queryResponse)
        let fallbackJson = """
        {"commandId": "\(commandId)", "commandType": "\(commandType)", "status": "error", "message": "Encoding response failed"}
        """
        return jsonString ?? fallbackJson
    }

    private static func encodeToJson<T: Codable>(_ value: T) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data = try encoder.encode(value)
            return String(data: data, encoding: .utf8)
        } catch {
            let errorMsg = "JSON Encoding Error for type \(String(describing: T.self)): \(error.localizedDescription)"
            fputs("ERROR: \(errorMsg)\n", stderr)
            GlobalAXLogger.shared.log(AXLogEntry(level: .error, message: errorMsg, details: ["error_details": AnyCodable(error.localizedDescription)]))

            if let encodingError = error as? EncodingError {
                let detailDesc = encodingError.detailedDescription
                fputs("ERROR EncodingError Details: \(detailDesc)\n", stderr)
                GlobalAXLogger.shared.log(AXLogEntry(level: .error, message: "EncodingError Details: \(detailDesc)"))
            }
            fflush(stderr)
            return nil
        }
    }
}

// CommandEnvelope.CommandType to AXCommand conversion
extension CommandType {
    func toAXCommand(commandEnvelope: CommandEnvelope) -> AXCommand? {
        switch self {
        case .query:
            let effectiveLocator = commandEnvelope.locator ?? Locator(criteria: [])
            return .query(QueryCommand(
                appIdentifier: commandEnvelope.application,
                locator: Locator(
                    matchAll: effectiveLocator.matchAll,
                    criteria: effectiveLocator.criteria,
                    rootElementPathHint: effectiveLocator.rootElementPathHint,
                    descendantCriteria: effectiveLocator.descendantCriteria,
                    requireAction: effectiveLocator.requireAction,
                    computedNameContains: effectiveLocator.computedNameContains,
                    debugPathSearch: commandEnvelope.locator?.debugPathSearch
                ),
                attributesToReturn: commandEnvelope.attributes,
                maxDepthForSearch: commandEnvelope.maxDepth ?? 10,
                includeChildrenBrief: commandEnvelope.includeChildrenBrief
            ))
        case .performAction:
            guard let actionName = commandEnvelope.actionName else { return nil }
            return .performAction(PerformActionCommand(
                appIdentifier: commandEnvelope.application,
                locator: commandEnvelope.locator ?? Locator(criteria: []),
                action: actionName,
                value: commandEnvelope.actionValue,
                maxDepthForSearch: commandEnvelope.maxDepth ?? 10
            ))
        case .getAttributes:
            return .getAttributes(GetAttributesCommand(
                appIdentifier: commandEnvelope.application,
                locator: commandEnvelope.locator ?? Locator(criteria: []),
                attributes: commandEnvelope.attributes ?? [],
                maxDepthForSearch: commandEnvelope.maxDepth ?? 10
            ))
        case .describeElement:
            return .describeElement(DescribeElementCommand(
                appIdentifier: commandEnvelope.application,
                locator: commandEnvelope.locator ?? Locator(criteria: []),
                depth: commandEnvelope.maxDepth ?? 3,
                includeIgnored: commandEnvelope.includeIgnoredElements ?? false,
                maxSearchDepth: commandEnvelope.maxDepth ?? 10
            ))
        case .extractText:
            return .extractText(ExtractTextCommand(
                appIdentifier: commandEnvelope.application,
                locator: commandEnvelope.locator ?? Locator(criteria: []),
                maxDepthForSearch: commandEnvelope.maxDepth ?? 10,
                includeChildren: commandEnvelope.includeChildrenInText ?? false,
                maxDepth: commandEnvelope.maxDepth
            ))
        case .collectAll:
            return .collectAll(CollectAllCommand(
                appIdentifier: commandEnvelope.application,
                attributesToReturn: commandEnvelope.attributes,
                maxDepth: commandEnvelope.maxDepth ?? 10,
                filterCriteria: commandEnvelope.filterCriteria,
                valueFormatOption: ValueFormatOption.smart
            ))
        case .batch:
            guard let batchSubCommands = commandEnvelope.subCommands else {
                axErrorLog("toAXCommand: Batch command missing subCommands in CommandEnvelope.")
                return nil
            }
            let axSubCommands = batchSubCommands.compactMap { subCmdEnv -> AXBatchCommand.SubCommandEnvelope? in
                guard let axSubCmd = subCmdEnv.command.toAXCommand(commandEnvelope: subCmdEnv) else {
                    axErrorLog("toAXCommand: Failed to convert subCommand '\(subCmdEnv.commandId)' of type '\(subCmdEnv.command.rawValue)' to AXSubCommand.")
                    return nil
                }
                return AXBatchCommand.SubCommandEnvelope(commandID: subCmdEnv.commandId, command: axSubCmd)
            }
            if axSubCommands.count != batchSubCommands.count {
                axErrorLog("toAXCommand: Some subCommands in batch failed to convert. Original: \(batchSubCommands.count), Converted: \(axSubCommands.count)")
            }
            return .batch(AXBatchCommand(commands: axSubCommands))
            
        case .setFocusedValue:
            guard let value = commandEnvelope.actionValue?.value as? String else { 
                 axErrorLog("toAXCommand: SetFocusedValue missing string value in actionValue or wrong type.")
                return nil 
            }
            return .setFocusedValue(SetFocusedValueCommand(
                appIdentifier: commandEnvelope.application,
                locator: commandEnvelope.locator ?? Locator(criteria: []),
                value: value,
                maxDepthForSearch: commandEnvelope.maxDepth ?? 10
            ))
            
        case .getElementAtPoint:
            guard let point = commandEnvelope.point else {
                axErrorLog("toAXCommand: GetElementAtPoint missing point.")
                return nil
            }
            return .getElementAtPoint(GetElementAtPointCommand(
                point: point,
                appIdentifier: commandEnvelope.application,
                pid: commandEnvelope.pid,
                attributesToReturn: commandEnvelope.attributes,
                includeChildrenBrief: commandEnvelope.includeChildrenBrief
            ))
            
        case .getFocusedElement:
            return .getFocusedElement(GetFocusedElementCommand(
                appIdentifier: commandEnvelope.application,
                attributesToReturn: commandEnvelope.attributes,
                includeChildrenBrief: commandEnvelope.includeChildrenBrief
            ))
            
        case .observe:
            guard let notificationsList = commandEnvelope.notifications, !notificationsList.isEmpty else {
                axErrorLog("toAXCommand: Observe missing notifications list.")
                return nil
            }
            guard let firstNotificationName = notificationsList.first,
                  let axNotification = AXNotification(rawValue: firstNotificationName) else {
                axErrorLog("toAXCommand: Invalid or unsupported notification name: \(notificationsList.first ?? "nil") for observe command.")
                return nil
            }
            return .observe(ObserveCommand(
                appIdentifier: commandEnvelope.application,
                locator: commandEnvelope.locator,
                notifications: notificationsList,
                includeDetails: true,
                watchChildren: commandEnvelope.watchChildren ?? false,
                notificationName: axNotification,
                includeElementDetails: commandEnvelope.includeElementDetails,
                maxDepthForSearch: commandEnvelope.maxDepth ?? 10
            ))
            
        case .ping:
            return nil
            
        case .stopObservation:
            return nil
            
        case .isProcessTrusted:
            return nil
            
        case .isAXFeatureEnabled:
            return nil
            
        case .setNotificationHandler:
            return nil
            
        case .removeNotificationHandler:
            return nil
            
        case .getElementDescription:
            return nil
        }
    }
}

// Extension for EncodingError details
protocol CodingPathProvider {
    var codingPath: [CodingKey] { get }
}

extension EncodingError.Context: CodingPathProvider {}
// For DecodingError as well if needed later
// extension DecodingError.Context: CodingPathProvider {}

extension EncodingError {
    var detailedDescription: String {
        switch self {
        case .invalidValue(let value, let context):
            return "InvalidValue: '\(value)' attempting to encode at path '\(context.codingPathString)'. Debug: \(context.debugDescription)"
        @unknown default:
            return "Unknown encoding error. Localized: \(self.localizedDescription)"
        }
    }
}

// Helper for CodingPathProvider to get a string representation
extension CodingPathProvider {
    var codingPathString: String {
        codingPath.map { $0.stringValue }.joined(separator: ".")
    }
}
