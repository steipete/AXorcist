import Foundation

@MainActor
extension AXorcist {
    public func handleBatchCommands(command: AXBatchCommand) -> AXResponse {
        GlobalAXLogger.shared.log(AXLogEntry(level: .info, message: "HandleBatch: Received \(command.commands.count) sub-commands."))
        var results: [AXResponse] = []
        var overallSuccess = true
        var errorMessages: [String] = []

        for (index, subCommandEnvelope) in command.commands.enumerated() {
            GlobalAXLogger.shared.log(AXLogEntry(
                level: .debug,
                message: "HandleBatch: Processing sub-command \(index + 1)/\(command.commands.count): " +
                    "ID '\(subCommandEnvelope.commandID)', Type: \(subCommandEnvelope.command.type)"
            ))

            let response = processSingleBatchCommand(subCommandEnvelope.command)
            results.append(response)

            if response.status != "success" {
                overallSuccess = false
                let errorDetail = response.error?.message ?? "Unknown error in sub-command \(subCommandEnvelope.commandID)"
                errorMessages.append("Sub-command \(subCommandEnvelope.commandID) ('\(subCommandEnvelope.command.type)') failed: \(errorDetail)")
                GlobalAXLogger.shared.log(AXLogEntry(level: .warning, message: "HandleBatch: Sub-command \(subCommandEnvelope.commandID) failed: \(errorDetail)"))
            }
        }

        if overallSuccess {
            GlobalAXLogger.shared.log(AXLogEntry(level: .info, message: "HandleBatch: All \(command.commands.count) sub-commands succeeded."))
            let successfulPayloads = results.map { $0.payload }
            return .successResponse(payload: AnyCodable(BatchResponsePayload(results: successfulPayloads, errors: nil)))
        } else {
            let combinedErrorMessage = "HandleBatch: One or more sub-commands failed. Errors: \(errorMessages.joined(separator: "; "))"
            GlobalAXLogger.shared.log(AXLogEntry(level: .error, message: combinedErrorMessage))
            return .errorResponse(message: combinedErrorMessage, code: .batchOperationFailed)
        }
    }

    private func processSingleBatchCommand(_ command: AXCommand) -> AXResponse {
        switch command {
        case .query(let queryCommand):
            return handleQuery(command: queryCommand, maxDepth: queryCommand.maxDepthForSearch)
        case .performAction(let actionCommand):
            return handlePerformAction(command: actionCommand)
        case .getAttributes(let getAttributesCommand):
            return handleGetAttributes(command: getAttributesCommand)
        case .describeElement(let describeCommand):
            return handleDescribeElement(command: describeCommand)
        case .extractText(let extractTextCommand):
            return handleExtractText(command: extractTextCommand)
        case .setFocusedValue(let setFocusedValueCommand):
            return handleSetFocusedValue(command: setFocusedValueCommand)
        case .getElementAtPoint(let getElementAtPointCommand):
            return handleGetElementAtPoint(command: getElementAtPointCommand)
        case .getFocusedElement(let getFocusedElementCommand):
            return handleGetFocusedElement(command: getFocusedElementCommand)
        case .observe(let observeCommand):
            GlobalAXLogger.shared.log(AXLogEntry(level: .info, message: "BatchProc: Processing Observe command."))
            return handleObserve(command: observeCommand)
        case .collectAll(let collectAllCommand):
            return handleCollectAll(command: collectAllCommand)
        case .batch:
            return .errorResponse(message: "Nested batch commands are not supported within a single batch operation.", code: .invalidCommand)
        }
    }
}
