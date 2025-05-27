import AppKit
@testable import AXorcist
import Testing

// MARK: - Application Query Tests

@Test("Get All Running Applications")
func testGetAllApplications() async throws {
    let command = CommandEnvelope(
        commandId: "test-get-all-apps",
        command: .collectAll,
        debugLogging: true,
        locator: Locator(criteria: ["AXRole": "AXApplication"]),
        outputFormat: .verbose
    )

    let encoder = JSONEncoder()
    encoder.outputFormatting = .prettyPrinted
    let jsonData = try encoder.encode(command)
    guard let jsonString = String(data: jsonData, encoding: .utf8) else {
        throw TestError.generic("Failed to create JSON")
    }

    let result = try runAXORCCommand(arguments: [jsonString])

    #expect(result.exitCode == 0, "Command should succeed")
    #expect(result.output != nil, "Should have output")

    guard let output = result.output,
          let responseData = output.data(using: .utf8) else {
        throw TestError.generic("No output")
    }

    let response = try JSONDecoder().decode(SimpleSuccessResponse.self, from: responseData)

    #expect(response.success == true)
    #expect(response.data?["elements"] != nil, "Should have elements")

    if let elements = response.data?["elements"] as? [[String: Any]] {
        #expect(!elements.isEmpty, "Should have at least one application")

        // Check for Finder
        let appTitles = elements.compactMap { element -> String? in
            guard let attrs = element["attributes"] as? [String: Any] else { return nil }
            return attrs["AXTitle"] as? String
        }
        #expect(appTitles.contains("Finder"), "Finder should be running")
    }
}

@Test("Get Windows of TextEdit")
@MainActor
func testGetWindowsOfApplication() async throws {
    await closeTextEdit()
    try await Task.sleep(for: .milliseconds(500))

    let (pid, _) = try await setupTextEditAndGetInfo()
    defer {
        if let app = NSRunningApplication.runningApplications(withProcessIdentifier: pid).first {
            app.terminate()
        }
    }

    try await Task.sleep(for: .seconds(1))

    // Query for windows
    let command = CommandEnvelope(
        commandId: "test-get-windows",
        command: .query,
        application: "TextEdit",
        debugLogging: true,
        locator: Locator(criteria: ["AXRole": "AXWindow"]),
        outputFormat: .verbose
    )

    let encoder = JSONEncoder()
    let jsonData = try encoder.encode(command)
    guard let jsonString = String(data: jsonData, encoding: .utf8) else {
        throw TestError.generic("Failed to create JSON")
    }

    let result = try runAXORCCommand(arguments: [jsonString])

    #expect(result.exitCode == 0)

    guard let output = result.output,
          let responseData = output.data(using: .utf8) else {
        throw TestError.generic("No output")
    }

    let response = try JSONDecoder().decode(SimpleSuccessResponse.self, from: responseData)

    #expect(response.success == true)

    if let elements = response.data?["elements"] as? [[String: Any]] {
        #expect(!elements.isEmpty, "Should have at least one window")

        for window in elements {
            if let attrs = window["attributes"] as? [String: Any] {
                #expect(attrs["AXRole"] as? String == "AXWindow")
                #expect(attrs["AXTitle"] != nil, "Window should have title")
            }
        }
    }
}

@Test("Query Non-Existent Application")
func testQueryNonExistentApp() async throws {
    let command = CommandEnvelope(
        commandId: "test-nonexistent",
        command: .query,
        application: "NonExistentApp12345",
        debugLogging: true,
        locator: Locator(criteria: ["AXRole": "AXApplication"])
    )

    let encoder = JSONEncoder()
    let jsonData = try encoder.encode(command)
    guard let jsonString = String(data: jsonData, encoding: .utf8) else {
        throw TestError.generic("Failed to create JSON")
    }

    let result = try runAXORCCommand(arguments: [jsonString])

    // Command should succeed but return no elements
    #expect(result.exitCode == 0)

    guard let output = result.output,
          let responseData = output.data(using: .utf8) else {
        throw TestError.generic("No output")
    }

    let response = try JSONDecoder().decode(SimpleSuccessResponse.self, from: responseData)

    if response.success {
        if let elements = response.data?["elements"] as? [[String: Any]] {
            #expect(elements.isEmpty, "Should not find non-existent app")
        }
    }
}
