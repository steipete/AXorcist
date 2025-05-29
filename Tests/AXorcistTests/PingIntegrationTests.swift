@testable import AXorcist
import Foundation
import Testing

// MARK: - Ping Command Tests

@Test("Test Ping via STDIN")
func pingViaStdin() async throws {
    let inputJSON = """
    {
        "command_id": "test_ping_stdin",
        "command": "ping",
        "payload": {
            "message": "Hello from testPingViaStdin"
        }
    }
    """
    let result = try runAXORCCommandWithStdin(
        inputJSON: inputJSON,
        arguments: ["--stdin"]
    )

    #expect(
        result.exitCode == 0,
        Comment(rawValue: "axorc command failed with status \(result.exitCode). Error: \(result.errorOutput ?? "N/A")")
    )
    #expect(
        result.errorOutput == nil || result.errorOutput!.isEmpty,
        Comment(rawValue: "Expected no error output, but got: \(result.errorOutput!)")
    )

    guard let outputString = result.output else {
        #expect(Bool(false), Comment(rawValue: "Output was nil for ping via STDIN"))
        return
    }

    guard let responseData = outputString.data(using: String.Encoding.utf8) else {
        #expect(
            Bool(false),
            Comment(rawValue: "Failed to convert output to Data for ping via STDIN. Output: \(outputString)")
        )
        return
    }
    let decodedResponse = try JSONDecoder().decode(SimpleSuccessResponse.self, from: responseData)
    #expect(decodedResponse.success == true)
    #expect(
        decodedResponse.message == "Ping handled by AXORCCommand. Input source: STDIN",
        Comment(rawValue: "Unexpected success message: \(decodedResponse.message)")
    )
    #expect(decodedResponse.details == "Hello from testPingViaStdin")
}

@Test("Test Ping via --file")
func pingViaFile() async throws {
    let payloadMessage = "Hello from testPingViaFile"
    let inputJSON = """
    {
        "command_id": "test_ping_file",
        "command": "ping",
        "payload": { "message": "\(payloadMessage)" }
    }
    """
    let tempFilePath = try createTempFile(content: inputJSON)
    defer { try? FileManager.default.removeItem(atPath: tempFilePath) }

    let result = try runAXORCCommand(arguments: ["--file", tempFilePath])

    #expect(
        result.exitCode == 0,
        Comment(rawValue: "axorc command failed with status \(result.exitCode). Error: \(result.errorOutput ?? "N/A")")
    )
    #expect(
        result.errorOutput == nil || result.errorOutput!.isEmpty,
        Comment(rawValue: "Expected no error output, but got: \(result.errorOutput ?? "N/A")")
    )

    guard let outputString = result.output else {
        #expect(Bool(false), Comment(rawValue: "Output was nil for ping via file"))
        return
    }
    guard let responseData = outputString.data(using: String.Encoding.utf8) else {
        #expect(
            Bool(false),
            Comment(rawValue: "Failed to convert output to Data for ping via file. Output: \(outputString)")
        )
        return
    }
    let decodedResponse = try JSONDecoder().decode(SimpleSuccessResponse.self, from: responseData)
    #expect(decodedResponse.success == true)
    #expect(
        decodedResponse.message.lowercased().contains("file: \(tempFilePath.lowercased())"),
        Comment(rawValue: "Message should contain file path. Got: \(decodedResponse.message)")
    )
    #expect(decodedResponse.details == payloadMessage)
}

