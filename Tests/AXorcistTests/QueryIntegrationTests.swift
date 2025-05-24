import AppKit
@testable import AXorcist
import Testing

// MARK: - Query Command Tests

@Test("Launch TextEdit, Get Focused Element via STDIN")
func testLaunchAndQueryTextEdit() async throws {
    await closeTextEdit()
    try await Task.sleep(for: .milliseconds(500))

    let (pid, _) = try await setupTextEditAndGetInfo()
    #expect(pid != 0, "PID should not be zero after TextEdit setup")

    let commandId = "focused_textedit_test_\(UUID().uuidString)"
    let attributesToFetch: [String] = [
        ApplicationServices.kAXRoleAttribute as String,
        ApplicationServices.kAXRoleDescriptionAttribute as String,
        ApplicationServices.kAXValueAttribute as String,
        "AXPlaceholderValue"
    ]

    let commandEnvelope = createCommandEnvelope(
        commandId: commandId,
        command: .getFocusedElement,
        application: "com.apple.TextEdit",
        attributes: attributesToFetch
    )

    let inputJSON = try encodeCommandToJSON(commandEnvelope)

    print("Input JSON for axorc:\n\(inputJSON)")

    let (output, errorOutput, terminationStatus) = try runAXORCCommandWithStdin(
        inputJSON: inputJSON,
        arguments: ["--debug"]
    )

    print("axorc STDOUT:\n\(output ?? "nil")")
    print("axorc STDERR:\n\(errorOutput ?? "nil")")
    print("axorc Termination Status: \(terminationStatus)")

    let outputJSONString = try validateCommandExecution(
        output: output,
        errorOutput: errorOutput,
        exitCode: terminationStatus,
        commandName: "getFocusedElement"
    )

    let queryResponse = try decodeQueryResponse(from: outputJSONString, commandName: "getFocusedElement")
    validateQueryResponseBasics(queryResponse, expectedCommandId: commandId, expectedCommand: .getFocusedElement)

    guard let elementData = queryResponse.data else {
        throw TestError
            .generic(
                "QueryResponse data is nil. Error: \(queryResponse.error?.message ?? "N/A"). " +
                    "Logs: \(queryResponse.debugLogs?.joined(separator: "\n") ?? "")"
            )
    }

    let expectedRole = ApplicationServices.kAXTextAreaRole as String
    let actualRole = elementData.attributes?[ApplicationServices.kAXRoleAttribute as String]?.value as? String
    let attributeKeys = Array(elementData.attributes?.keys ?? [])
    #expect(
        actualRole == expectedRole,
        "Focused element role should be '\(expectedRole)'. Got: '\(actualRole ?? "nil")'. " +
            "Attributes: \(attributeKeys)"
    )

    #expect(
        elementData.attributes?.keys.contains(ApplicationServices.kAXValueAttribute as String) == true,
        "Focused element attributes should contain kAXValueAttribute as it was requested."
    )

    if let logs = queryResponse.debugLogs, !logs.isEmpty {
        print("axorc Debug Logs:")
        logs.forEach { print($0) }
    }

    await closeTextEdit()
}

@Test("Get Attributes for TextEdit Application")
@MainActor
func testGetAttributesForTextEditApplication() async throws {
    let commandId = "getattributes-textedit-app-\(UUID().uuidString)"
    let textEditBundleId = "com.apple.TextEdit"
    let requestedAttributes = ["AXRole", "AXTitle", "AXWindows", "AXFocusedWindow", "AXMainWindow", "AXIdentifier"]

    do {
        _ = try await setupTextEditAndGetInfo()
        print("TextEdit setup completed for getAttributes test.")
    } catch {
        throw TestError.generic("TextEdit setup failed for getAttributes: \(error.localizedDescription)")
    }
    defer {
        Task { await closeTextEdit() }
        print("TextEdit close process initiated for getAttributes test.")
    }

    let appLocator = Locator(criteria: [:])

    let commandEnvelope = createCommandEnvelope(
        commandId: commandId,
        command: .getAttributes,
        application: textEditBundleId,
        attributes: requestedAttributes,
        locator: appLocator
    )

    let jsonString = try encodeCommandToJSON(commandEnvelope)

    print("Sending getAttributes command to axorc: \(jsonString)")
    let (output, errorOutput, exitCode) = try runAXORCCommand(arguments: [jsonString])

    let outputString = try validateCommandExecution(
        output: output,
        errorOutput: errorOutput,
        exitCode: exitCode,
        commandName: "getAttributes"
    )

    let queryResponse = try decodeQueryResponse(from: outputString, commandName: "getAttributes")
    validateQueryResponseBasics(queryResponse, expectedCommandId: commandId, expectedCommand: .getAttributes)
    #expect(queryResponse.data?.attributes != nil, "AXElement attributes should not be nil.")

        let attributes = queryResponse.data?.attributes
        #expect(
            attributes?["AXRole"]?.value as? String == "AXApplication",
            "Application role should be AXApplication. Got: \(String(describing: attributes?["AXRole"]?.value))"
        )
        #expect(
            attributes?["AXTitle"]?.value as? String == "TextEdit",
            "Application title should be TextEdit. Got: \(String(describing: attributes?["AXTitle"]?.value))"
        )

        if let windowsAttr = attributes?["AXWindows"] {
            #expect(windowsAttr.value is [Any], "AXWindows should be an array. Type: \(type(of: windowsAttr.value))")
            if let windowsArray = windowsAttr.value as? [AnyCodable] {
                #expect(!windowsArray.isEmpty, "AXWindows array should not be empty if TextEdit has windows.")
            } else if let windowsArray = windowsAttr.value as? [Any] {
                #expect(!windowsArray.isEmpty, "AXWindows array should not be empty (general type check).")
            }
        } else {
            #expect(attributes?["AXWindows"] != nil, "AXWindows attribute should be present.")
        }

        #expect(queryResponse.debugLogs != nil, "Debug logs should be present.")
        #expect(
            queryResponse.debugLogs?
                .contains {
                    $0.contains("Handling getAttributes command") || $0.contains("handleGetAttributes completed") } ==
                true,
            "Debug logs should indicate getAttributes execution."
        )

    }
}

