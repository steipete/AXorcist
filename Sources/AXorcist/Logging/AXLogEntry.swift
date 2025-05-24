import Foundation

public enum AXLogLevel: String, Codable, Sendable, CaseIterable {
    case debug
    case info
    case warning
    case error
    case critical // For errors that might lead to a crash or critical malfunction
}

public struct AXLogEntry: Codable, Sendable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let level: AXLogLevel
    public let message: String
    public let file: String?
    public let function: String?
    public let line: Int?
    public let details: [String: String]? // Optional dictionary for structured details

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        level: AXLogLevel,
        message: String,
        file: String? = #file,
        function: String? = #function,
        line: Int? = #line,
        details: [String: String]? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.message = message
        self.file = file?.components(separatedBy: "/").last // Store only the filename
        self.function = function
        self.line = line
        self.details = details
    }
}

// Add Equatable conformance
extension AXLogEntry: Equatable {
    public static func == (lhs: AXLogEntry, rhs: AXLogEntry) -> Bool {
        lhs.id == rhs.id
    }
}

// Example of how it might be formatted for text output
extension AXLogEntry {
    public func formattedForTextLog() -> String {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timeString = dateFormatter.string(from: timestamp)

        var logParts: [String] = [
            "[\(timeString)]",
            "[\(level.rawValue.uppercased())]"
        ]

        if let fileName = file, let lineNum = line {
            logParts.append("[\(fileName):\(lineNum)]")
        } else if let fileName = file {
            logParts.append("[\(fileName)]")
        }

        if let funcName = function {
            logParts.append("[\(funcName)]")
        }

        logParts.append("- \(message)")

        if let details = details, !details.isEmpty {
            logParts.append("Details: \(details.map { key, value in "\(key): \(value)" }.joined(separator: ", "))")
        }

        return logParts.joined(separator: " ")
    }
}
