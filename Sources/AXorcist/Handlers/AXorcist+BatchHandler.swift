// AXorcist+BatchHandler.swift - Batch processing operations

import AppKit
import ApplicationServices
import CoreGraphics // For CGPoint, potentially used by getElementAtPoint logic
import Foundation

// GlobalAXLogger and AXUtilities are assumed to be available

// MARK: - Batch Processing Handler Extension
extension AXorcist {

    @MainActor
    private func prepareLocator(for subCommandEnvelope: CommandEnvelope, existingLocator: Locator?) -> Locator? {
        guard let newLocator = existingLocator else {
            if let oldPathHint = subCommandEnvelope.pathHint, !oldPathHint.isEmpty {
                axWarningLog("SubCommand \(subCommandEnvelope.commandId) has a CommandEnvelope.pathHint (old [String] format) but no base locator. This old pathHint will NOT be used. Provide path hints via locator.rootElementPathHint in JSON format.")
            }
            return existingLocator
        }

        // If CommandEnvelope.pathHint ([String]?) is provided, AND locator.rootElementPathHint ([JSONPathHintComponent]?) is NOT,
        // this indicates an attempt to use the old path hint format. We log a warning as it won't be used by the new system.
        if let topLevelOldPathHint = subCommandEnvelope.pathHint, 
           !topLevelOldPathHint.isEmpty, 
           newLocator.rootElementPathHint == nil || newLocator.rootElementPathHint!.isEmpty {
            axWarningLog("AXorcist+BatchHandler: CommandEnvelope.pathHint (old [String] format) provided for sub-command \(subCommandEnvelope.commandId), but new JSON format (locator.rootElementPathHint) is nil or empty. The old format pathHint will NOT be used. Please update your query to use the new JSON format for rootElementPathHint within the locator object.")
            // DO NOT ASSIGN: newLocator.rootElementPathHint = topLevelOldPathHint // This would be a type error
        }
        return newLocator
    }

    @MainActor
    public func handleBatchCommands(commandEnvelopes: [CommandEnvelope], batchCommandID: String) async -> [HandlerResponse] {
        var batchResults: [HandlerResponse] = []
        axDebugLog("[AXorcist.handleBatchCommands][BatchID: \(batchCommandID)] Received \(commandEnvelopes.count) sub-commands.")

        for subCommandEnvelope in commandEnvelopes {
            let result = await processSingleBatchCommand(subCommandEnvelope)
            batchResults.append(result)
        }

        // Batch processing complete
        axDebugLog("[AXorcist.handleBatchCommands] Batch processing complete")

        axDebugLog("[AXorcist.handleBatchCommands][BatchID: \(batchCommandID)] Completed batch command processing, returning \(batchResults.count) results.")
        return batchResults
    }

    @MainActor
    private func processSingleBatchCommand(_ subCommandEnvelope: CommandEnvelope) async -> HandlerResponse {
        let subCmdID = subCommandEnvelope.commandId
        axDebugLog("[AXorcist.handleBatchCommands][SubCmdID: \(subCmdID)] Processing sub-command: \(subCmdID), type: \(subCommandEnvelope.command)")

        // Log operation details
        axDebugLog("[AXorcist.handleBatchCommands] Processing sub-command: \(subCmdID) for app: \(subCommandEnvelope.application ?? AXMiscConstants.focusedApplicationKey)")

        switch subCommandEnvelope.command {
        case .getFocusedElement:
            return await processFocusedElementCommand(subCommandEnvelope)

        case .getAttributes:
            return await processGetAttributes(subCommandEnvelope, subCmdID: subCmdID)

        case .query:
            return await processQuery(subCommandEnvelope, subCmdID: subCmdID)

        case .describeElement:
            return await processDescribeElement(subCommandEnvelope, subCmdID: subCmdID)

        case .performAction:
            return await processPerformAction(subCommandEnvelope, subCmdID: subCmdID)

        case .setFocusedValue:
            axWarningLog("Command 'setFocusedValue' found in batch. Current batch handler does not specifically process it. Returning as unsupported for now.")
            return processUnsupportedCommand(subCommandEnvelope, subCmdID: subCmdID)

        case .extractText:
            return await processExtractText(subCommandEnvelope, subCmdID: subCmdID)

        case .getElementAtPoint:
            return processGetElementAtPoint(subCommandEnvelope, subCmdID: subCmdID)

        case .ping:
            return processPingCommand(subCmdID)

        case .collectAll:
            return processUnsupportedCommand(subCommandEnvelope, subCmdID: subCmdID)

        case .observe:
            return processUnsupportedCommand(subCommandEnvelope, subCmdID: subCmdID)

        @unknown default:
            return processUnknownCommand(subCommandEnvelope, subCmdID: subCmdID)
        }
    }

    @MainActor
    private func processFocusedElementCommand(_ subCommandEnvelope: CommandEnvelope) -> HandlerResponse {
        return self.handleGetFocusedElement(
            for: subCommandEnvelope.application,
            requestedAttributes: subCommandEnvelope.attributes
        )
    }