@Test("Query for TextEdit Text Area")
@MainActor
func testQueryForTextEditTextArea() async throws {
    let commandId = "query-textedit-textarea-\(UUID().uuidString)"
    let textEditBundleId = "com.apple.TextEdit"
    let textAreaRole = ApplicationServices.kAXTextAreaRole as String
    let requestedAttributes = ["AXRole", "AXValue", "AXSelectedText", "AXNumberOfCharacters"]

    do {
        _ = try await setupTextEditAndGetInfo()
        print("TextEdit setup completed for query test.")
    } catch {
        throw TestError.generic("TextEdit setup failed for query: \(error.localizedDescription)")
    }
    defer {
        Task { await closeTextEdit() }
        print("TextEdit close process initiated for query test.")
    }

    let textAreaLocator = Locator(
        criteria: ["AXRole": textAreaRole]
    )

    let commandEnvelope = createCommandEnvelope(
        commandId: commandId,
        command: .query,
        application: textEditBundleId,
        attributes: requestedAttributes,
        locator: textAreaLocator
    )

    let jsonString = try encodeCommandToJSON(commandEnvelope)

    print("Sending query command to axorc: \(jsonString)")
    let (output, errorOutput, exitCode) = try runAXORCCommand(arguments: [jsonString])

    let outputString = try validateCommandExecution(
        output: output,
        errorOutput: errorOutput,
        exitCode: exitCode,
        commandName: "query"
    )

    let queryResponse = try decodeQueryResponse(from: outputString, commandName: "query")
    validateQueryResponseBasics(queryResponse, expectedCommandId: commandId, expectedCommand: .query)
    #expect(queryResponse.data?.attributes != nil, "AXElement attributes should not be nil.")

        let attributes = queryResponse.data?.attributes
        #expect(
            attributes?["AXRole"]?.value as? String == textAreaRole,
            "Element role should be \(textAreaRole). Got: \(String(describing: attributes?["AXRole"]?.value))"
        )

        #expect(attributes?["AXValue"]?.value is String, "AXValue should exist and be a string.")
        #expect(attributes?["AXNumberOfCharacters"]?.value is Int, "AXNumberOfCharacters should exist and be an Int.")

        #expect(queryResponse.debugLogs != nil, "Debug logs should be present.")
        #expect(
            queryResponse.debugLogs?
                .contains { $0.contains("Handling query command") || $0.contains("handleQuery completed") } == true,
            "Debug logs should indicate query execution."
        )

    }
}

