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
    let (output, errorOutput, terminationStatus) = try runAXORCCommandWithStdin(
        inputJSON: inputJSON,
        arguments: ["--stdin"]
    )

    #expect(
        terminationStatus == 0,
        "axorc command failed with status \(terminationStatus). Error: \(errorOutput ?? "N/A")"
    )
    #expect(errorOutput == nil || errorOutput!.isEmpty, "Expected no error output, but got: \(errorOutput!)")

    guard let outputString = output else {
        #expect(Bool(false), "Output was nil for ping via STDIN")
        return
    }

    guard let responseData = outputString.data(using: .utf8) else {
        #expect(Bool(false), "Failed to convert output to Data for ping via STDIN. Output: \(outputString)")
        return
    }
    let decodedResponse = try JSONDecoder().decode(SimpleSuccessResponse.self, from: responseData)
    #expect(decodedResponse.success == true)
    #expect(
        decodedResponse.message == "Ping handled by AXORCCommand. Input source: STDIN",
        "Unexpected success message: \(decodedResponse.message)"
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

    let (output, errorOutput, terminationStatus) = try runAXORCCommand(arguments: ["--file", tempFilePath])

    #expect(
        terminationStatus == 0,
        "axorc command failed with status \(terminationStatus). Error: \(errorOutput ?? "N/A")"
    )
    #expect(errorOutput == nil || errorOutput!.isEmpty, "Expected no error output, but got: \(errorOutput ?? "N/A")")

    guard let outputString = output else {
        #expect(Bool(false), "Output was nil for ping via file")
        return
    }
    guard let responseData = outputString.data(using: .utf8) else {
        #expect(Bool(false), "Failed to convert output to Data for ping via file. Output: \(outputString)")
        return
    }
    let decodedResponse = try JSONDecoder().decode(SimpleSuccessResponse.self, from: responseData)
    #expect(decodedResponse.success == true)
    #expect(
        decodedResponse.message.lowercased().contains("file: \(tempFilePath.lowercased())"),
        "Message should contain file path. Got: \(decodedResponse.message)"
    )
    #expect(decodedResponse.details == payloadMessage)
}

@Test("Test Ping via direct positional argument")
func pingViaDirectPayload() async throws {
    let payloadMessage = "Hello from testPingViaDirectPayload"
    let inputJSON =
        "{\"command_id\":\"test_ping_direct\",\"command\":\"ping\",\"payload\":{\"message\":\"\(payloadMessage)\"}}"

    let (output, errorOutput,
         terminationStatus) = try runAXORCCommand(arguments: [inputJSON])

    #expect(
        terminationStatus == 0,
        "axorc command failed with status \(terminationStatus). Error: \(errorOutput ?? "N/A")"
    )
    #expect(errorOutput == nil || errorOutput!.isEmpty, "Expected no error output, but got: \(errorOutput ?? "N/A")")

    guard let outputString = output else {
        #expect(Bool(false), "Output was nil for ping via direct payload")
        return
    }
    guard let responseData = outputString.data(using: .utf8) else {
        #expect(Bool(false), "Failed to convert output to Data for ping via direct payload. Output: \(outputString)")
        return
    }
    let decodedResponse = try JSONDecoder().decode(SimpleSuccessResponse.self, from: responseData)
    #expect(decodedResponse.success == true)
    #expect(
        decodedResponse.message.contains("Direct Argument Payload"),
        "Unexpected success message: \(decodedResponse.message)"
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

    let (output, errorOutput, terminationStatus) = try runAXORCCommandWithStdin(
        inputJSON: inputJSON,
        arguments: ["--file", tempFilePath]
    )

    #expect(
        terminationStatus == 0,
        "axorc command should return 0 with error on stdout. Status: \(terminationStatus). " +
            "Error STDOUT: \(output ?? "nil"). Error STDERR: \(errorOutput ?? "nil")"
    )

    guard let outputString = output, !outputString.isEmpty else {
        #expect(Bool(false), "Output was nil or empty for multiple input methods error test")
        return
    }
    guard let responseData = outputString.data(using: .utf8) else {
        #expect(
            Bool(false),
            "Failed to convert output to Data for multiple input methods error. Output: \(outputString)"
        )
        return
    }
    let errorResponse = try JSONDecoder().decode(ErrorResponse.self, from: responseData)
    #expect(errorResponse.success == false)
    #expect(
        errorResponse.error.message.contains("Multiple input flags specified"),
        "Unexpected error message: \(errorResponse.error.message)"
    )
}

@Test("Test Error: No Input Provided for Ping")
func errorNoInputProvidedForPing() async throws {
    let (output, errorOutput, terminationStatus) = try runAXORCCommand(arguments: [])

    #expect(
        terminationStatus == 0,
        "axorc should return 0 with error on stdout. Status: \(terminationStatus). " +
            "Error STDOUT: \(output ?? "nil"). Error STDERR: \(errorOutput ?? "nil")"
    )

    guard let outputString = output, !outputString.isEmpty else {
        #expect(Bool(false), "Output was nil or empty for no input test.")
        return
    }
    guard let responseData = outputString.data(using: .utf8) else {
        #expect(Bool(false), "Failed to convert output to Data for no input error. Output: \(outputString)")
        return
    }
    let errorResponse = try JSONDecoder().decode(ErrorResponse.self, from: responseData)
    #expect(errorResponse.success == false)
    #expect(
        errorResponse.commandId == "input_error",
        "Expected commandId to be input_error, got \(errorResponse.commandId)"
    )
    #expect(
        errorResponse.error.message.contains("No JSON input method specified"),
        "Unexpected error message for no input: \(errorResponse.error.message)"
    )
}
