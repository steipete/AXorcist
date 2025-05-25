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
        guard var newLocator = existingLocator else {
            // If there's a pathHint on the envelope but no locator, this is problematic.
            // For now, if no base locator, we can't effectively use the pathHint from the envelope alone
            // unless we construct a new locator, but that might miss criteria.
            // This case should ideally be handled by validation upstream or clearer contract.
            // If pathHint is the ONLY way to locate, the CommandEnvelope should reflect that.
            // For now, just return the locator as is (which might be nil).
            if subCommandEnvelope.pathHint != nil && !subCommandEnvelope.pathHint!.isEmpty {
                axWarningLog("SubCommand \(subCommandEnvelope.commandId) has a pathHint but no base locator. PathHint will not be used unless locator also has criteria.")
                // Optionally, create a locator with only pathHint if that's a valid use case:
                // return Locator(criteria: [:], rootElementPathHint: subCommandEnvelope.pathHint)
            }
            return existingLocator
        }

        // If CommandEnvelope.pathHint is provided, and locator.rootElementPathHint is not,
        // transfer the pathHint to the locator.
        if let topLevelPathHint = subCommandEnvelope.pathHint,
           !topLevelPathHint.isEmpty,
           newLocator.rootElementPathHint == nil || newLocator.rootElementPathHint!.isEmpty {
            axDebugLog("AXorcist+BatchHandler: Populating locator.rootElementPathHint from CommandEnvelope.pathHint for sub-command \(subCommandEnvelope.commandId).")
            newLocator.rootElementPathHint = topLevelPathHint
        }
        return newLocator
    }

    @MainActor
    public func handleBatchCommands(
        batchCommandID: String, // The ID of the overall batch command
        subCommands: [CommandEnvelope] // The array of sub-commands to process
    ) async -> [HandlerResponse] {
        // REMOVED: SearchVisitor.resetGlobalVisitCount() // Reset counter at the start of the whole batch
        axInfoLog("Starting batch command execution. Batch ID: \(batchCommandID), Number of sub-commands: \(subCommands.count)")

        var batchResults: [HandlerResponse] = []

        for subCommandEnvelope in subCommands {
            let subCommandResponse = await processSingleBatchCommand(subCommandEnvelope)
            batchResults.append(subCommandResponse)
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
            return processFocusedElementCommand(subCommandEnvelope)

        case .getAttributes:
            return await processGetAttributesCommand(subCommandEnvelope, subCmdID: subCmdID)

        case .query:
            return await processQueryCommand(subCommandEnvelope, subCmdID: subCmdID)

        case .describeElement:
            return await processDescribeElementCommand(subCommandEnvelope, subCmdID: subCmdID)

        case .performAction:
            return await processPerformActionCommand(subCommandEnvelope, subCmdID: subCmdID)

        case .setFocusedValue:
            axWarningLog("Command 'setFocusedValue' found in batch. Current batch handler does not specifically process it. Returning as unsupported for now.")
            return processUnsupportedCommand(subCommandEnvelope, subCmdID: subCmdID)

        case .extractText:
            return await processExtractTextCommand(subCommandEnvelope, subCmdID: subCmdID)

        case .getElementAtPoint:
            return processGetElementAtPointCommand(subCommandEnvelope, subCmdID: subCmdID)

        case .ping:
            return processPingCommand(subCmdID)

        case .collectAll, .batch, .observe:
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
    private func processGetAttributesCommand(_ subCommandEnvelope: CommandEnvelope, subCmdID: String) async -> HandlerResponse {
        guard let originalLocator = subCommandEnvelope.locator else {
            let errorMsg = "Locator missing for getAttributes in batch (sub-command ID: \(subCmdID))"
            axErrorLog(errorMsg)
            return HandlerResponse(error: errorMsg)
        }
        let finalLocator = prepareLocator(for: subCommandEnvelope, existingLocator: originalLocator)

        return await self.handleGetAttributes(
            for: subCommandEnvelope.application,
            locator: finalLocator!, // Safe to force unwrap as we checked originalLocator
            requestedAttributes: subCommandEnvelope.attributes,
            maxDepth: subCommandEnvelope.maxElements, // maxElements often used as maxDepth for search in handlers
            outputFormat: subCommandEnvelope.outputFormat
        )
    }

    @MainActor
    private func processQueryCommand(_ subCommandEnvelope: CommandEnvelope, subCmdID: String) async -> HandlerResponse {
        guard let originalLocator = subCommandEnvelope.locator else {
            let errorMsg = "Locator missing for query in batch (sub-command ID: \(subCmdID))"
            axErrorLog(errorMsg)
            return HandlerResponse(error: errorMsg)
        }
        let finalLocator = prepareLocator(for: subCommandEnvelope, existingLocator: originalLocator)

        return await self.handleQuery(
            for: subCommandEnvelope.application,
            locator: finalLocator!, // Safe to force unwrap
            maxDepth: subCommandEnvelope.maxElements,
            requestedAttributes: subCommandEnvelope.attributes,
            outputFormat: subCommandEnvelope.outputFormat
        )
    }

    @MainActor
    private func processDescribeElementCommand(_ subCommandEnvelope: CommandEnvelope, subCmdID: String) async -> HandlerResponse {
        guard let originalLocator = subCommandEnvelope.locator else {
            let errorMsg = "Locator missing for describeElement in batch (sub-command ID: \(subCmdID))"
            axErrorLog(errorMsg)
            return HandlerResponse(error: errorMsg)
        }
        let finalLocator = prepareLocator(for: subCommandEnvelope, existingLocator: originalLocator)

        return await self.handleDescribeElement(
            for: subCommandEnvelope.application,
            locator: finalLocator!, // Safe to force unwrap
            maxDepth: subCommandEnvelope.maxDepth, // Use maxDepth for describeElement
            requestedAttributes: subCommandEnvelope.attributes,
            outputFormat: subCommandEnvelope.outputFormat
        )
    }

    @MainActor
    private func processPerformActionCommand(_ subCommandEnvelope: CommandEnvelope, subCmdID: String) async -> HandlerResponse {
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
            locator: finalLocator!, // Safe to force unwrap
            actionName: actionName,
            actionValue: subCommandEnvelope.actionValue,
            maxDepth: subCommandEnvelope.maxElements // maxElements often used as maxDepth for search in handlers
        )
    }

    @MainActor
    private func processExtractTextCommand(_ subCommandEnvelope: CommandEnvelope, subCmdID: String) async -> HandlerResponse {
        guard let originalLocator = subCommandEnvelope.locator else {
            let errorMsg = "Locator missing for extractText in batch (sub-command ID: \(subCmdID))"
            axErrorLog(errorMsg)
            return HandlerResponse(error: errorMsg)
        }
        let finalLocator = prepareLocator(for: subCommandEnvelope, existingLocator: originalLocator)

        return await self.handleExtractText(
            for: subCommandEnvelope.application,
            locator: finalLocator!, // Safe to force unwrap
            maxDepth: subCommandEnvelope.maxElements // maxElements often used as maxDepth for search in handlers
        )
    }

    @MainActor
    private func processGetElementAtPointCommand(_ subCommandEnvelope: CommandEnvelope, subCmdID: String) -> HandlerResponse {
        guard let point = subCommandEnvelope.point else {
            let errorMsg = "Missing point for getElementAtPoint command (sub-command ID: \(subCmdID))"
            axErrorLog(errorMsg)
            return HandlerResponse(error: errorMsg)
        }
        return self.getElementAtPoint(
            pid: subCommandEnvelope.pid.map { pid_t($0) },
            point: point,
            appIdentifierOrNil: subCommandEnvelope.application,
            requestedAttributes: subCommandEnvelope.attributes
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