    @MainActor
    private func processGetAttributes(_ subCommandEnvelope: CommandEnvelope, subCmdID: String) async -> HandlerResponse {
        guard let originalLocator = subCommandEnvelope.locator else {
            let errorMsg = "Locator missing for getAttributes in batch (sub-command ID: \(subCmdID))"
            axErrorLog(errorMsg)
            return HandlerResponse(error: errorMsg)
        }
        let finalLocator = prepareLocator(for: subCommandEnvelope, existingLocator: originalLocator)

        return await self.handleGetAttributes(
            for: subCommandEnvelope.application,
            locator: finalLocator!,
            requestedAttributes: subCommandEnvelope.attributes,
            maxDepth: subCommandEnvelope.maxElements,
            outputFormat: subCommandEnvelope.outputFormat
        )
    }

    @MainActor
    private func processQuery(_ subCommandEnvelope: CommandEnvelope, subCmdID: String) async -> HandlerResponse {
        guard let originalLocator = subCommandEnvelope.locator else {
            let errorMsg = "Locator missing for query in batch (sub-command ID: \(subCmdID))"
            axErrorLog(errorMsg)
            return HandlerResponse(error: errorMsg)
        }
        let finalLocator = prepareLocator(for: subCommandEnvelope, existingLocator: originalLocator)

        return await self.handleQuery(
            for: subCommandEnvelope.application,
            locator: finalLocator!,
            maxDepth: subCommandEnvelope.maxElements,
            requestedAttributes: subCommandEnvelope.attributes,
            outputFormat: subCommandEnvelope.outputFormat
        )
    }

    @MainActor
    private func processDescribeElement(_ subCommandEnvelope: CommandEnvelope, subCmdID: String) async -> HandlerResponse {
        guard let originalLocator = subCommandEnvelope.locator else {
            let errorMsg = "Locator missing for describeElement in batch (sub-command ID: \(subCmdID))"
            axErrorLog(errorMsg)
            return HandlerResponse(error: errorMsg)
        }
        let finalLocator = prepareLocator(for: subCommandEnvelope, existingLocator: originalLocator)

        return await self.handleDescribeElement(
            for: subCommandEnvelope.application,
            locator: finalLocator!,
            maxDepth: subCommandEnvelope.maxDepth,
            requestedAttributes: subCommandEnvelope.attributes,
            outputFormat: subCommandEnvelope.outputFormat
        )
    }

    @MainActor
    private func processPerformAction(_ subCommandEnvelope: CommandEnvelope, subCmdID: String) async -> HandlerResponse {
        guard let originalLocator = subCommandEnvelope.locator else {
            let errorMsg = "Locator missing for performAction in batch (sub-command ID: \(subCmdID))"
            axErrorLog(errorMsg)
            return HandlerResponse(error: errorMsg)
        }
        guard let actionName = subCommandEnvelope.actionName else {
            let errorMsg = "Action name missing for performAction in batch (sub-command ID: \(subCmdID))"
            axErrorLog(errorMsg)
            return HandlerResponse(error: errorMsg)
        }
        let finalLocator = prepareLocator(for: subCommandEnvelope, existingLocator: originalLocator)

        return await self.handlePerformAction(
            for: subCommandEnvelope.application,
            locator: finalLocator!,
            actionName: actionName,
            actionValue: subCommandEnvelope.actionValue,
            maxDepth: subCommandEnvelope.maxElements
        )
    }

    @MainActor
    private func processExtractText(_ subCommandEnvelope: CommandEnvelope, subCmdID: String) async -> HandlerResponse {
        guard let originalLocator = subCommandEnvelope.locator else {
            let errorMsg = "Locator missing for extractText in batch (sub-command ID: \(subCmdID))"
            axErrorLog(errorMsg)
            return HandlerResponse(error: errorMsg)
        }
        let finalLocator = prepareLocator(for: subCommandEnvelope, existingLocator: originalLocator)

        return await self.handleExtractText(
            for: subCommandEnvelope.application,
            locator: finalLocator!,
            maxDepth: subCommandEnvelope.maxElements
        )
    }

    @MainActor
    private func processGetElementAtPoint(_ subCommandEnvelope: CommandEnvelope, subCmdID: String) -> HandlerResponse {
        guard let point = subCommandEnvelope.point else {
            let errorMsg = "Missing point for getElementAtPoint command (sub-command ID: \(subCmdID))"
            axErrorLog(errorMsg)
            return HandlerResponse(error: errorMsg)
        }
        return self.handleGetElementAtPoint(
            for: subCommandEnvelope.application,
            point: point,
            requestedAttributes: subCommandEnvelope.attributes,
            outputFormat: subCommandEnvelope.outputFormat
        )
    }

    @MainActor
    private func processPingCommand(_ subCmdID: String) -> HandlerResponse {
        let pingMsg = "Ping command handled within batch (sub-command ID: \(subCmdID))"
        axInfoLog(pingMsg)
        return HandlerResponse(data: nil, error: nil)
    }

    @MainActor
    private func processUnsupportedCommand(_ subCommandEnvelope: CommandEnvelope, subCmdID: String) -> HandlerResponse {
        let errorMsg =
            "Command type '\(subCommandEnvelope.command)' not supported within batch execution by AXorcist (sub-command ID: \(subCmdID))"
        axErrorLog(errorMsg)
        return HandlerResponse(error: errorMsg)
    }

    @MainActor
    private func processUnknownCommand(_ subCommandEnvelope: CommandEnvelope, subCmdID: String) -> HandlerResponse {
        let errorMsg =
            "Unknown or unhandled command type '\(subCommandEnvelope.command)' in batch processing within AXorcist (sub-command ID: \(subCmdID))"
        axErrorLog(errorMsg)
        return HandlerResponse(error: errorMsg)
    }
}
