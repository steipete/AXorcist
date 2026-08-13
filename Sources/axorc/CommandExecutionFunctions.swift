// CommandExecutionFunctions.swift - Individual command execution functions

import AXorcist
import Foundation

// MARK: - Command Execution Functions (now call AXorcist.runCommand)

@MainActor
func executeQuery(
    command: CommandEnvelope,
    axorcist: AXorcist,
    traversalOptions: AXTraversalOptions) -> HandlerResponse
{
    guard let axQueryCommand = command.command.toAXCommand(commandEnvelope: command) else {
        axErrorLog("Failed to convert Query to AXCommand")
        return HandlerResponse(data: nil, error: "Internal error: Failed to create AXCommand for Query")
    }

    let axResponse = axorcist.runCommand(
        AXCommandEnvelope(commandID: command.commandId, command: axQueryCommand),
        traversalOptions: traversalOptions)
    return HandlerResponse(from: axResponse)
}

@MainActor
func executeGetFocusedElement(
    command: CommandEnvelope,
    axorcist: AXorcist,
    traversalOptions: AXTraversalOptions) -> HandlerResponse
{
    guard let axGetFocusedCmd = command.command.toAXCommand(commandEnvelope: command) else {
        axErrorLog("Failed to convert GetFocusedElement to AXCommand")
        return HandlerResponse(data: nil, error: "Internal error: Failed to create AXCommand for GetFocusedElement")
    }
    let axResponse = axorcist.runCommand(
        AXCommandEnvelope(commandID: command.commandId, command: axGetFocusedCmd),
        traversalOptions: traversalOptions)
    return HandlerResponse(from: axResponse)
}

@MainActor
func executeGetAttributes(
    command: CommandEnvelope,
    axorcist: AXorcist,
    traversalOptions: AXTraversalOptions) -> HandlerResponse
{
    guard let axGetAttrsCmd = command.command.toAXCommand(commandEnvelope: command) else {
        axErrorLog("Failed to convert GetAttributes to AXCommand")
        return HandlerResponse(data: nil, error: "Internal error: Failed to create AXCommand for GetAttributes")
    }
    let axResponse = axorcist.runCommand(
        AXCommandEnvelope(commandID: command.commandId, command: axGetAttrsCmd),
        traversalOptions: traversalOptions)
    return HandlerResponse(from: axResponse)
}

@MainActor
func executeDescribeElement(
    command: CommandEnvelope,
    axorcist: AXorcist,
    traversalOptions: AXTraversalOptions) -> HandlerResponse
{
    guard let axDescribeCmd = command.command.toAXCommand(commandEnvelope: command) else {
        axErrorLog("Failed to convert DescribeElement to AXCommand")
        return HandlerResponse(data: nil, error: "Internal error: Failed to create AXCommand for DescribeElement")
    }
    let axResponse = axorcist.runCommand(
        AXCommandEnvelope(commandID: command.commandId, command: axDescribeCmd),
        traversalOptions: traversalOptions)
    return HandlerResponse(from: axResponse)
}

@MainActor
func executeExtractText(
    command: CommandEnvelope,
    axorcist: AXorcist,
    traversalOptions: AXTraversalOptions) -> HandlerResponse
{
    guard let axExtractCmd = command.command.toAXCommand(commandEnvelope: command) else {
        axErrorLog("Failed to convert ExtractText to AXCommand")
        return HandlerResponse(data: nil, error: "Internal error: Failed to create AXCommand for ExtractText")
    }
    let axResponse = axorcist.runCommand(
        AXCommandEnvelope(commandID: command.commandId, command: axExtractCmd),
        traversalOptions: traversalOptions)
    return HandlerResponse(from: axResponse)
}

@MainActor
func executePerformAction(
    command: CommandEnvelope,
    axorcist: AXorcist,
    traversalOptions: AXTraversalOptions) -> HandlerResponse
{
    guard let axPerformCmd = command.command.toAXCommand(commandEnvelope: command) else {
        axErrorLog("Failed to convert PerformAction to AXCommand")
        return HandlerResponse(data: nil, error: "Internal error: Failed to create AXCommand for PerformAction")
    }
    let axResponse = axorcist.runCommand(
        AXCommandEnvelope(commandID: command.commandId, command: axPerformCmd),
        traversalOptions: traversalOptions)
    return HandlerResponse(from: axResponse)
}
