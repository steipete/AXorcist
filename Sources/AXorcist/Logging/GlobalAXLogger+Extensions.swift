import Foundation

// Extension to GlobalAXLogger for additional functionality needed by the command system

extension GlobalAXLogger {
    // Properties for tracking state
    private static var _isLoggingEnabled: Bool = false
    private static var _detailLevel: AXLogDetailLevel = .normal
    private static var _currentCommandID: String?
    private static var _currentAppName: String?

    // MARK: - Logging Control

    public func isLoggingEnabled() async -> Bool {
        return Self._isLoggingEnabled
    }

    public func setLoggingEnabled(_ enabled: Bool) async {
        Self._isLoggingEnabled = enabled
    }

    public func getDetailLevel() async -> AXLogDetailLevel {
        return Self._detailLevel
    }

    public func setDetailLevel(_ level: AXLogDetailLevel) async {
        Self._detailLevel = level
    }

    // MARK: - Operation Context

    public func updateOperationDetails(commandID: String?, appName: String?) async {
        Self._currentCommandID = commandID
        Self._currentAppName = appName
    }

    // MARK: - Log Formatting

    public func getLogsAsStrings(
        format: AXLogOutputFormat,
        includeTimestamps: Bool = true,
        includeLevels: Bool = true,
        includeDetails: Bool = false,
        includeAppName: Bool = false,
        includeCommandID: Bool = false
    ) async -> [String] {
        let entries = await GlobalAXLogger.shared.getEntries()

        return entries.map { entry in
            var components: [String] = []

            if includeTimestamps {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
                components.append("[\(formatter.string(from: entry.timestamp))]")
            }

            if includeLevels {
                components.append("[\(entry.level.rawValue.uppercased())]")
            }

            if includeCommandID, let commandID = Self._currentCommandID {
                components.append("[CMD:\(commandID)]")
            }

            if includeAppName, let appName = Self._currentAppName {
                components.append("[APP:\(appName)]")
            }

            components.append(entry.message)

            if includeDetails, let details = entry.details, !details.isEmpty {
                let detailsStr = details.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
                components.append("{\(detailsStr)}")
            }

            return components.joined(separator: " ")
        }
    }

    internal func getLogEntriesAsJSON() async throws -> String {
        let entries = await GlobalAXLogger.shared.getEntries()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let jsonData = try encoder.encode(entries)
        return String(data: jsonData, encoding: .utf8) ?? "[]"
    }

    public func getLogsAsJSON() async throws -> String {
        return try await getLogEntriesAsJSON()
    }
}

// MARK: - Log Detail Level

public enum AXLogDetailLevel: String, Codable {
    case minimal
    case normal
    case verbose
}

// MARK: - Log Output Format

public enum AXLogOutputFormat: String, Codable {
    case text
    case json
}
