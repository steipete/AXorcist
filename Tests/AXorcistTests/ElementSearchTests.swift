import AppKit
@testable import AXorcist
import Testing

// MARK: - Element Search and Navigation Tests

@Test("Search Elements by Role")
@MainActor
func testSearchElementsByRole() async throws {
    await closeTextEdit()
    try await Task.sleep(for: .milliseconds(500))
    
    let (pid, _) = try await setupTextEditAndGetInfo()
    defer { 
        if let app = NSRunningApplication.runningApplications(withProcessIdentifier: pid).first {
            app.terminate()
        }
    }
    
    try await Task.sleep(for: .seconds(1))
    
    // Search for buttons
    let command = CommandEnvelope(
        commandId: "test-search-buttons",
        command: .query,
        application: "TextEdit",
        debugLogging: true,
        locator: Locator(criteria: ["AXRole": "AXButton"]),
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
        #expect(!elements.isEmpty, "Should find buttons")
        
        for button in elements {
            if let attrs = button["attributes"] as? [String: Any] {
                #expect(attrs["AXRole"] as? String == "AXButton")
            }
        }
    }
}

@Test("Describe Element with Hierarchy")
@MainActor
func testDescribeElementHierarchy() async throws {
    await closeTextEdit()
    try await Task.sleep(for: .milliseconds(500))
    
    let (pid, _) = try await setupTextEditAndGetInfo()
    defer { 
        if let app = NSRunningApplication.runningApplications(withProcessIdentifier: pid).first {
            app.terminate()
        }
    }
    
    try await Task.sleep(for: .seconds(1))
    
    // Describe the application element
    let command = CommandEnvelope(
        commandId: "test-describe",
        command: .describeElement,
        application: "TextEdit",
        debugLogging: true,
        locator: Locator(criteria: ["AXRole": "AXApplication"]),
        maxDepth: 3,
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
    #expect(response.data != nil)
    
    // Check hierarchy
    if let data = response.data {
        if let attrs = data["attributes"] as? [String: Any] {
            #expect(attrs["AXRole"] as? String == "AXApplication")
        }
        
        if let children = data["children"] as? [[String: Any]] {
            #expect(!children.isEmpty, "App should have children")
            
            // Look for windows
            let windows = children.filter { child in
                if let childAttrs = child["attributes"] as? [String: Any],
                   let role = childAttrs["AXRole"] as? String {
                    return role == "AXWindow"
                }
                return false
            }
            
            #expect(!windows.isEmpty, "Should have windows")
        }
    }
}

@Test("Set and Verify Text Content")
@MainActor
func testSetAndVerifyText() async throws {
    await closeTextEdit()
    try await Task.sleep(for: .milliseconds(500))
    
    let (pid, _) = try await setupTextEditAndGetInfo()
    defer { 
        if let app = NSRunningApplication.runningApplications(withProcessIdentifier: pid).first {
            app.terminate()
        }
    }
    
    try await Task.sleep(for: .seconds(1))
    
    // Set text
    let setText = CommandEnvelope(
        commandId: "test-set-text",
        command: .performAction,
        application: "TextEdit",
        debugLogging: true,
        locator: Locator(criteria: ["AXRole": "AXTextArea"]),
        actionName: "AXSetValue",
        actionValue: AnyCodable("Hello from AXorcist tests!")
    )
    
    let encoder = JSONEncoder()
    var jsonData = try encoder.encode(setText)
    guard let setJsonString = String(data: jsonData, encoding: .utf8) else {
        throw TestError.generic("Failed to create JSON")
    }
    
    var result = try runAXORCCommand(arguments: [setJsonString])
    #expect(result.exitCode == 0)
    
    // Query to verify
    let queryText = CommandEnvelope(
        commandId: "test-query-text",
        command: .query,
        application: "TextEdit",
        debugLogging: true,
        locator: Locator(criteria: ["AXRole": "AXTextArea"]),
        outputFormat: .verbose
    )
    
    jsonData = try encoder.encode(queryText)
    guard let queryJsonString = String(data: jsonData, encoding: .utf8) else {
        throw TestError.generic("Failed to create JSON")
    }
    
    result = try runAXORCCommand(arguments: [queryJsonString])
    #expect(result.exitCode == 0)
    
    guard let output = result.output,
          let responseData = output.data(using: .utf8) else {
        throw TestError.generic("No output")
    }
    
    let response = try JSONDecoder().decode(SimpleSuccessResponse.self, from: responseData)
    
    if let elements = response.data?["elements"] as? [[String: Any]] {
        #expect(!elements.isEmpty)
        
        var foundText = false
        for element in elements {
            if let attrs = element["attributes"] as? [String: Any],
               let value = attrs["AXValue"] as? String {
                if value.contains("Hello from AXorcist tests!") {
                    foundText = true
                    break
                }
            }
        }
        
        #expect(foundText, "Should find the text we set")
    }
}

@Test("Extract Text from Window")
@MainActor
func testExtractText() async throws {
    await closeTextEdit()
    try await Task.sleep(for: .milliseconds(500))
    
    let (pid, _) = try await setupTextEditAndGetInfo()
    defer { 
        if let app = NSRunningApplication.runningApplications(withProcessIdentifier: pid).first {
            app.terminate()
        }
    }
    
    try await Task.sleep(for: .seconds(1))
    
    // Set some text first
    let setText = CommandEnvelope(
        commandId: "test-set-for-extract",
        command: .performAction,
        application: "TextEdit",
        debugLogging: true,
        locator: Locator(criteria: ["AXRole": "AXTextArea"]),
        actionName: "AXSetValue",
        actionValue: AnyCodable("This is test content.\nIt has multiple lines.\nExtract this text.")
    )
    
    let encoder = JSONEncoder()
    var jsonData = try encoder.encode(setText)
    guard let setJsonString = String(data: jsonData, encoding: .utf8) else {
        throw TestError.generic("Failed to create JSON")
    }
    
    _ = try runAXORCCommand(arguments: [setJsonString])
    
    // Extract text
    let extractCommand = CommandEnvelope(
        commandId: "test-extract",
        command: .extractText,
        application: "TextEdit",
        debugLogging: true,
        locator: Locator(criteria: ["AXRole": "AXWindow"]),
        outputFormat: .textContent
    )
    
    jsonData = try encoder.encode(extractCommand)
    guard let extractJsonString = String(data: jsonData, encoding: .utf8) else {
        throw TestError.generic("Failed to create JSON")
    }
    
    let result = try runAXORCCommand(arguments: [extractJsonString])
    #expect(result.exitCode == 0)
    
    guard let output = result.output,
          let responseData = output.data(using: .utf8) else {
        throw TestError.generic("No output")
    }
    
    let response = try JSONDecoder().decode(SimpleSuccessResponse.self, from: responseData)
    
    #expect(response.success == true)
    
    if let extractedText = response.data?["extractedText"] as? String {
        #expect(extractedText.contains("This is test content"))
        #expect(extractedText.contains("multiple lines"))
    }
}