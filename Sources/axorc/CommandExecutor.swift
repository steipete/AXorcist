// CommandExecutor.swift - Main command executor that coordinates command processing

import AppKit // For NSRunningApplication
import AXorcist
import Foundation

@MainActor
struct CommandExecutor {

    @MainActor
    static func execute(
        command: CommandEnvelope,
        axorcist: AXorcist,
        debugCLI: Bool // This is from the --debug CLI flag
    ) -> String {
        // The main AXORCCommand.run() now sets the global logging based on --debug.
        // CommandExecutor.setupLogging can adjust detail level if command.debugLogging is true.
        let previousDetailLevel = setupDetailLevelForCommand(commandDebugLogging: command.debugLogging, cliDebug: debugCLI)

        defer {
            // Restore only the detail level if it was changed.
            if let prevLevel = previousDetailLevel {
                GlobalAXLogger.shared.detailLevel = prevLevel
            }
        }

        axDebugLog("Executing command: \(command.command) (ID: \(command.commandId)), cmdDebug: \(command.debugLogging), cliDebug: \(debugCLI)")

        let responseString = processCommand(command: command, axorcist: axorcist, debugCLI: debugCLI)

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

        case .getElementAtPoint:
            return handleSimpleCommand(command: command, axorcist: axorcist, debugCLI: debugCLI) { cmd, ax in
                guard let axCmd = cmd.command.toAXCommand(commandEnvelope: cmd) else {
                    axErrorLog("Failed to convert GetElementAtPoint to AXCommand")
                    return HandlerResponse(data: nil, error: "Internal error: Failed to create AXCommand for GetElementAtPoint")
                }
                let axResponse = ax.runCommand(AXCommandEnvelope(commandID: cmd.commandId, command: axCmd))
                return HandlerResponse(from: axResponse)
            }

        case .setFocusedValue:
            return handleSimpleCommand(command: command, axorcist: axorcist, debugCLI: debugCLI) { cmd, ax in
                guard let axCmd = cmd.command.toAXCommand(commandEnvelope: cmd) else {
                    axErrorLog("Failed to convert SetFocusedValue to AXCommand")
                    return HandlerResponse(data: nil, error: "Internal error: Failed to create AXCommand for SetFocusedValue")
                }
                let axResponse = ax.runCommand(AXCommandEnvelope(commandID: cmd.commandId, command: axCmd))
                return HandlerResponse(from: axResponse)
            }

        case .ping:
            return handlePingCommand(command: command, debugCLI: debugCLI)

        case .batch:
            return handleBatchCommand(command: command, axorcist: axorcist, debugCLI: debugCLI)

        case .observe:
            return handleObserveCommand(command: command, axorcist: axorcist, debugCLI: debugCLI)

        case .stopObservation:
            // Stop all observations through AXObserverCenter
            AXObserverCenter.shared.removeAllObservers()
            let stopResponse = FinalResponse(
                commandId: command.commandId,
                commandType: command.command.rawValue,
                status: "success",
                data: AnyCodable("All observations stopped"),
                error: nil,
                debugLogs: debugCLI || command.debugLogging ? axGetLogsAsStrings() : nil
            )
            return encodeToJson(stopResponse) ?? "{\"error\": \"Encoding stopObservation response failed\", \"commandId\": \"\(command.commandId)\"}"

        case .isProcessTrusted:
            let trustedResponse = ProcessTrustedResponse(
                commandId: command.commandId,
                status: "success",
                trusted: AXIsProcessTrusted()
            )
            return encodeToJson(trustedResponse) ?? "{\"error\": \"Encoding isProcessTrusted response failed\", \"commandId\": \"\(command.commandId)\"}"

        case .isAXFeatureEnabled:
            let axEnabled = AXIsProcessTrustedWithOptions(nil)
            let featureEnabledResponse = AXFeatureEnabledResponse(
                commandId: command.commandId,
                status: "success",
                enabled: axEnabled
            )
            return encodeToJson(featureEnabledResponse) ?? "{\"error\": \"Encoding isAXFeatureEnabled response failed\", \"commandId\": \"\(command.commandId)\"}"

        case .setNotificationHandler:
            return handleNotImplementedCommand(command: command, message: "setNotificationHandler is not implemented in axorc", debugCLI: debugCLI)

        case .removeNotificationHandler:
            return handleNotImplementedCommand(command: command, message: "removeNotificationHandler is not implemented in axorc", debugCLI: debugCLI)

        case .getElementDescription:
            return handleNotImplementedCommand(command: command, message: "getElementDescription is not implemented in axorc", debugCLI: debugCLI)
        }
    }
}