@Test("Describe TextEdit Text Area")
@MainActor
func testDescribeTextEditTextArea() async throws {
    let commandId = "describe-textedit-textarea-\(UUID().uuidString)"
    let textEditBundleId = "com.apple.TextEdit"
    let textAreaRole = ApplicationServices.kAXTextAreaRole as String

    do {
        _ = try await setupTextEditAndGetInfo()
        print("TextEdit setup completed for describeElement test.")
    } catch {
        throw TestError.generic("TextEdit setup failed for describeElement: \(error.localizedDescription)")
    }
    defer {
        Task { await closeTextEdit() }
        print("TextEdit close process initiated for describeElement test.")
    }

    let textAreaLocator = Locator(
        criteria: ["AXRole": textAreaRole]
    )

    let commandEnvelope = createCommandEnvelope(
        commandId: commandId,
        command: .describeElement,
        application: textEditBundleId,
        locator: textAreaLocator
    )

    let jsonString = try encodeCommandToJSON(commandEnvelope)

    print("Sending describeElement command to axorc: \(jsonString)")
    let (output, errorOutput, exitCode) = try runAXORCCommand(arguments: [jsonString])

    let outputString = try validateCommandExecution(
        output: output,
        errorOutput: errorOutput,
        exitCode: exitCode,
        commandName: "describeElement"
    )

    let queryResponse = try decodeQueryResponse(from: outputString, commandName: "describeElement")
    validateQueryResponseBasics(queryResponse, expectedCommandId: commandId, expectedCommand: .describeElement)

        guard let attributes = queryResponse.data?.attributes else {
            throw TestError.generic("Attributes dictionary is nil in describeElement response.")
        }

        #expect(
            attributes["AXRole"]?.value as? String == textAreaRole,
            "Element role should be \(textAreaRole). Got: \(String(describing: attributes["AXRole"]?.value))"
        )

        #expect(attributes["AXRoleDescription"]?.value is String, "AXRoleDescription should exist.")
        #expect(attributes["AXEnabled"]?.value is Bool, "AXEnabled should exist.")
        #expect(attributes["AXPosition"]?.value != nil, "AXPosition should exist.")
        #expect(attributes["AXSize"]?.value != nil, "AXSize should exist.")
        #expect(
            attributes.count > 10,
            "Expected describeElement to return many attributes (e.g., > 10). Got \(attributes.count)"
        )

        #expect(queryResponse.debugLogs != nil, "Debug logs should be present.")
        #expect(
            queryResponse.debugLogs?
                .contains {
                    $0.contains("Handling describeElement command") || $0.contains("handleDescribeElement completed")
                } ==
                true,
            "Debug logs should indicate describeElement execution."
        )

    }
}

// MARK: - Helper Functions

private func createCommandEnvelope(
    commandId: String,
    command: CommandType,
    application: String,
    attributes: [String]? = nil,
    locator: Locator? = nil,
    debugLogging: Bool = true
) -> CommandEnvelope {
    return CommandEnvelope(
        commandId: commandId,
        command: command,
        application: application,
        attributes: attributes,
        debugLogging: debugLogging,
        locator: locator,
        payload: nil
    )
}

private func encodeCommandToJSON(_ commandEnvelope: CommandEnvelope) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .withoutEscapingSlashes
    let jsonData = try encoder.encode(commandEnvelope)
    guard let jsonString = String(data: jsonData, encoding: .utf8) else {
        throw TestError.generic("Failed to create JSON string for command.")
    }
    return jsonString
}

private func decodeQueryResponse(from outputString: String, commandName: String) throws -> QueryResponse {
    guard let responseData = outputString.data(using: .utf8) else {
        throw TestError.generic("Could not convert output string to data for \(commandName). Output: \(outputString)")
    }

    let decoder = JSONDecoder()
    do {
        return try decoder.decode(QueryResponse.self, from: responseData)
    } catch {
        throw TestError.generic(
            "Failed to decode QueryResponse for \(commandName): \(error.localizedDescription). " +
            "Original JSON: \(outputString)"
        )
    }
}

private func validateCommandExecution(
    output: String?,
    errorOutput: String?,
    exitCode: Int32,
    commandName: String
) throws -> String {
    #expect(exitCode == 0, "axorc process should exit with 0 for \(commandName). Error: \(errorOutput ?? "N/A")")
    #expect(errorOutput == nil || errorOutput!.isEmpty, "STDERR should be empty on success. Got: \(errorOutput ?? "")")

    guard let outputString = output, !outputString.isEmpty else {
        throw TestError.generic("Output string was nil or empty for \(commandName).")
    }

    print("Received output from axorc (\(commandName)): \(outputString)")
    return outputString
}

private func validateQueryResponseBasics(
    _ queryResponse: QueryResponse,
    expectedCommandId: String,
    expectedCommand: CommandType
) {
    #expect(queryResponse.commandId == expectedCommandId)
    #expect(
        queryResponse.success == true,
        "Command should succeed. Error: \(queryResponse.error?.message ?? "None")"
    )
    #expect(queryResponse.command == expectedCommand.rawValue)
    #expect(queryResponse.error == nil, "Error field should be nil. Got: \(queryResponse.error?.message ?? "N/A")")
    #expect(queryResponse.data != nil, "Data field should not be nil.")
}
