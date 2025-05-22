// InputHandler.swift - Handles input parsing for AXORC CLI

import Foundation

struct InputHandler {

    static func parseInput(
        stdin: Bool,
        file: String?,
        directPayload: String?,
        debug: Bool
    ) -> (jsonString: String?, sourceDescription: String, error: String?, debugLogs: [String]) {

        var localDebugLogs: [String] = []
        if debug {
            localDebugLogs.append("Debug logging enabled by --debug flag.")
        }

        var receivedJsonString: String?
        var inputSourceDescription: String = "Unspecified"
        var detailedInputError: String?

        let activeInputFlags = (stdin ? 1 : 0) + (file != nil ? 1 : 0)
        let positionalPayloadProvided = directPayload != nil &&
            !(directPayload?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)

        if activeInputFlags > 1 {
            detailedInputError = "Error: Multiple input flags specified (--stdin, --file). Only one is allowed."
            inputSourceDescription = detailedInputError!
        } else if stdin {
            inputSourceDescription = "STDIN"
            let stdInputHandle = FileHandle.standardInput
            let stdinData = stdInputHandle.readDataToEndOfFile()
            if let str = String(data: stdinData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !str.isEmpty {
                receivedJsonString = str
                if debug {
                    localDebugLogs.append("Successfully read \\(str.count) characters from STDIN.")
                }
            } else {
                detailedInputError = "No data received from STDIN or data was empty."
                if debug {
                    localDebugLogs.append("Failed to read from STDIN or received empty data.")
                }
            }
        } else if let filePath = file {
            inputSourceDescription = "File: \\(filePath)"
            do {
                let str = try String(contentsOfFile: filePath, encoding: .utf8)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !str.isEmpty {
                    receivedJsonString = str
                    if debug {
                        localDebugLogs.append("Successfully read \\(str.count) characters from file: \\(filePath)")
                    }
                } else {
                    detailedInputError = "File \\(filePath) is empty or contains only whitespace."
                    if debug {
                        localDebugLogs.append("File \\(filePath) was empty or contained only whitespace.")
                    }
                }
            } catch {
                detailedInputError = "Failed to read file \\(filePath): \\(error.localizedDescription)"
                if debug {
                    localDebugLogs.append("Error reading file \\(filePath): \\(error)")
                }
            }
        } else if positionalPayloadProvided {
            inputSourceDescription = "Direct argument"
            receivedJsonString = directPayload?.trimmingCharacters(in: .whitespacesAndNewlines)
            if debug {
                localDebugLogs.append("Using direct payload argument with \\(receivedJsonString?.count ?? 0) characters.")
            }
        } else {
            detailedInputError = "No input provided. Use --stdin, --file <path>, or provide JSON as a direct argument."
            inputSourceDescription = "No input"
            if debug {
                localDebugLogs.append("No input method specified and no direct payload provided.")
            }
        }

        return (receivedJsonString, inputSourceDescription, detailedInputError, localDebugLogs)
    }
}
