import AppKit
@testable import AXorcist
import Testing

// MARK: - Batch Command Tests

@Test("Batch Command: GetFocusedElement and Query TextEdit")
@MainActor
func testBatchCommandGetFocusedElementAndQuery() async throws {
    let batchCommandId = "batch-textedit-\(UUID().uuidString)"
    let focusedElementSubCmdId = "batch-sub-getfocused-\(UUID().uuidString)"
    let querySubCmdId = "batch-sub-querytextarea-\(UUID().uuidString)"
    let textEditBundleId = "com.apple.TextEdit"
    let textAreaRole = ApplicationServices.kAXTextAreaRole as String

    // Setup TextEdit
    _ = try await setupTextEditAndGetInfo()
    defer { Task { await closeTextEdit() } }

    // Create batch command
    let batchCommand = createBatchCommand(
        batchCommandId: batchCommandId,
        focusedElementSubCmdId: focusedElementSubCmdId,
        querySubCmdId: querySubCmdId,
        textEditBundleId: textEditBundleId,
        textAreaRole: textAreaRole
    )

    // Execute batch command
    let batchResponse = try await executeBatchCommand(batchCommand)

    // Verify results
    verifyBatchResponse(
        batchResponse,
        batchCommandId: batchCommandId,
        focusedElementSubCmdId: focusedElementSubCmdId,
        querySubCmdId: querySubCmdId,
        textAreaRole: textAreaRole
    )
}

// MARK: - Helper Functions

private func createBatchCommand(
    batchCommandId: String,
    focusedElementSubCmdId: String,
    querySubCmdId: String,
    textEditBundleId: String,
    textAreaRole: String
) -> CommandEnvelope {
    let getFocusedElementSubCommand = CommandEnvelope(
        commandId: focusedElementSubCmdId,
        command: .getFocusedElement,
        application: textEditBundleId,
        debugLogging: true
    )

    let queryTextAreaSubCommand = CommandEnvelope(
        commandId: querySubCmdId,
        command: .query,
        application: textEditBundleId,
        attributes: ["AXRole", "AXValue"],
        debugLogging: true,
        locator: Locator(criteria: ["AXRole": textAreaRole])
    )

    return CommandEnvelope(
        commandId: batchCommandId,
        command: .batch,
        application: nil,
        debugLogging: true,
        subCommands: [getFocusedElementSubCommand, queryTextAreaSubCommand]
    )
}

private func executeBatchCommand(_ command: CommandEnvelope) async throws -> BatchOperationResponse {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .prettyPrinted
    let jsonData = try encoder.encode(command)
    guard let jsonString = String(data: jsonData, encoding: .utf8) else {
        throw TestError.generic("Failed to create JSON string for batch command.")
    }

    print("Sending batch command to axorc: \(jsonString)")
    let result = try runAXORCCommand(arguments: [jsonString])
    let (output, errorOutput, exitCode) = (result.output, result.errorOutput, result.exitCode)

    #expect(exitCode == 0, "axorc process for batch command should exit with 0. Error: \(errorOutput ?? "N/A")")
    #expect(errorOutput == nil || errorOutput!.isEmpty, "STDERR should be empty. Got: \(errorOutput ?? "")")

    guard let outputString = output, !outputString.isEmpty else {
        throw TestError.generic("Output string was nil or empty for batch command.")
    }
    print("Received output from axorc (batch command): \(outputString)")

    guard let responseData = outputString.data(using: .utf8) else {
        throw TestError.generic("Could not convert output string to data for batch command.")
    }

    return try JSONDecoder().decode(BatchOperationResponse.self, from: responseData)
}

private func verifyBatchResponse(
    _ batchResponse: BatchOperationResponse,
    batchCommandId: String,
    focusedElementSubCmdId: String,
    querySubCmdId: String,
    textAreaRole: String
) {
    #expect(batchResponse.commandId == batchCommandId)
    #expect(batchResponse.success == true, "Batch command should succeed")
    #expect(batchResponse.results.count == 2, "Expected 2 results")

    // Verify first sub-command
    let result1 = batchResponse.results[0]
    #expect(result1.commandId == focusedElementSubCmdId)
    #expect(result1.success == true, "GetFocusedElement should succeed")
    #expect(result1.command == CommandType.getFocusedElement.rawValue)
    #expect(result1.data != nil)
    #expect(result1.data?.attributes?["AXRole"]?.value as? String == textAreaRole)

    // Verify second sub-command
    let result2 = batchResponse.results[1]
    #expect(result2.commandId == querySubCmdId)
    #expect(result2.success == true, "Query should succeed")
    #expect(result2.command == CommandType.query.rawValue)
    #expect(result2.data != nil)
    #expect(result2.data?.attributes?["AXRole"]?.value as? String == textAreaRole)

    #expect(batchResponse.debugLogs != nil)
}
