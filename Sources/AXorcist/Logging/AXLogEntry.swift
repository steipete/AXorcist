import Foundation

public enum AXLogLevel: String, Codable, Sendable, CaseIterable {
    case debug
    case info
    case warning
    case error
    case critical // For errors that might lead to a crash or critical malfunction
}

// Added AXLogDetailLevel
public enum AXLogDetailLevel: String, Codable, Sendable, CaseIterable {
    case minimal // Only critical/error messages
    case normal // Info, warning, error, critical
    case verbose // Debug, info, warning, error, critical (all messages)
}

// Added AXLogOutputFormat
public enum AXLogOutputFormat: String, Codable, Sendable, CaseIterable {
    case text
    case json
}

public struct AXLogEntry: Codable, Sendable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let level: AXLogLevel
    public let message: String
    public let file: String?
    public let function: String?
    public let line: Int?
    public let details: [String: AnyCodable]? // Changed to AnyCodable

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        level: AXLogLevel,
        message: String,
        file: String? = #file,
        function: String? = #function,
        line: Int? = #line,
        details: [String: AnyCodable]? = nil // Changed to AnyCodable
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
            // Simplified details formatting for AnyCodable
            let detailString = details.map { key, value in
                let valueStr: String
                if let val = value.value as? String {
                    valueStr = val
                } else if let val = value.value as? CustomStringConvertible {
                    valueStr = val.description
                } else {
                    valueStr = String(describing: value.value)
                }
                return "\(key): \(valueStr)"
            }.joined(separator: ", ")
            logParts.append("Details: [\(detailString)]")
        }

        return logParts.joined(separator: " ")
    }
}