@Test("Test Ping via direct positional argument")
func pingViaDirectPayload() async throws {
    let payloadMessage = "Hello from testPingViaDirectPayload"
    let inputJSON =
        "{\"command_id\":\"test_ping_direct\",\"command\":\"ping\",\"payload\":{\"message\":\"\(payloadMessage)\"}}"

    let result = try runAXORCCommand(arguments: [inputJSON])

    #expect(
        result.exitCode == 0,
        Comment(rawValue: "axorc command failed with status \(result.exitCode). Error: \(result.errorOutput ?? "N/A")")
    )
    #expect(
        result.errorOutput == nil || result.errorOutput!.isEmpty,
        Comment(rawValue: "Expected no error output, but got: \(result.errorOutput ?? "N/A")")
    )

    guard let outputString = result.output else {
        #expect(Bool(false), Comment(rawValue: "Output was nil for ping via direct payload"))
        return
    }
    guard let responseData = outputString.data(using: String.Encoding.utf8) else {
        #expect(
            Bool(false),
            Comment(rawValue: "Failed to convert output to Data for ping via direct payload. Output: \(outputString)")
        )
        return
    }
    let decodedResponse = try JSONDecoder().decode(SimpleSuccessResponse.self, from: responseData)
    #expect(decodedResponse.success == true)
    #expect(
        decodedResponse.message.contains("Direct Argument Payload"),
        Comment(rawValue: "Unexpected success message: \(decodedResponse.message)")
    )
    #expect(decodedResponse.details == payloadMessage)
}

@Test("Test Error: Multiple Input Methods (stdin and file)")
func errorMultipleInputMethods() async throws {
    let inputJSON = """
    {
        "command_id": "test_error_multiple_inputs",
        "command": "ping",
        "payload": { "message": "This should not be processed" }
    }
    """
    let tempFilePath = try createTempFile(content: "{}")
    defer { try? FileManager.default.removeItem(atPath: tempFilePath) }

    let result = try runAXORCCommandWithStdin(
        inputJSON: inputJSON,
        arguments: ["--file", tempFilePath]
    )

    #expect(
        result.exitCode == 0,
        Comment(rawValue: "axorc command should return 0 with error on stdout. Status: \(result.exitCode). " +
            "Error STDOUT: \(result.output ?? "nil"). Error STDERR: \(result.errorOutput ?? "nil")")
    )

    guard let outputString = result.output, !outputString.isEmpty else {
        #expect(Bool(false), Comment(rawValue: "Output was nil or empty for multiple input methods error test"))
        return
    }
    guard let responseData = outputString.data(using: String.Encoding.utf8) else {
        #expect(
            Bool(false),
            Comment(
                rawValue: "Failed to convert output to Data for multiple input methods error. Output: \(outputString)"
            )
        )
        return
    }
    let errorResponse = try JSONDecoder().decode(ErrorResponse.self, from: responseData)
    #expect(errorResponse.success == false)
    #expect(
        errorResponse.error.message.contains("Multiple input flags specified"),
        Comment(rawValue: "Unexpected error message: \(errorResponse.error.message)")
    )
}

@Test("Test Error: No Input Provided for Ping")
func errorNoInputProvidedForPing() async throws {
    let result = try runAXORCCommand(arguments: [])

    #expect(
        result.exitCode == 0,
        Comment(rawValue: "axorc should return 0 with error on stdout. Status: \(result.exitCode). " +
            "Error STDOUT: \(result.output ?? "nil"). Error STDERR: \(result.errorOutput ?? "nil")")
    )

    guard let outputString = result.output, !outputString.isEmpty else {
        #expect(Bool(false), Comment(rawValue: "Output was nil or empty for no input test."))
        return
    }
    guard let responseData = outputString.data(using: String.Encoding.utf8) else {
        #expect(
            Bool(false),
            Comment(rawValue: "Failed to convert output to Data for no input error. Output: \(outputString)")
        )
        return
    }
    let errorResponse = try JSONDecoder().decode(ErrorResponse.self, from: responseData)
    #expect(errorResponse.success == false)
    #expect(
        errorResponse.commandId == "input_error",
        Comment(rawValue: "Expected commandId to be input_error, got \(errorResponse.commandId)")
    )
    #expect(
        errorResponse.error.message.contains("No JSON input method specified"),
        Comment(rawValue: "Unexpected error message for no input: \(errorResponse.error.message)")
    )
}
